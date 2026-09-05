const express = require("express");
const pool = require("../config/database");
const authenticateToken = require("../middleware/auth");
const {
  removeStaleUnreadReminders,
  generateRemindersForUser,
} = require("../services/reminderService");

const router = express.Router();

// 1. Protect every food route with JWT authentication
router.use(authenticateToken);

// 2. Comprehensive check: Reject any client-supplied user_id or userId in body, query, or params
function rejectUserId(req, res, next) {
  const hasUserId = (obj) => {
    if (!obj || typeof obj !== "object") return false;
    return (
      Object.prototype.hasOwnProperty.call(obj, "user_id") ||
      Object.prototype.hasOwnProperty.call(obj, "userId")
    );
  };

  if (hasUserId(req.body) || hasUserId(req.query) || hasUserId(req.params)) {
    return res.status(400).json({
      message:
        "Explicitly providing user_id is not permitted. Authentication token is used instead.",
    });
  }
  next();
}

router.use(rejectUserId);

const VALID_STATUSES = ["active", "consumed", "discarded"];

// Strict YYYY-MM-DD calendar date validator
function isValidDateString(dateStr) {
  if (typeof dateStr !== "string") return false;
  const regex = /^\d{4}-\d{2}-\d{2}$/;
  if (!regex.test(dateStr)) return false;

  const [yearStr, monthStr, dayStr] = dateStr.split("-");
  const year = parseInt(yearStr, 10);
  const month = parseInt(monthStr, 10);
  const day = parseInt(dayStr, 10);

  if (month < 1 || month > 12) return false;
  if (day < 1 || day > 31) return false;

  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

// POST /api/foods - Add a new food item
router.post("/", async (req, res, next) => {
  try {
    const userId = req.user && req.user.id;
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ message: "Invalid user authentication." });
    }

    const {
      food_name,
      category,
      quantity = 1,
      purchase_date,
      expiry_date,
      storage_location,
      notes,
    } = req.body;

    if (
      !food_name ||
      typeof food_name !== "string" ||
      food_name.trim().length === 0
    ) {
      return res.status(400).json({
        message: "Food name is required.",
      });
    }

    const parsedQuantity = Number(quantity);
    if (!Number.isInteger(parsedQuantity) || parsedQuantity <= 0) {
      return res.status(400).json({
        message: "Quantity must be a positive whole number.",
      });
    }

    if (!expiry_date || !isValidDateString(expiry_date)) {
      return res.status(400).json({
        message: "A valid expiry date in YYYY-MM-DD format is required.",
      });
    }

    if (purchase_date) {
      if (!isValidDateString(purchase_date)) {
        return res.status(400).json({
          message: "Purchase date must be in valid YYYY-MM-DD format.",
        });
      }
      if (purchase_date > expiry_date) {
        return res.status(400).json({
          message: "Purchase date cannot be after expiry date.",
        });
      }
    }

    const result = await pool.query(
      `INSERT INTO food_items (
        user_id,
        food_name,
        category,
        quantity,
        purchase_date,
        expiry_date,
        storage_location,
        status,
        notes,
        created_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'active', $8, NOW(), NOW())
      RETURNING *`,
      [
        userId,
        food_name.trim(),
        category && typeof category === "string" && category.trim().length > 0
          ? category.trim()
          : null,
        parsedQuantity,
        purchase_date || null,
        expiry_date,
        storage_location &&
        typeof storage_location === "string" &&
        storage_location.trim().length > 0
          ? storage_location.trim()
          : null,
        notes && typeof notes === "string" && notes.trim().length > 0
          ? notes.trim()
          : null,
      ]
    );

    return res.status(201).json(result.rows[0]);
  } catch (error) {
    next(error);
  }
});

