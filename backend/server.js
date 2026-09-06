require("dotenv").config();

const { validateEnv } = require("./config/envValidator");

// 1. Fail-fast environment validation
try {
  validateEnv();
} catch (err) {
  console.error("FATAL CONFIGURATION ERROR:", err.message);
  process.exit(1);
}

const app = require("./app");

// 2. Start Hourly Reminder Scheduler (disabled during test runs)
const { startReminderScheduler } = require("./jobs/reminderScheduler");
if (process.env.NODE_ENV !== "test") {
  startReminderScheduler();
}

// 3. Start Periodic OTP & Pending Registration Cleanup (runs daily at 3 AM, disabled in test)
const { cleanExpiredOtpAndRegistrations } = require("./jobs/otpCleanupJob");
const cron = require("node-cron");
if (process.env.NODE_ENV !== "test") {
  cleanExpiredOtpAndRegistrations();
  cron.schedule("0 3 * * *", () => {
    cleanExpiredOtpAndRegistrations();
  });
}

const PORT = parseInt(process.env.PORT || "5000", 10);

const server = app.listen(PORT, () => {
  console.log(`FreshTrack server running on http://localhost:${PORT}`);
});

module.exports = server;
