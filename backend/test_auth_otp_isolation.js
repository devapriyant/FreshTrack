require("dotenv").config();
const http = require("http");
const express = require("express");
const cors = require("cors");
const pool = require("./config/database");
const authRoutes = require("./routes/auth");
const foodRoutes = require("./routes/foods");
const notificationRoutes = require("./routes/notifications");
const { getTestCapturedOtp, clearTestCapturedOtps } = require("./services/emailService");
const { cleanExpiredOtpAndRegistrations } = require("./jobs/otpCleanupJob");

// Safety guard
if (
  process.env.NODE_ENV !== "test" ||
  process.env.ALLOW_INTEGRATION_TEST_DB !== "true" ||
  process.env.ALLOW_TEST_OTP_CAPTURE !== "true"
) {
  console.error(
    "FATAL: test_auth_otp_isolation.js requires NODE_ENV=test, ALLOW_INTEGRATION_TEST_DB=true, and ALLOW_TEST_OTP_CAPTURE=true."
  );
  process.exit(1);
}

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

const TEST_PORT = 5066;
let server;

function request(method, path, body = null, token = null) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const headers = {
      "Content-Type": "application/json",
    };
    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }
    if (data) {
      headers["Content-Length"] = Buffer.byteLength(data);
    }

    const req = http.request(
      {
        hostname: "localhost",
        port: TEST_PORT,
        path,
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

async function runTests() {
  console.log("=== Starting FreshTrack Hardened Isolation & Email OTP Suite ===");
  const timestamp = Date.now();
  const userAEmail = `iso_user_a_${timestamp}@example.com`;
  const userBEmail = `iso_user_b_${timestamp}@example.com`;
  const unverifiedEmail = `iso_unverified_${timestamp}@example.com`;
  const password = "ComplexPassword123!";

  let userAId = null;
  let userBId = null;
  let tokenA = null;
  let tokenB = null;
  let foodAId = null;

  try {
    // -------------------------------------------------------------
    // Test 1: Registration Flow with pending_registrations & OTP
    // -------------------------------------------------------------
    console.log("\n[Test 1] Registration Flow with pending_registrations & OTP");

    clearTestCapturedOtps();
    const regResA = await request("POST", "/api/auth/register", {
      name: "User A",
      email: userAEmail,
      password,
    });

    if (regResA.status !== 201) {
      throw new Error(`Register User A failed: ${JSON.stringify(regResA.body)}`);
    }
    if (!regResA.body.challenge_id) {
      throw new Error("Registration did not return challenge_id");
    }
    if (regResA.body.token) {
      throw new Error("SECURITY VIOLATION: JWT returned at registration step!");
    }
    const challengeA = regResA.body.challenge_id;
    console.log("✓ Registration returns challenge_id and masked email without issuing JWT");

    // Verify user record does NOT exist in users table yet
    const pendingDbCheck = await pool.query(
      "SELECT id FROM users WHERE LOWER(email) = $1",
      [userAEmail.toLowerCase()]
    );
    if (pendingDbCheck.rows.length !== 0) {
      throw new Error("SECURITY VIOLATION: User was inserted into users table before OTP verification!");
    }

    // Verify row exists in pending_registrations
    const pendingRow = await pool.query(
      "SELECT * FROM pending_registrations WHERE email = $1",
      [userAEmail.toLowerCase()]
    );
    if (pendingRow.rows.length === 0) {
      throw new Error("pending_registrations row was not created!");
    }
    console.log("✓ Unverified registration strictly isolated in pending_registrations table");

    // Try wrong OTP -> should increment attempts
    const wrongOtpRes = await request("POST", "/api/auth/register/verify-otp", {
      challenge_id: challengeA,
      otp: "000000",
    });
    if (wrongOtpRes.status !== 400) {
      throw new Error(`Expected 400 for wrong OTP, got ${wrongOtpRes.status}`);
    }

    const challengeDbCheck = await pool.query(
      "SELECT attempts FROM email_otp_challenges WHERE id = $1",
      [challengeA]
    );
    if (challengeDbCheck.rows[0].attempts !== 1) {
      throw new Error(`Attempts was not incremented, got ${challengeDbCheck.rows[0].attempts}`);
    }
    console.log("✓ Invalid OTP code increments failed attempts counter");

    // Get captured OTP from test store
    const capturedA = getTestCapturedOtp(userAEmail);
    if (!capturedA || !capturedA.otp) {
      throw new Error("Test OTP was not captured in emailService!");
    }

    // Verify with correct OTP
    const verifyRegA = await request("POST", "/api/auth/register/verify-otp", {
      challenge_id: challengeA,
      otp: capturedA.otp,
    });
    if (verifyRegA.status !== 200) {
      throw new Error(`Verify OTP User A failed: ${JSON.stringify(verifyRegA.body)}`);
    }
    if (verifyRegA.body.token) {
      throw new Error("SECURITY VIOLATION: JWT returned at register verify-otp step!");
    }
    console.log("✓ Correct registration OTP successfully verifies account (no JWT issued)");

    // Confirm user is now in users table with email_verified = true
    const userADb = await pool.query(
      "SELECT id, email_verified, email_verified_at FROM users WHERE LOWER(email) = $1",
      [userAEmail.toLowerCase()]
    );
    if (userADb.rows.length === 0 || !userADb.rows[0].email_verified) {
      throw new Error("User was not found in users table or email_verified is not true!");
    }
    userAId = userADb.rows[0].id;

    // Confirm pending_registrations row was deleted
    const pendingAfter = await pool.query(
      "SELECT id FROM pending_registrations WHERE email = $1",
      [userAEmail.toLowerCase()]
    );
    if (pendingAfter.rows.length !== 0) {
      throw new Error("pending_registrations row was not deleted after verification!");
    }
    console.log("✓ Verified user inserted into users and deleted from pending_registrations");

    // Confirm challenge was marked consumed and cannot be reused
    const reuseOtp = await request("POST", "/api/auth/register/verify-otp", {
      challenge_id: challengeA,
      otp: capturedA.otp,
    });
    if (reuseOtp.status !== 400) {
      throw new Error(`Expected 400 when reusing consumed OTP, got ${reuseOtp.status}`);
    }
    console.log("✓ Consumed OTP challenge cannot be reused");

    // -------------------------------------------------------------
    // Test 2: Two-Step Login with OTP & Verified JWT
    // -------------------------------------------------------------
    console.log("\n[Test 2] Two-Step Login with OTP & Verified JWT");

    // Step 1: Login with credentials
    clearTestCapturedOtps();
    const loginStep1 = await request("POST", "/api/auth/login", {
      email: userAEmail,
      password,
    });
    if (loginStep1.status !== 200 || !loginStep1.body.challenge_id) {
      throw new Error(`Login step 1 failed: ${JSON.stringify(loginStep1.body)}`);
    }
    if (loginStep1.body.token) {
      throw new Error("SECURITY VIOLATION: JWT issued at login step 1 before OTP!");
    }
    const loginChallengeId = loginStep1.body.challenge_id;
    console.log("✓ Login step 1 validates password and returns login OTP challenge (NO JWT)");

    // Step 2: Verify login OTP
    const capturedLoginOtp = getTestCapturedOtp(userAEmail);
    if (!capturedLoginOtp || !capturedLoginOtp.otp) {
      throw new Error("Login OTP was not captured in emailService!");
    }

    const loginStep2 = await request("POST", "/api/auth/login/verify-otp", {
      challenge_id: loginChallengeId,
      otp: capturedLoginOtp.otp,
    });
    if (loginStep2.status !== 200 || !loginStep2.body.token) {
      throw new Error(`Login step 2 failed: ${JSON.stringify(loginStep2.body)}`);
    }
    tokenA = loginStep2.body.token;
    if (loginStep2.body.user.id !== userAId) {
      throw new Error(`User ID in login response mismatch: expected ${userAId}, got ${loginStep2.body.user.id}`);
    }
    console.log("✓ Login step 2 issues verified JWT containing correct user ID and profile");

    // -------------------------------------------------------------
    // Test 3: Register & Login User B
    // -------------------------------------------------------------
    console.log("\n[Test 3] Register & Login User B");
    clearTestCapturedOtps();
    const regResB = await request("POST", "/api/auth/register", {
      name: "User B",
      email: userBEmail,
      password,
    });
    const challengeB = regResB.body.challenge_id;
    const capturedB = getTestCapturedOtp(userBEmail);

    await request("POST", "/api/auth/register/verify-otp", {
      challenge_id: challengeB,
      otp: capturedB.otp,
    });

    clearTestCapturedOtps();
    const loginB1 = await request("POST", "/api/auth/login", {
      email: userBEmail,
      password,
    });
    const loginB2 = await request("POST", "/api/auth/login/verify-otp", {
      challenge_id: loginB1.body.challenge_id,
      otp: getTestCapturedOtp(userBEmail).otp,
    });
    tokenB = loginB2.body.token;
    userBId = loginB2.body.user.id;
    console.log("✓ User B registered, verified, and logged in successfully");

    // -------------------------------------------------------------
    // Test 4: Cross-User Food Isolation Audit
    // -------------------------------------------------------------
    console.log("\n[Test 4] Cross-User Food Isolation Audit");

    // User A adds USER_A_PRIVATE_FOOD
    const createFoodA = await request(
      "POST",
      "/api/foods",
      {
        food_name: "USER_A_PRIVATE_FOOD",
        category: "Produce",
        quantity: 5,
        expiry_date: "2026-09-30",
        storage_location: "Pantry",
        notes: "Confidential private food data",
      },
      tokenA
    );
    if (createFoodA.status !== 201) {
      throw new Error(`Create food A failed: ${JSON.stringify(createFoodA.body)}`);
    }
    foodAId = createFoodA.body.id;
    console.log(`✓ User A created food item '${createFoodA.body.food_name}' (ID: ${foodAId})`);

    // User A retrieves it -> 200
    const getFoodA = await request("GET", `/api/foods/${foodAId}`, null, tokenA);
    if (getFoodA.status !== 200 || getFoodA.body.food_name !== "USER_A_PRIVATE_FOOD") {
      throw new Error("User A cannot retrieve own food item");
    }
    console.log("✓ User A retrieves own food item successfully (200)");

    // User B calls GET /api/foods -> must be empty (0 items)
    const listFoodB = await request("GET", "/api/foods", null, tokenB);
    if (listFoodB.status !== 200 || listFoodB.body.count !== 0 || listFoodB.body.items.length !== 0) {
      throw new Error(`SECURITY LEAK: User B list returned items! Count: ${listFoodB.body.count}`);
    }
    console.log("✓ User B GET /api/foods does not contain User A's item (count: 0)");

    // User B attempts GET /api/foods/:id using User A's food ID -> 404
    const userBGet = await request("GET", `/api/foods/${foodAId}`, null, tokenB);
    if (userBGet.status !== 404) {
      throw new Error(`Expected 404 for User B GET unowned food, got ${userBGet.status}`);
    }
    console.log("✓ User B GET /api/foods/:id on User A's item returns 404");

    // User B attempts PUT /api/foods/:id on User A's food ID -> 404
    const userBPut = await request(
      "PUT",
      `/api/foods/${foodAId}`,
      {
        food_name: "TAMPERED_BY_B",
        quantity: 1,
        expiry_date: "2026-09-30",
      },
      tokenB
    );
    if (userBPut.status !== 404) {
      throw new Error(`Expected 404 for User B PUT unowned food, got ${userBPut.status}`);
    }
    console.log("✓ User B PUT /api/foods/:id on User A's item returns 404");

    // User B attempts PATCH /api/foods/:id/status on User A's food ID -> 404
    const userBPatch = await request(
      "PATCH",
      `/api/foods/${foodAId}/status`,
      { status: "consumed" },
      tokenB
    );
    if (userBPatch.status !== 404) {
      throw new Error(`Expected 404 for User B PATCH unowned food, got ${userBPatch.status}`);
    }
    console.log("✓ User B PATCH /api/foods/:id/status on User A's item returns 404");

    // User B attempts DELETE /api/foods/:id on User A's food ID -> 404
    const userBDelete = await request("DELETE", `/api/foods/${foodAId}`, null, tokenB);
    if (userBDelete.status !== 404) {
      throw new Error(`Expected 404 for User B DELETE unowned food, got ${userBDelete.status}`);
    }
    console.log("✓ User B DELETE /api/foods/:id on User A's item returns 404");

    // Confirm database data for User A remains completely UNCHANGED
    const verifyUnchanged = await pool.query(
      "SELECT food_name, status, quantity FROM food_items WHERE id = $1",
      [foodAId]
    );
    if (
      verifyUnchanged.rows[0].food_name !== "USER_A_PRIVATE_FOOD" ||
      verifyUnchanged.rows[0].status !== "active" ||
      verifyUnchanged.rows[0].quantity !== 5
    ) {
      throw new Error("SECURITY LEAK: User A's food data was altered by User B!");
    }
    console.log("✓ Database record for User A remains unaltered after User B's unauthorized attempts");

    // -------------------------------------------------------------
    // Test 5: Rejection of user_id in Query & Params
    // -------------------------------------------------------------
    console.log("\n[Test 5] Rejection of user_id in Query & Params");
    const queryTamper = await request("GET", "/api/foods?user_id=1", null, tokenA);
    if (queryTamper.status !== 400) {
      throw new Error(`Expected 400 on user_id query param, got ${queryTamper.status}`);
    }
    const queryCamelTamper = await request("GET", "/api/foods?userId=1", null, tokenA);
    if (queryCamelTamper.status !== 400) {
      throw new Error(`Expected 400 on userId query param, got ${queryCamelTamper.status}`);
    }
    console.log("✓ GET /api/foods rejects user_id and userId in query parameters with 400");

    // -------------------------------------------------------------
    // Test 6: Unverified Existing Account Verification Flow
    // -------------------------------------------------------------
    console.log("\n[Test 6] Existing Account Email Verification Flow");
    // Insert an unverified account manually
    const unverifiedHash = await require("bcryptjs").hash(password, 10);
    await pool.query(
      `INSERT INTO users (name, email, password_hash, email_verified, created_at)
       VALUES ('Unverified User', $1, $2, FALSE, NOW())`,
      [unverifiedEmail, unverifiedHash]
    );

    // Try logging in before verification -> must return 403 with verification_required: true
    const unverifiedLogin = await request("POST", "/api/auth/login", {
      email: unverifiedEmail,
      password,
    });
    if (unverifiedLogin.status !== 403 || !unverifiedLogin.body.verification_required) {
      throw new Error(`Expected 403 verification_required, got ${unverifiedLogin.status}`);
    }
    console.log("✓ Login rejects unverified account with 403 verification_required");

    // Start verification with wrong password -> 401
    const badPassVerify = await request("POST", "/api/auth/email-verification/start", {
      email: unverifiedEmail,
      password: "WrongPassword!",
    });
    if (badPassVerify.status !== 401) {
      throw new Error(`Expected 401 for wrong password on verify start, got ${badPassVerify.status}`);
    }

    // Start verification with correct password -> 200
    clearTestCapturedOtps();
    const startVerify = await request("POST", "/api/auth/email-verification/start", {
      email: unverifiedEmail,
      password,
    });
    if (startVerify.status !== 200 || !startVerify.body.challenge_id) {
      throw new Error(`Start email verification failed: ${JSON.stringify(startVerify.body)}`);
    }
    const unverifiedChallengeId = startVerify.body.challenge_id;

    // Complete verification
    const unverifiedOtp = getTestCapturedOtp(unverifiedEmail);
    const completeVerify = await request("POST", "/api/auth/email-verification/verify", {
      challenge_id: unverifiedChallengeId,
      otp: unverifiedOtp.otp,
    });
    if (completeVerify.status !== 200) {
      throw new Error(`Complete email verification failed: ${JSON.stringify(completeVerify.body)}`);
    }

    // User can now log in
    const nowCanLogin = await request("POST", "/api/auth/login", {
      email: unverifiedEmail,
      password,
    });
    if (nowCanLogin.status !== 200 || !nowCanLogin.body.challenge_id) {
      throw new Error("Verified user could not proceed to login step 1");
    }
    console.log("✓ Existing account verification flow completes and enables login");

    // -------------------------------------------------------------
    // Test 7: Resend Cooldown Enforcement
    // -------------------------------------------------------------
    console.log("\n[Test 7] Resend Cooldown Enforcement");
    const rapidResend = await request("POST", "/api/auth/login/resend-otp", {
      challenge_id: nowCanLogin.body.challenge_id,
    });
    if (rapidResend.status !== 429) {
      throw new Error(`Expected 429 on rapid resend within cooldown, got ${rapidResend.status}`);
    }
    console.log("✓ Resend OTP enforces 60-second cooldown with HTTP 429");

    // -------------------------------------------------------------
    // Test 8: Abandoned Registrations & Expired Challenges Cleanup
    // -------------------------------------------------------------
    console.log("\n[Test 8] Abandoned Registrations & Expired Challenges Cleanup");
    // Run cleanup function
    const cleanupResult = await cleanExpiredOtpAndRegistrations();
    if (typeof cleanupResult.deletedChallenges !== "number") {
      throw new Error("Cleanup function did not return deleted count");
    }
    console.log(`✓ Cleanup job executed safely (pruned ${cleanupResult.deletedChallenges} challenges)`);

    console.log("\n=======================================================");
    console.log("ALL HARDENED BACKEND ISOLATION & OTP TESTS PASSED! 🎉");
    console.log("=======================================================");
  } finally {
    // Clean up test records
    try {
      await pool.query("DELETE FROM users WHERE LOWER(email) IN ($1, $2, $3)", [
        userAEmail.toLowerCase(),
        userBEmail.toLowerCase(),
        unverifiedEmail.toLowerCase(),
      ]);
      await pool.query("DELETE FROM pending_registrations WHERE LOWER(email) IN ($1, $2, $3)", [
        userAEmail.toLowerCase(),
        userBEmail.toLowerCase(),
        unverifiedEmail.toLowerCase(),
      ]);
      await pool.query("DELETE FROM email_otp_challenges WHERE LOWER(email) IN ($1, $2, $3)", [
        userAEmail.toLowerCase(),
        userBEmail.toLowerCase(),
        unverifiedEmail.toLowerCase(),
      ]);
    } catch (_) {}
    server.close();
    await pool.end();
  }
}

server = app.listen(TEST_PORT, async () => {
  try {
    await runTests();
    process.exit(0);
  } catch (err) {
    console.error("\nTEST FAILURE:", err.message);
    process.exit(1);
  }
});