// GET /api/foods - List food items for authenticated user
router.get("/", async (req, res, next) => {
  try {
    const userId = req.user && req.user.id;
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ message: "Invalid user authentication." });
    }

    const { status, category, storage_location, search } = req.query;

    let queryText = `SELECT * FROM food_items WHERE user_id = $1`;
    const queryParams = [userId];
    let paramIndex = 2;

    if (status) {
      const normalizedStatus = status.trim().toLowerCase();
      if (!VALID_STATUSES.includes(normalizedStatus)) {
        return res.status(400).json({
          message: `Invalid status filter. Permitted values: ${VALID_STATUSES.join(
            ", "
          )}.`,
        });
      }
      queryText += ` AND status = $${paramIndex++}`;
      queryParams.push(normalizedStatus);
    }

    if (category && category.trim().length > 0) {
      queryText += ` AND category = $${paramIndex++}`;
      queryParams.push(category.trim());
    }

    if (storage_location && storage_location.trim().length > 0) {
      queryText += ` AND storage_location = $${paramIndex++}`;
      queryParams.push(storage_location.trim());
    }

    if (search && search.trim().length > 0) {
      queryText += ` AND food_name ILIKE $${paramIndex++}`;
      queryParams.push(`%${search.trim()}%`);
    }

    queryText += ` ORDER BY expiry_date ASC, created_at DESC`;

    const result = await pool.query(queryText, queryParams);

    return res.json({
      items: result.rows,
      count: result.rows.length,
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/foods/:id - Get a specific food item owned by user
router.get("/:id", async (req, res, next) => {
  try {
    const userId = req.user && req.user.id;
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ message: "Invalid user authentication." });
    }

    const foodId = parseInt(req.params.id, 10);
    if (!Number.isInteger(foodId) || foodId <= 0) {
      return res.status(400).json({
        message: "Invalid food item ID.",
      });
    }

    const result = await pool.query(
      `SELECT * FROM food_items WHERE id = $1 AND user_id = $2`,
      [foodId, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "Food item not found.",
      });
    }

    return res.json(result.rows[0]);
  } catch (error) {
    next(error);
  }
});

// PUT /api/foods/:id - Full update of a food item owned by user
router.put("/:id", async (req, res, next) => {
  const userId = req.user && req.user.id;
  if (!Number.isInteger(userId) || userId <= 0) {
    return res.status(401).json({ message: "Invalid user authentication." });
  }

  const foodId = parseInt(req.params.id, 10);
  if (!Number.isInteger(foodId) || foodId <= 0) {
    return res.status(400).json({
      message: "Invalid food item ID.",
    });
  }

  const {
    food_name,
    category,
    quantity,
    purchase_date,
    expiry_date,
    storage_location,
    notes,
  } = req.body;

  if (
    !food_name ||
    typeof food_name !== "string" ||
    food_name.trim().length === 0
  ) {
    return res.status(400).json({
      message: "Food name is required.",
    });
  }

  const parsedQuantity = Number(quantity);
  if (!Number.isInteger(parsedQuantity) || parsedQuantity <= 0) {
    return res.status(400).json({
      message: "Quantity must be a positive whole number.",
    });
  }

  if (!expiry_date || !isValidDateString(expiry_date)) {
    return res.status(400).json({
      message: "A valid expiry date in YYYY-MM-DD format is required.",
    });
  }

  if (purchase_date) {
    if (!isValidDateString(purchase_date)) {
      return res.status(400).json({
        message: "Purchase date must be in valid YYYY-MM-DD format.",
      });
    }
    if (purchase_date > expiry_date) {
      return res.status(400).json({
        message: "Purchase date cannot be after expiry date.",
      });
    }
  }

  const cleanCategory =
    category && typeof category === "string" && category.trim().length > 0
      ? category.trim()
      : null;

  const cleanStorageLocation =
    storage_location &&
    typeof storage_location === "string" &&
    storage_location.trim().length > 0
      ? storage_location.trim()
      : null;

  const cleanNotes =
    notes && typeof notes === "string" && notes.trim().length > 0
      ? notes.trim()
      : null;

  const client = await pool.connect();
  let expiryChanged = false;
  let updatedFood = null;

  try {
    await client.query("BEGIN");

    const existing = await client.query(
      "SELECT id, TO_CHAR(expiry_date, 'YYYY-MM-DD') AS expiry_date FROM food_items WHERE id = $1 AND user_id = $2 FOR UPDATE",
      [foodId, userId]
    );

    if (existing.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        message: "Food item not found.",
      });
    }

    const oldExpiry = existing.rows[0].expiry_date;
    expiryChanged = oldExpiry !== expiry_date;

    const result = await client.query(
      `UPDATE food_items
       SET food_name = $1,
           category = $2,
           quantity = $3,
           purchase_date = $4,
           expiry_date = $5,
           storage_location = $6,
           notes = $7,
           updated_at = NOW()
       WHERE id = $8 AND user_id = $9
       RETURNING *`,
      [
        food_name.trim(),
        cleanCategory,
        parsedQuantity,
        purchase_date || null,
        expiry_date,
        cleanStorageLocation,
        cleanNotes,
        foodId,
        userId,
      ]
    );

    updatedFood = result.rows[0];

    // Delete unread reminders ONLY if expiry date actually changed
    if (expiryChanged) {
      await removeStaleUnreadReminders(foodId, userId, client);
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    return next(error);
  } finally {
    client.release();
  }

  // Decoupled post-commit reminder generation
  if (expiryChanged && updatedFood.status === "active") {
    try {
      await generateRemindersForUser(userId);
    } catch (genErr) {
      console.error("Post-commit reminder generation failed:", genErr.message);
    }
  }

  return res.json(updatedFood);
});

