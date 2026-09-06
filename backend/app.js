const express = require("express");
const pool = require("./config/database");
const { corsMiddleware } = require("./config/corsConfig");
const authRoutes = require("./routes/auth");
const foodRoutes = require("./routes/foods");
const notificationRoutes = require("./routes/notifications");

const app = express();

// Apply CORS & body parsing middleware
app.use(corsMiddleware);
app.use(express.json());

// Base health check
app.get("/", (req, res) => {
  res.json({
    message: "FreshTrack authentication server is running",
  });
});

// Database connectivity check
app.get("/api/database-test", async (req, res, next) => {
  try {
    const result = await pool.query("SELECT NOW() AS current_time");
    res.json({
      message: "PostgreSQL connected successfully",
      databaseTime: result.rows[0].current_time,
    });
  } catch (error) {
    next(error);
  }
});

// Mount Authentication Routes
app.use("/api/auth", authRoutes);

// Mount Food Inventory Routes
app.use("/api/foods", foodRoutes);

// Mount Notification & Reminder Preferences Routes
app.use("/api", notificationRoutes);

// 404 Route Handler
app.use((req, res) => {
  res.status(404).json({
    message: `Cannot ${req.method} ${req.originalUrl}`,
  });
});

// Centralized Sanitized Error Handling Middleware
function errorHandler(err, req, res, next) {
  const statusCode = err.statusCode || err.status || 500;

  // Sanitized server-side diagnostic logging (no passwords or credentials logged)
  console.error(`[API Error] ${req.method} ${req.originalUrl}:`, err.message || err);

  // Return generic sanitized message for 500 or unhandled errors
  if (statusCode >= 500) {
    return res.status(500).json({
      message: "An internal server error occurred.",
    });
  }

  // Client errors (4xx): sanitize message to ensure no database or internal leak
  const msg = err.message ? String(err.message) : "Request failed.";
  const isInternalLeak =
    msg.includes("SELECT") ||
    msg.includes("INSERT") ||
    msg.includes("UPDATE") ||
    msg.includes("DELETE") ||
    msg.includes("relation") ||
    msg.includes("syntax error") ||
    msg.includes("pg_") ||
    msg.includes("column");

  if (isInternalLeak) {
    return res.status(500).json({
      message: "An internal server error occurred.",
    });
  }

  res.status(statusCode).json({
    message: msg,
  });
}

app.use(errorHandler);

module.exports = app;
module.exports.errorHandler = errorHandler;
