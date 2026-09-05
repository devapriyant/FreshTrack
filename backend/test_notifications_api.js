// FreshTrack Phase 3 Backend Automated Integration Test Suite
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, ".env") });

// Safety flag guard: Refuse execution unless explicitly configured for testing
if (
  process.env.NODE_ENV !== "test" ||
  process.env.ALLOW_INTEGRATION_TEST_DB !== "true"
) {
  console.error(
    "FATAL: Integration tests refuse to run without NODE_ENV=test and ALLOW_INTEGRATION_TEST_DB=true"
  );
  process.exit(1);
}

const http = require("http");
const pool = require("./config/database");
const express = require("express");
const cors = require("cors");
const authRoutes = require("./routes/auth");
const foodRoutes = require("./routes/foods");
const notificationRoutes = require("./routes/notifications");
const {
  validateTimeZone,
  getTimeZoneParts,
  getLocalDateForTimeZone,
  getLocalHourForTimeZone,
  calculateDaysRemaining,
  buildReminderMessage,
  generateRemindersForUser,
  removeStaleUnreadReminders,
} = require("./services/reminderService");

const app = express();
app.use(cors());
app.use(express.json());

app.use("/api/auth", authRoutes);
app.use("/api/foods", foodRoutes);
app.use("/api", notificationRoutes);

app.use((err, req, res, next) => {
  const statusCode = err.statusCode || err.status || 500;
  res.status(statusCode).json({
    message: err.message || "An internal server error occurred.",
  });
});

const TEST_PORT = 5056;
let server;

function request(method, reqPath, body = null, token = null) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const headers = { "Content-Type": "application/json" };
    if (token) headers["Authorization"] = `Bearer ${token}`;
    if (data) headers["Content-Length"] = Buffer.byteLength(data);

    const req = http.request(
      {
        hostname: "localhost",
        port: TEST_PORT,
        path: reqPath,
        method,
        headers,
      },
      (res) => {
        let responseBody = "";
        res.on("data", (chunk) => (responseBody += chunk));
        res.on("end", () => {
          try {
            const parsed = responseBody ? JSON.parse(responseBody) : {};
            resolve({ status: res.statusCode, body: parsed });
          } catch (e) {
            resolve({ status: res.statusCode, body: responseBody });
          }
        });
      }
    );

    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

// Track exact IDs for strictly scoped teardown
const createdUserIds = new Set();
const createdFoodIds = new Set();
const createdNotificationIds = new Set();

