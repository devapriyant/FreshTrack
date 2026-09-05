require("dotenv").config();

const express = require("express");
const cors = require("cors");
const pool = require("./config/database");
const authRoutes = require("./routes/auth");
const foodRoutes = require("./routes/foods");

const app = express();

app.use(cors());
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
const notificationRoutes = require("./routes/notifications");
app.use("/api", notificationRoutes);

// Start Hourly Reminder Scheduler (disabled during test runs)
const { startReminderScheduler } = require("./jobs/reminderScheduler");
startReminderScheduler();

// Start Periodic OTP & Pending Registration Cleanup (runs daily at 3 AM, disabled in test)
const { cleanExpiredOtpAndRegistrations } = require("./jobs/otpCleanupJob");
const cron = require("node-cron");
if (process.env.NODE_ENV !== "test") {
  cleanExpiredOtpAndRegistrations();
  cron.schedule("0 3 * * *", () => {
    cleanExpiredOtpAndRegistrations();
  });
}

// 404 Route Handler
app.use((req, res) => {
  res.status(404).json({
    message: `Cannot ${req.method} ${req.originalUrl}`,
  });
});

// Centralized Error Handling Middleware
app.use((err, req, res, next) => {
  // Do not log passwords, tokens, or sensitive credentials
  console.error("API Error:", err.message);

  const statusCode = err.statusCode || err.status || 500;
  res.status(statusCode).json({
    message: err.message || "An internal server error occurred.",
  });
});

const PORT = process.env.PORT || 5000;

app.listen(PORT, () => {
  console.log(`FreshTrack server running on http://localhost:${PORT}`);
});
