const pool = require("../config/database");

/**
 * Validates whether a timezone string is a valid IANA timezone.
 * @param {string} timezone
 * @returns {boolean}
 */
function validateTimeZone(timezone) {
  if (!timezone || typeof timezone !== "string") return false;
  try {
    new Intl.DateTimeFormat(undefined, { timeZone: timezone.trim() });
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * Extracts date and hour parts for a timezone using Intl.DateTimeFormat.formatToParts.
 * @param {string} timezone
 * @param {Date} [date=new Date()]
 * @returns {{ year: string, month: string, day: string, hour: string }}
 */
function getTimeZoneParts(timezone, date = new Date()) {
  const validTz = validateTimeZone(timezone) ? timezone.trim() : "Asia/Kolkata";
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: validTz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
  });

  const parts = formatter.formatToParts(date);
  const partMap = {};
  for (const part of parts) {
    if (part.type !== "literal") {
      partMap[part.type] = part.value;
    }
  }

  return {
    year: partMap.year,
    month: partMap.month,
    day: partMap.day,
    hour: partMap.hour,
  };
}

/**
 * Gets the current calendar date in YYYY-MM-DD for a timezone.
 * @param {string} timezone
 * @param {Date} [date=new Date()]
 * @returns {string}
 */
function getLocalDateForTimeZone(timezone, date = new Date()) {
  const parts = getTimeZoneParts(timezone, date);
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/**
 * Gets the current hour (0-23) in a timezone.
 * @param {string} timezone
 * @param {Date} [date=new Date()]
 * @returns {number}
 */
function getLocalHourForTimeZone(timezone, date = new Date()) {
  const parts = getTimeZoneParts(timezone, date);
  return parseInt(parts.hour, 10);
}

/**
 * Calculates calendar day difference between expiry date and user local date.
 * Splits YYYY-MM-DD into numeric year/month/day before calling Date.UTC.
 * @param {string} expiryDateStr
 * @param {string} userLocalDateStr
 * @returns {number}
 */
function calculateDaysRemaining(expiryDateStr, userLocalDateStr) {
  const [ey, em, ed] = expiryDateStr.split("-").map(Number);
  const [uy, um, ud] = userLocalDateStr.split("-").map(Number);

  const expiryUtc = Date.UTC(ey, em - 1, ed);
  const userUtc = Date.UTC(uy, um - 1, ud);

  return Math.round((expiryUtc - userUtc) / (1000 * 60 * 60 * 24));
}

/**
 * Builds user-facing title, message, and type for a reminder.
 * @param {object} foodItem
 * @param {number} daysRemaining
 * @returns {{ title: string, message: string, type: string, offset: number }}
 */
function buildReminderMessage(foodItem, daysRemaining) {
  const name = foodItem.food_name;

  if (daysRemaining > 1) {
    return {
      title: `${name} Expiring Soon`,
      message: `${name} expires in ${daysRemaining} days.`,
      type: "expiring_soon",
      offset: daysRemaining,
    };
  }

  if (daysRemaining === 1) {
    return {
      title: `${name} Expiring Soon`,
      message: `${name} expires tomorrow.`,
      type: "expiring_soon",
      offset: 1,
    };
  }

  if (daysRemaining === 0) {
    return {
      title: `${name} Expires Today`,
      message: `${name} expires today.`,
      type: "expires_today",
      offset: 0,
    };
  }

  return {
    title: `${name} Expired`,
    message: `${name} has expired.`,
    type: "expired",
    offset: -1,
  };
}

/**
 * Generates applicable reminders for a user idempotently.
 * @param {number} userId
 * @param {object} [client=pool]
 * @returns {Promise<Array>} Newly created notification records
 */
async function generateRemindersForUser(userId, client = pool) {
  // 1. Ensure default preferences exist atomically
  await client.query(
    `INSERT INTO notification_preferences (
       user_id, notifications_enabled, browser_notifications_enabled,
       reminder_days, timezone, reminder_hour, updated_at
     )
     VALUES ($1, TRUE, FALSE, ARRAY[7, 3, 1, 0], 'Asia/Kolkata', 9, NOW())
     ON CONFLICT (user_id) DO NOTHING`,
    [userId]
  );

  const prefRes = await client.query(
    "SELECT * FROM notification_preferences WHERE user_id = $1",
    [userId]
  );

  const pref = prefRes.rows[0];
  if (!pref || !pref.notifications_enabled) {
    return [];
  }

  const timezone = validateTimeZone(pref.timezone) ? pref.timezone : "Asia/Kolkata";
  const userLocalDate = getLocalDateForTimeZone(timezone);
  const reminderDays = pref.reminder_days || [7, 3, 1, 0];

  // 2. Query active foods with formatted expiry date
  const foodRes = await client.query(
    `SELECT id, user_id, food_name, quantity,
            TO_CHAR(expiry_date, 'YYYY-MM-DD') AS expiry_date
     FROM food_items
     WHERE user_id = $1 AND status = 'active'`,
    [userId]
  );

  const createdNotifications = [];

  for (const food of foodRes.rows) {
    const daysRemaining = calculateDaysRemaining(food.expiry_date, userLocalDate);

    let applicable = false;
    let offset = null;

    if (reminderDays.includes(daysRemaining) && daysRemaining >= 0) {
      applicable = true;
      offset = daysRemaining;
    } else if (daysRemaining < 0) {
      // Create one expired reminder using offset -1
      applicable = true;
      offset = -1;
    }

    if (applicable && offset !== null) {
      const reminderData = buildReminderMessage(food, daysRemaining);

      const insertRes = await client.query(
        `INSERT INTO notifications (
           user_id, food_item_id, expiry_date, reminder_offset_days,
           type, title, message, is_read, created_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, FALSE, NOW())
         ON CONFLICT (user_id, food_item_id, expiry_date, reminder_offset_days)
         DO NOTHING
         RETURNING *`,
        [
          userId,
          food.id,
          food.expiry_date,
          reminderData.offset,
          reminderData.type,
          reminderData.title,
          reminderData.message,
        ]
      );

      if (insertRes.rows.length > 0) {
        createdNotifications.push(insertRes.rows[0]);
      }
    }
  }

  return createdNotifications;
}

/**
 * Runs reminder generation for all active users whose local hour matches reminder_hour.
 * @returns {Promise<{ processed: number, created: number }>}
 */
async function generateRemindersForAllUsers() {
  const usersRes = await pool.query(
    `SELECT np.user_id, np.timezone, np.reminder_hour
     FROM notification_preferences np
     JOIN users u ON np.user_id = u.id
     WHERE np.notifications_enabled = TRUE`
  );

  let processed = 0;
  let created = 0;

  for (const user of usersRes.rows) {
    try {
      const localHour = getLocalHourForTimeZone(user.timezone);
      if (localHour === user.reminder_hour) {
        const newReminders = await generateRemindersForUser(user.user_id);
        processed++;
        created += newReminders.length;
      }
    } catch (err) {
      // Safe error summary without logging credentials or complete request dumps
      console.error(
        `Reminder generation failed for user ${user.user_id}:`,
        err.message
      );
    }
  }

  return { processed, created };
}

/**
 * Removes stale unread reminders for a food item.
 * Preserves already-read notification history.
 * @param {number} foodItemId
 * @param {number} userId
 * @param {object} [client=pool]
 * @returns {Promise<number>} Number of deleted notifications
 */
async function removeStaleUnreadReminders(foodItemId, userId, client = pool) {
  const result = await client.query(
    `DELETE FROM notifications
     WHERE food_item_id = $1 AND user_id = $2 AND is_read = FALSE
     RETURNING id`,
    [foodItemId, userId]
  );
  return result.rows.length;
}

module.exports = {
  validateTimeZone,
  getTimeZoneParts,
  getLocalDateForTimeZone,
  getLocalHourForTimeZone,
  calculateDaysRemaining,
  buildReminderMessage,
  generateRemindersForUser,
  generateRemindersForAllUsers,
  removeStaleUnreadReminders,
};