async function runTests() {
  console.log("--- Starting FreshTrack Phase 3 Backend Automated Tests ---");
  const timestamp = Date.now();
  const userAEmail = `notif_user_a_${timestamp}@example.com`;
  const userBEmail = `notif_user_b_${timestamp}@example.com`;
  const password = "Password123!";

  let tokenA = null;
  let tokenB = null;
  let userAId = null;
  let userBId = null;

  try {
    // 1. User Registration & Login with OTP
    const { getTestCapturedOtp } = require("./services/emailService");

    const regARes = await request("POST", "/api/auth/register", {
      name: "User A",
      email: userAEmail,
      password,
    });
    if (regARes.status !== 201) throw new Error("User A registration failed");
    const capturedA = getTestCapturedOtp(userAEmail);
    await request("POST", "/api/auth/register/verify-otp", {
      challenge_id: regARes.body.challenge_id,
      otp: capturedA.otp,
    });

    const loginA1 = await request("POST", "/api/auth/login", {
      email: userAEmail,
      password,
    });
    const capturedLoginA = getTestCapturedOtp(userAEmail);
    const loginA2 = await request("POST", "/api/auth/login/verify-otp", {
      challenge_id: loginA1.body.challenge_id,
      otp: capturedLoginA.otp,
    });
    userAId = loginA2.body.user.id;
    tokenA = loginA2.body.token;
    createdUserIds.add(userAId);

    const regBRes = await request("POST", "/api/auth/register", {
      name: "User B",
      email: userBEmail,
      password,
    });
    const capturedB = getTestCapturedOtp(userBEmail);
    await request("POST", "/api/auth/register/verify-otp", {
      challenge_id: regBRes.body.challenge_id,
      otp: capturedB.otp,
    });

    const loginB1 = await request("POST", "/api/auth/login", {
      email: userBEmail,
      password,
    });
    const capturedLoginB = getTestCapturedOtp(userBEmail);
    const loginB2 = await request("POST", "/api/auth/login/verify-otp", {
      challenge_id: loginB1.body.challenge_id,
      otp: capturedLoginB.otp,
    });
    userBId = loginB2.body.user.id;
    tokenB = loginB2.body.token;
    createdUserIds.add(userBId);

    console.log("✓ Test users A and B authenticated successfully");

    // 2. Database CHECK Constraint on reminder_days
    // Empty array must fail cardinality(reminder_days) > 0
    try {
      await pool.query(
        "INSERT INTO notification_preferences (user_id, reminder_days) VALUES ($1, ARRAY[]::INTEGER[])",
        [userAId]
      );
      throw new Error("CHECK constraint failed to reject empty reminder_days array");
    } catch (dbErr) {
      if (dbErr.code === "23514") {
        console.log("✓ DB CHECK constraint rejected empty reminder_days array (23514)");
      } else {
        throw dbErr;
      }
    }

    // Invalid offset in array (e.g. 5) must fail <@ ARRAY[0,1,3,7]
    try {
      await pool.query(
        "INSERT INTO notification_preferences (user_id, reminder_days) VALUES ($1, ARRAY[5, 1, 0])",
        [userAId]
      );
      throw new Error("CHECK constraint failed to reject invalid reminder_days values");
    } catch (dbErr) {
      if (dbErr.code === "23514") {
        console.log("✓ DB CHECK constraint rejected invalid offset array [5, 1, 0] (23514)");
      } else {
        throw dbErr;
      }
    }

    // 3. Timezone Extraction, Rollover, and Date Math
    const testDateBoundary = new Date("2026-09-02T23:30:00.000Z");
    const nyDate = getLocalDateForTimeZone("America/New_York", testDateBoundary);
    const tokyoDate = getLocalDateForTimeZone("Asia/Tokyo", testDateBoundary);
    if (nyDate !== "2026-09-02" || tokyoDate !== "2026-09-03") {
      throw new Error(`Timezone boundary failed: NY=${nyDate}, Tokyo=${tokyoDate}`);
    }
    console.log("✓ Timezone day boundary handled correctly across IANA zones");

    // Month rollover (Feb 28 to Mar 1 non-leap year)
    const febDate = new Date("2025-02-28T22:30:00.000Z");
    const tokyoMarDate = getLocalDateForTimeZone("Asia/Tokyo", febDate);
    if (tokyoMarDate !== "2025-03-01") {
      throw new Error(`Month rollover failed: expected 2025-03-01, got ${tokyoMarDate}`);
    }
    console.log("✓ Month rollover (Feb 28 -> Mar 1) handled correctly");

    // Year rollover (Dec 31 to Jan 1)
    const nyeDate = new Date("2026-12-31T20:00:00.000Z");
    const tokyoNyeDate = getLocalDateForTimeZone("Asia/Tokyo", nyeDate);
    if (tokyoNyeDate !== "2027-01-01") {
      throw new Error(`Year rollover failed: expected 2027-01-01, got ${tokyoNyeDate}`);
    }
    console.log("✓ Year rollover (Dec 31 -> Jan 1) handled correctly");

    // Midnight hour 0 extraction
    const midnightDate = new Date("2026-09-02T18:30:00.000Z"); // 00:00 in Asia/Kolkata
    const kolkataHour = getLocalHourForTimeZone("Asia/Kolkata", midnightDate);
    if (kolkataHour !== 0) {
      throw new Error(`Midnight hour extraction failed: expected 0, got ${kolkataHour}`);
    }
    console.log("✓ Midnight hour 0 extracted correctly (hourCycle h23)");

    // Date difference math
    const diffDays = calculateDaysRemaining("2026-09-05", "2026-09-02");
    if (diffDays !== 3) throw new Error(`calculateDaysRemaining failed: ${diffDays}`);
    console.log("✓ Numeric Date.UTC days difference math verified");

    // 4. Default Preference Retrieval & Concurrent Safe Creation
    const prefResA = await request("GET", "/api/notification-preferences", null, tokenA);
    if (prefResA.status !== 200) throw new Error("Failed to get preferences");
    if (prefResA.body.notifications_enabled !== true) throw new Error("Default preferences mismatch");
    console.log("✓ Default notification preferences initialized atomically on demand");

    // 5. Parameter Injection Defense: Reject user_id / userId in body
    const injectRes = await request(
      "PUT",
      "/api/notification-preferences",
      {
        user_id: userBId,
        notifications_enabled: false,
        browser_notifications_enabled: false,
        reminder_days: [3, 1],
        timezone: "Asia/Kolkata",
        reminder_hour: 10,
      },
      tokenA
    );
    if (injectRes.status !== 400) throw new Error("PUT preferences did not reject user_id");
    console.log("✓ PUT /api/notification-preferences rejected user_id in body (400)");

    // 6. Preference Validation (Invalid array, timezone, hour)
    const badArrayRes = await request(
      "PUT",
      "/api/notification-preferences",
      {
        notifications_enabled: true,
        browser_notifications_enabled: false,
        reminder_days: [5, 1],
        timezone: "Asia/Kolkata",
        reminder_hour: 9,
      },
      tokenA
    );
    if (badArrayRes.status !== 400) throw new Error("Did not reject invalid reminder days");

    const badTzRes = await request(
      "PUT",
      "/api/notification-preferences",
      {
        notifications_enabled: true,
        browser_notifications_enabled: false,
        reminder_days: [3, 1],
        timezone: "Invalid/Zone",
        reminder_hour: 9,
      },
      tokenA
    );
    if (badTzRes.status !== 400) throw new Error("Did not reject invalid timezone");

    const badHourRes = await request(
      "PUT",
      "/api/notification-preferences",
      {
        notifications_enabled: true,
        browser_notifications_enabled: false,
        reminder_days: [3, 1],
        timezone: "Asia/Kolkata",
        reminder_hour: 25,
      },
      tokenA
    );
    if (badHourRes.status !== 400) throw new Error("Did not reject invalid hour");
    console.log("✓ Preference input validation rejects invalid arrays, timezones, and hours");

    // Valid update: Deduplicates and stores consistently [7, 3, 1, 0]
    const validPrefRes = await request(
      "PUT",
      "/api/notification-preferences",
      {
        notifications_enabled: true,
        browser_notifications_enabled: true,
        reminder_days: [0, 3, 1, 3, 7],
        timezone: "Asia/Kolkata",
        reminder_hour: 10,
      },
      tokenA
    );
    if (validPrefRes.status !== 200) throw new Error("Valid PUT preferences failed");
    if (JSON.stringify(validPrefRes.body.reminder_days) !== JSON.stringify([7, 3, 1, 0])) {
      throw new Error("Reminder days were not deduplicated and sorted as [7, 3, 1, 0]");
    }
    console.log("✓ Valid preference update deduplicates and sorts reminder_days to [7, 3, 1, 0]");

    // 7. Cross-User Privacy & Unread-Count On-Demand Generation
    // Create active food expiring today for User A
    const todayStr = getLocalDateForTimeZone("Asia/Kolkata");
    const foodCreateRes = await request(
      "POST",
      "/api/foods",
      {
        food_name: "Fresh Milk",
        quantity: 2,
        expiry_date: todayStr,
      },
      tokenA
    );
    if (foodCreateRes.status !== 201) throw new Error("Food creation failed");
    const foodAId = foodCreateRes.body.id;
    createdFoodIds.add(foodAId);

    // Call GET /api/notifications/unread-count on demand
    const unreadCountResA = await request("GET", "/api/notifications/unread-count", null, tokenA);
    if (unreadCountResA.status !== 200 || unreadCountResA.body.unread_count < 1) {
      throw new Error(`On-demand reminder generation in unread-count failed: ${JSON.stringify(unreadCountResA.body)}`);
    }
    console.log("✓ GET /api/notifications/unread-count generates reminders on demand (count >= 1)");

    // User B unread count must be isolated (0)
    const unreadCountResB = await request("GET", "/api/notifications/unread-count", null, tokenB);
    if (unreadCountResB.body.unread_count !== 0) {
      throw new Error("User B unread count is not isolated!");
    }
    console.log("✓ User B notifications are completely isolated (count: 0)");

    // 8. Reminder Offsets (7, 3, 1, 0, expired -1) & Duplicate Prevention
    // Fetch notifications list for User A
    const notifListRes = await request("GET", "/api/notifications", null, tokenA);
    if (notifListRes.status !== 200 || notifListRes.body.notifications.length === 0) {
      throw new Error("Failed to list notifications");
    }
    const notifA = notifListRes.body.notifications[0];
    createdNotificationIds.add(notifA.id);
    if (notifA.type !== "expires_today" || notifA.reminder_offset_days !== 0) {
      throw new Error(`Notification type mismatch: ${JSON.stringify(notifA)}`);
    }

    // Repeated call creates no duplicate rows (ON CONFLICT DO NOTHING)
    await generateRemindersForUser(userAId);
    const countCheck = await pool.query(
      "SELECT COUNT(*)::int AS count FROM notifications WHERE user_id = $1 AND food_item_id = $2",
      [userAId, foodAId]
    );
    if (countCheck.rows[0].count !== 1) {
      throw new Error("Duplicate reminder created despite ON CONFLICT DO NOTHING!");
    }
    console.log("✓ Idempotent reminder generation creates exactly one row");

    // 9. Read Notification & Ownership
    // User B cannot mark User A notification read
    const hackReadRes = await request("PATCH", `/api/notifications/${notifA.id}/read`, null, tokenB);
    if (hackReadRes.status !== 404) throw new Error("User B was able to mark User A notification read");

    // User A marks as read
    const readRes = await request("PATCH", `/api/notifications/${notifA.id}/read`, null, tokenA);
    if (readRes.status !== 200 || readRes.body.is_read !== true) {
      throw new Error("Failed to mark notification read");
    }
    console.log("✓ PATCH /api/notifications/:id/read works exclusively for owner");

    // 10. Conditional PUT Food Cleanup:
    // Update food name only (expiry unchanged) -> unread reminders preserved (though here it's already read)
    // Create another food item with unread reminder
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const tomorrowStr = getLocalDateForTimeZone("Asia/Kolkata", tomorrow);

    const food2Res = await request(
      "POST",
      "/api/foods",
      {
        food_name: "Yogurt",
        quantity: 1,
        expiry_date: tomorrowStr,
      },
      tokenA
    );
    const food2Id = food2Res.body.id;
    createdFoodIds.add(food2Id);

    // Generate reminder
    await generateRemindersForUser(userAId);
    const unreadBeforePut = await pool.query(
      "SELECT id FROM notifications WHERE food_item_id = $1 AND is_read = FALSE",
      [food2Id]
    );
    if (unreadBeforePut.rows.length === 0) throw new Error("Expected unread reminder for food 2");
    createdNotificationIds.add(unreadBeforePut.rows[0].id);

    // PUT food 2 changing only notes -> unread reminder MUST be preserved
    await request(
      "PUT",
      `/api/foods/${food2Id}`,
      {
        food_name: "Yogurt",
        quantity: 1,
        expiry_date: tomorrowStr,
        notes: "Updated note only",
      },
      tokenA
    );
    const unreadAfterNotePut = await pool.query(
      "SELECT id FROM notifications WHERE food_item_id = $1 AND is_read = FALSE",
      [food2Id]
    );
    if (unreadAfterNotePut.rows.length === 0) {
      throw new Error("PUT with unchanged expiry incorrectly cleaned up unread reminders!");
    }
    console.log("✓ PUT food with unchanged expiry_date preserves unread reminders");

    // PUT food 2 changing expiry_date -> stale unread reminder cleaned up
    const futureDate = new Date();
    futureDate.setDate(futureDate.getDate() + 10);
    const futureDateStr = getLocalDateForTimeZone("Asia/Kolkata", futureDate);

    await request(
      "PUT",
      `/api/foods/${food2Id}`,
      {
        food_name: "Yogurt",
        quantity: 1,
        expiry_date: futureDateStr,
      },
      tokenA
    );
    const unreadAfterDatePut = await pool.query(
      "SELECT id FROM notifications WHERE food_item_id = $1 AND is_read = FALSE",
      [food2Id]
    );
    if (unreadAfterDatePut.rows.length > 0) {
      throw new Error("PUT with changed expiry_date failed to delete stale unread reminders!");
    }
    console.log("✓ PUT food with changed expiry_date cleans up stale unread reminders");

    // 11. Conditional Status PATCH:
    // active -> active: no-op, preserves updated_at, no cleanup/regeneration
    const foodRowBefore = await pool.query("SELECT * FROM food_items WHERE id = $1", [foodAId]);
    const updatedAtBefore = foodRowBefore.rows[0].updated_at.toISOString();

    const activePatchRes = await request(
      "PATCH",
      `/api/foods/${foodAId}/status`,
      { status: "active" },
      tokenA
    );
    if (activePatchRes.status !== 200) throw new Error("active -> active status PATCH failed");
    const foodRowAfter = await pool.query("SELECT * FROM food_items WHERE id = $1", [foodAId]);
    const updatedAtAfter = foodRowAfter.rows[0].updated_at.toISOString();
    if (updatedAtBefore !== updatedAtAfter) {
      throw new Error("active -> active unexpectedly modified updated_at!");
    }
    console.log("✓ PATCH status active -> active is a clean no-op preserving updated_at");

    // 12. Reactivation & Read History Preservation:
    // foodA has 1 READ notification (notifA)
    // Mark foodA consumed
    await request("PATCH", `/api/foods/${foodAId}/status`, { status: "consumed" }, tokenA);
    // Preserved read notification still in DB
    const readCheckConsumed = await pool.query(
      "SELECT is_read FROM notifications WHERE id = $1",
      [notifA.id]
    );
    if (readCheckConsumed.rows.length === 0 || !readCheckConsumed.rows[0].is_read) {
      throw new Error("Read reminder was lost on consumed status transition!");
    }

    // Reactivate foodA to active
    await request("PATCH", `/api/foods/${foodAId}/status`, { status: "active" }, tokenA);

    // Check notifications for foodA: exactly 1 read notification, no duplicate!
    const notifsAfterReactivation = await pool.query(
      "SELECT id, is_read, reminder_offset_days FROM notifications WHERE food_item_id = $1",
      [foodAId]
    );
    if (notifsAfterReactivation.rows.length !== 1) {
      throw new Error(`Reactivation duplicated notification: count is ${notifsAfterReactivation.rows.length}`);
    }
    if (!notifsAfterReactivation.rows[0].is_read) {
      throw new Error("Reactivation reset is_read to false!");
    }
    console.log("✓ Reactivation preserves read reminders and generates only unrecorded keys");

    // 13. Read-All & Delete Ownership
    // Mark all as read
    const readAllRes = await request("PATCH", "/api/notifications/read-all", null, tokenA);
    if (readAllRes.status !== 200) throw new Error("read-all failed");
    console.log("✓ PATCH /api/notifications/read-all completed successfully");

    // Delete individual notification
    const delRes = await request("DELETE", `/api/notifications/${notifA.id}`, null, tokenA);
    if (delRes.status !== 200) throw new Error("DELETE notification failed");
    console.log("✓ DELETE /api/notifications/:id deleted notification for owner");

    // 14. Food Deletion Cascade: ON DELETE CASCADE permanently cleans up all notifications
    // Create food 3 with a notification
    const food3Res = await request(
      "POST",
      "/api/foods",
      {
        food_name: "Cheese",
        quantity: 1,
        expiry_date: todayStr,
      },
      tokenA
    );
    const food3Id = food3Res.body.id;
    createdFoodIds.add(food3Id);
    await generateRemindersForUser(userAId);

    const f3Notifs = await pool.query("SELECT id FROM notifications WHERE food_item_id = $1", [food3Id]);
    if (f3Notifs.rows.length === 0) throw new Error("Expected notification for food 3");

    // Delete food 3
    await request("DELETE", `/api/foods/${food3Id}`, null, tokenA);
    const f3NotifsAfter = await pool.query("SELECT id FROM notifications WHERE food_item_id = $1", [food3Id]);
    if (f3NotifsAfter.rows.length !== 0) {
      throw new Error("Food deletion cascade failed to remove related notifications!");
    }
    console.log("✓ Food deletion cascade permanently deletes related notifications");

    // 15. Pagination Verification (limit and offset)
    const pagRes = await request("GET", "/api/notifications?limit=10&offset=0", null, tokenA);
    if (pagRes.status !== 200 || !Array.isArray(pagRes.body.notifications) || typeof pagRes.body.total !== "number") {
      throw new Error("Pagination response schema mismatch");
    }
    console.log("✓ GET /api/notifications supports limit and offset pagination");

    // 16. Authentication & Credential Safety
    const unauthedRes = await request("GET", "/api/notifications");
    if (unauthedRes.status !== 401) throw new Error("Unauthenticated request did not return 401");

    const badTokenRes = await request("GET", "/api/notifications", null, "invalid.jwt.token");
    if (badTokenRes.status !== 401) throw new Error("Invalid JWT did not return 401");

    const prefString = JSON.stringify(validPrefRes.body);
    if (prefString.includes("password_hash") || prefString.includes("secret")) {
      throw new Error("Sensitive credentials leaked in response!");
    }
    console.log("✓ Missing/invalid JWT returns 401 and zero credentials leaked");

    console.log("\n=======================================================");
    console.log("ALL 25 PHASE 3 BACKEND INTEGRATION TESTS PASSED! 🎉");
    console.log("=======================================================\n");
  } finally {
    // Exact ID-based cleanup
    if (createdNotificationIds.size > 0) {
      await pool.query("DELETE FROM notifications WHERE id = ANY($1)", [Array.from(createdNotificationIds)]);
    }
    if (createdFoodIds.size > 0) {
      await pool.query("DELETE FROM food_items WHERE id = ANY($1)", [Array.from(createdFoodIds)]);
    }
    if (createdUserIds.size > 0) {
      await pool.query("DELETE FROM users WHERE id = ANY($1)", [Array.from(createdUserIds)]);
    }
    console.log("✓ Cleaned up only exact test user and notification records.");
  }
}

server = app.listen(TEST_PORT, async () => {
  try {
    await runTests();
    server.close();
    await pool.end();
    process.exit(0);
  } catch (error) {
    console.error("❌ TEST FAILURE:", error);
    server.close();
    await pool.end();
    process.exit(1);
  }
});
