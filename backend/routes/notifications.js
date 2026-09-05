const express = require("express");
const pool = require("../config/database");
const authenticateToken = require("../middleware/auth");
const {
  validateTimeZone,
  generateRemindersForUser,
} = require("../services/reminderService");

const router = express.Router();

// Enforce authentication for all notification routes
router.use(authenticateToken);

const VALID_NOTIFICATION_TYPES = ["expiring_soon", "expires_today", "expired"];
const ALLOWED_REMINDER_OFFSETS = [0, 1, 3, 7];

// Strict reject for client-supplied user_id or userId across body, query, and params
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

// Validate req.user.id middleware
router.use((req, res, next) => {
  const userId = req.user && req.user.id;
  if (!Number.isInteger(userId) || userId <= 0) {
    return res.status(401).json({ message: "Invalid user authentication." });
  }
  next();
});

// GET /api/notifications - List notifications for authenticated user
router.get("/notifications", async (req, res, next) => {
  try {
    const userId = req.user.id;

    // Trigger on-demand idempotent generation
    await generateRemindersForUser(userId);

    const { unread, type, limit = 30, offset = 0 } = req.query;

    const parsedLimit = parseInt(limit, 10);
    const parsedOffset = parseInt(offset, 10);

    if (
      !Number.isInteger(parsedLimit) ||
      parsedLimit < 1 ||
      parsedLimit > 100
    ) {
      return res.status(400).json({
        message: "Limit must be a positive integer between 1 and 100.",
      });
    }

    if (!Number.isInteger(parsedOffset) || parsedOffset < 0) {
      return res.status(400).json({
        message: "Offset must be a non-negative integer.",
      });
    }

    let queryText = `
      SELECT
        n.id,
        n.user_id,
        n.food_item_id,
        TO_CHAR(n.expiry_date, 'YYYY-MM-DD') AS expiry_date,
        n.reminder_offset_days,
        n.type,
        n.title,
        n.message,
        n.is_read,
        n.created_at,
        f.food_name,
        f.category,
        f.quantity,
        f.storage_location,
        f.status AS food_status
      FROM notifications n
      LEFT JOIN food_items f ON n.food_item_id = f.id
      WHERE n.user_id = $1
    `;

    const queryParams = [userId];
    let paramIndex = 2;

    if (unread !== undefined && unread !== "") {
      const isUnread = unread === "true";
      queryText += ` AND n.is_read = $${paramIndex++}`;
      queryParams.push(!isUnread);
    }

    if (type) {
      const normalizedType = type.trim().toLowerCase();
      if (!VALID_NOTIFICATION_TYPES.includes(normalizedType)) {
        return res.status(400).json({
          message: `Invalid notification type filter. Permitted: ${VALID_NOTIFICATION_TYPES.join(
            ", "
          )}.`,
        });
      }
      queryText += ` AND n.type = $${paramIndex++}`;
      queryParams.push(normalizedType);
    }

    // Count matching query before pagination
    const countSql = `SELECT COUNT(*)::int AS total FROM (${queryText}) AS filtered`;
    const countResult = await pool.query(countSql, queryParams);
    const total = countResult.rows[0].total;

    // Apply sorting and pagination
    queryText += ` ORDER BY n.created_at DESC, n.id DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
    queryParams.push(parsedLimit, parsedOffset);

    const result = await pool.query(queryText, queryParams);

    // Get unread count for user
    const unreadResult = await pool.query(
      "SELECT COUNT(*)::int AS unread_count FROM notifications WHERE user_id = $1 AND is_read = FALSE",
      [userId]
    );
    const unreadCount = unreadResult.rows[0].unread_count;

    return res.json({
      notifications: result.rows,
      unread_count: unreadCount,
      total,
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/notifications/unread-count - Fetch unread badge count
router.get("/notifications/unread-count", async (req, res, next) => {
  try {
    const userId = req.user.id;

    // Call on-demand idempotent generation before counting
    await generateRemindersForUser(userId);

    const result = await pool.query(
      "SELECT COUNT(*)::int AS unread_count FROM notifications WHERE user_id = $1 AND is_read = FALSE",
      [userId]
    );

    return res.json({
      unread_count: result.rows[0].unread_count,
    });
  } catch (error) {
    next(error);
  }
});

// PATCH /api/notifications/read-all - Mark all notifications read
// IMPORTANT: Defined before /:id/read to prevent route conflict
router.patch("/notifications/read-all", async (req, res, next) => {
  try {
    const userId = req.user.id;

    const result = await pool.query(
      "UPDATE notifications SET is_read = TRUE WHERE user_id = $1 AND is_read = FALSE RETURNING id",
      [userId]
    );

    return res.json({
      message: "All notifications marked as read.",
      updated_count: result.rows.length,
    });
  } catch (error) {
    next(error);
  }
});

// PATCH /api/notifications/:id/read - Mark individual notification as read
router.patch("/notifications/:id/read", async (req, res, next) => {
  try {
    const notifId = parseInt(req.params.id, 10);
    if (!Number.isInteger(notifId) || notifId <= 0) {
      return res.status(400).json({
        message: "Invalid notification ID.",
      });
    }

    const result = await pool.query(
      `UPDATE notifications
       SET is_read = TRUE
       WHERE id = $1 AND user_id = $2
       RETURNING
         id, user_id, food_item_id,
         TO_CHAR(expiry_date, 'YYYY-MM-DD') AS expiry_date,
         reminder_offset_days, type, title, message, is_read, created_at`,
      [notifId, req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "Notification not found.",
      });
    }

    return res.json(result.rows[0]);
  } catch (error) {
    next(error);
  }
});

// DELETE /api/notifications/:id - Delete individual notification
router.delete("/notifications/:id", async (req, res, next) => {
  try {
    const notifId = parseInt(req.params.id, 10);
    if (!Number.isInteger(notifId) || notifId <= 0) {
      return res.status(400).json({
        message: "Invalid notification ID.",
      });
    }

    const result = await pool.query(
      "DELETE FROM notifications WHERE id = $1 AND user_id = $2 RETURNING id",
      [notifId, req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "Notification not found.",
      });
    }

    return res.json({
      message: "Notification deleted successfully.",
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/notification-preferences - Get user's reminder preferences
router.get("/notification-preferences", async (req, res, next) => {
  try {
    const userId = req.user.id;

    // Atomically ensure default preference row exists
    await pool.query(
      `INSERT INTO notification_preferences (
         user_id, notifications_enabled, browser_notifications_enabled,
         reminder_days, timezone, reminder_hour, updated_at
       )
       VALUES ($1, TRUE, FALSE, ARRAY[7, 3, 1, 0], 'Asia/Kolkata', 9, NOW())
       ON CONFLICT (user_id) DO NOTHING`,
      [userId]
    );

    const result = await pool.query(
      `SELECT user_id, notifications_enabled, browser_notifications_enabled,
              reminder_days, timezone, reminder_hour, updated_at
       FROM notification_preferences
       WHERE user_id = $1`,
      [userId]
    );

    const pref = result.rows[0];
    // Return sorted reminder days consistently
    if (Array.isArray(pref.reminder_days)) {
      pref.reminder_days.sort((a, b) => b - a);
    }

    return res.json(pref);
  } catch (error) {
    next(error);
  }
});

// PUT /api/notification-preferences - Update user's reminder preferences
router.put("/notification-preferences", rejectUserId, async (req, res, next) => {
  try {
    const userId = req.user.id;
    const {
      notifications_enabled,
      browser_notifications_enabled,
      reminder_days,
      timezone,
      reminder_hour,
    } = req.body;

    // Strict boolean validation
    if (typeof notifications_enabled !== "boolean") {
      return res.status(400).json({
        message: "notifications_enabled must be a boolean (true or false).",
      });
    }

    if (typeof browser_notifications_enabled !== "boolean") {
      return res.status(400).json({
        message:
          "browser_notifications_enabled must be a boolean (true or false).",
      });
    }

    // Strict reminder_days validation: non-empty array containing only 0, 1, 3, 7
    if (!Array.isArray(reminder_days) || reminder_days.length === 0) {
      return res.status(400).json({
        message: "reminder_days must be a non-empty array of integers.",
      });
    }

    for (const day of reminder_days) {
      if (typeof day !== "number" || !ALLOWED_REMINDER_OFFSETS.includes(day)) {
        return res.status(400).json({
          message: `reminder_days may only contain values from: [${ALLOWED_REMINDER_OFFSETS.join(
            ", "
          )}]. Found invalid value: ${day}.`,
        });
      }
    }

    // Deduplicate and sort descending consistently [7, 3, 1, 0]
    const cleanReminderDays = Array.from(new Set(reminder_days)).sort(
      (a, b) => b - a
    );

    // Timezone validation
    if (!timezone || typeof timezone !== "string" || !validateTimeZone(timezone)) {
      return res.status(400).json({
        message:
          "A valid IANA timezone (e.g. 'Asia/Kolkata', 'UTC', 'America/New_York') is required.",
      });
    }

    // Reminder hour validation
    const parsedHour = Number(reminder_hour);
    if (!Number.isInteger(parsedHour) || parsedHour < 0 || parsedHour > 23) {
      return res.status(400).json({
        message: "reminder_hour must be an integer between 0 and 23.",
      });
    }

    const result = await pool.query(
      `INSERT INTO notification_preferences (
         user_id, notifications_enabled, browser_notifications_enabled,
         reminder_days, timezone, reminder_hour, updated_at
       )
       VALUES ($1, $2, $3, $4, $5, $6, NOW())
       ON CONFLICT (user_id) DO UPDATE SET
         notifications_enabled = EXCLUDED.notifications_enabled,
         browser_notifications_enabled = EXCLUDED.browser_notifications_enabled,
         reminder_days = EXCLUDED.reminder_days,
         timezone = EXCLUDED.timezone,
         reminder_hour = EXCLUDED.reminder_hour,
         updated_at = NOW()
       RETURNING user_id, notifications_enabled, browser_notifications_enabled,
                 reminder_days, timezone, reminder_hour, updated_at`,
      [
        userId,
        notifications_enabled,
        browser_notifications_enabled,
        cleanReminderDays,
        timezone.trim(),
        parsedHour,
      ]
    );

    const updated = result.rows[0];
    if (Array.isArray(updated.reminder_days)) {
      updated.reminder_days.sort((a, b) => b - a);
    }

    return res.json(updated);
  } catch (error) {
    next(error);
  }
});

module.exports = router;
