const cron = require("node-cron");
const { generateRemindersForAllUsers } = require("../services/reminderService");

let scheduledTask = null;

/**
 * Starts the hourly reminder scheduler.
 * Runs hourly (0 * * * *), checking each user's local hour against their configured reminder_hour.
 *
 * NOTE: The reminder scheduler operates only while the Node.js backend process is active.
 * On-demand generation occurs whenever a user fetches their notifications or unread count.
 */
function startReminderScheduler() {
  // Never start background cron jobs during test execution
  if (process.env.NODE_ENV === "test") {
    return null;
  }

  // Allow explicit opt-out
  if (process.env.ENABLE_REMINDER_SCHEDULER === "false") {
    console.log("Reminder scheduler disabled via ENABLE_REMINDER_SCHEDULER=false.");
    return null;
  }

  // Prevent duplicate cron tasks
  if (scheduledTask) {
    return scheduledTask;
  }

  // Schedule to run at minute 0 of every hour
  scheduledTask = cron.schedule("0 * * * *", async () => {
    try {
      const summary = await generateRemindersForAllUsers();
      if (summary.created > 0) {
        console.log(
          `[Scheduler] Processed ${summary.processed} users, generated ${summary.created} reminders.`
        );
      }
    } catch (err) {
      // Safe error summary - Express server will not crash
      console.error("[Scheduler] Error running hourly reminder generation:", err.message);
    }
  });

  console.log("Hourly reminder scheduler started successfully (0 * * * *).");
  return scheduledTask;
}

/**
 * Stops the running reminder scheduler if active.
 */
function stopReminderScheduler() {
  if (scheduledTask) {
    scheduledTask.stop();
    scheduledTask = null;
  }
}

module.exports = {
  startReminderScheduler,
  stopReminderScheduler,
};