// PATCH /api/foods/:id/status - Update food item lifecycle status owned by user
router.patch("/:id/status", async (req, res, next) => {
  const userId = req.user && req.user.id;
  if (!Number.isInteger(userId) || userId <= 0) {
    return res.status(401).json({ message: "Invalid user authentication." });
  }

  const foodId = parseInt(req.params.id, 10);
  if (!Number.isInteger(foodId) || foodId <= 0) {
    return res.status(400).json({
      message: "Invalid food item ID.",
    });
  }

  const { status } = req.body;
  if (!status || typeof status !== "string") {
    return res.status(400).json({
      message: `Status is required. Permitted values: ${VALID_STATUSES.join(
        ", "
      )}.`,
    });
  }

  const normalizedStatus = status.trim().toLowerCase();
  if (!VALID_STATUSES.includes(normalizedStatus)) {
    return res.status(400).json({
      message: `Invalid status. Permitted values: ${VALID_STATUSES.join(
        ", "
      )}.`,
    });
  }

  const client = await pool.connect();
  let shouldRegenerate = false;
  let updatedFood = null;

  try {
    await client.query("BEGIN");

    // SELECT complete row using id AND user_id FOR UPDATE
    const existing = await client.query(
      "SELECT * FROM food_items WHERE id = $1 AND user_id = $2 FOR UPDATE",
      [foodId, userId]
    );

    if (existing.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        message: "Food item not found.",
      });
    }

    const existingItem = existing.rows[0];
    const oldStatus = existingItem.status;

    // Check active -> active: commit without updating, return already-owned row
    if (oldStatus === "active" && normalizedStatus === "active") {
      await client.query("COMMIT");
      return res.json(existingItem);
    }

    const result = await client.query(
      `UPDATE food_items
       SET status = $1,
           updated_at = NOW()
       WHERE id = $2 AND user_id = $3
       RETURNING *`,
      [normalizedStatus, foodId, userId]
    );

    updatedFood = result.rows[0];

    // Delete unread reminders only when changing to consumed or discarded
    if (normalizedStatus === "consumed" || normalizedStatus === "discarded") {
      await removeStaleUnreadReminders(foodId, userId, client);
    }

    // Flag regeneration ONLY for real non-active -> active transition
    if (oldStatus !== "active" && normalizedStatus === "active") {
      shouldRegenerate = true;
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    return next(error);
  } finally {
    client.release();
  }

  // Decoupled post-commit reminder generation
  if (shouldRegenerate) {
    try {
      await generateRemindersForUser(userId);
    } catch (genErr) {
      console.error("Post-commit reminder generation failed:", genErr.message);
    }
  }

  return res.json(updatedFood);
});

// DELETE /api/foods/:id - Delete a food item owned by user
router.delete("/:id", async (req, res, next) => {
  try {
    const userId = req.user && req.user.id;
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ message: "Invalid user authentication." });
    }

    const foodId = parseInt(req.params.id, 10);
    if (!Number.isInteger(foodId) || foodId <= 0) {
      return res.status(400).json({
        message: "Invalid food item ID.",
      });
    }

    const result = await pool.query(
      `DELETE FROM food_items
       WHERE id = $1 AND user_id = $2
       RETURNING id`,
      [foodId, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "Food item not found.",
      });
    }

    return res.json({
      message: "Food item deleted successfully.",
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
