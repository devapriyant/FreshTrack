require("dotenv").config();
const assert = require("assert");
const http = require("http");
const app = require("./app");
const pool = require("./config/database");
const { getTestCapturedOtp, clearTestCapturedOtps } = require("./services/emailService");
const emailService = require("./services/emailService");

let server;
let testPort;

function apiRequest(method, path, body = null, token = null) {
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
        port: testPort,
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
            resolve({ statusCode: res.statusCode, body: parsed });
          } catch (e) {
            resolve({ statusCode: res.statusCode, body: responseBody });
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
  console.log("=== Running Registration OTP Resend Hardening Tests ===");

  // Ensure test environment is configured
  assert.strictEqual(process.env.NODE_ENV, "test");
  assert.strictEqual(process.env.ALLOW_INTEGRATION_TEST_DB, "true");
  assert.strictEqual(process.env.ALLOW_TEST_OTP_CAPTURE, "true");

  server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, resolve));
  testPort = server.address().port;

  clearTestCapturedOtps();

  // Clean up any test users from previous runs
  const testEmail = `resend_test_${Date.now()}@example.com`;
  await pool.query("DELETE FROM pending_registrations WHERE email = $1", [testEmail]);
  await pool.query("DELETE FROM email_otp_challenges WHERE email = $1", [testEmail]);
  await pool.query("DELETE FROM users WHERE email = $1", [testEmail]);

  try {
    // 1. Initial registration request
    const registerRes = await apiRequest("POST", "/api/auth/register", {
      name: "Resend Test User",
      email: testEmail,
      password: "SecurePassword123!",
    });

    assert.strictEqual(registerRes.statusCode, 201);
    const challengeId1 = registerRes.body.challenge_id || registerRes.body.challengeId;
    const maskedEmail1 = registerRes.body.email || registerRes.body.maskedEmail;
    assert(challengeId1, "Registration must return challenge_id");
    assert(maskedEmail1, "Registration must return masked email");
    assert.notStrictEqual(maskedEmail1, testEmail, "API must NOT leak full unmasked email in response");

    // Verify captured OTP went to real email
    const initialCaptured = getTestCapturedOtp(testEmail);
    assert(initialCaptured, "sendOtpEmail must have been called with the real email");
    assert.strictEqual(
      getTestCapturedOtp(maskedEmail1),
      null,
      "sendOtpEmail must NEVER be called with the masked email"
    );
    console.log("✓ Test 1 Passed: Initial registration passes real email to email service and returns masked email in JSON");

    // Clear cooldown by shifting last_sent_at in DB
    await pool.query(
      "UPDATE email_otp_challenges SET last_sent_at = NOW() - INTERVAL '65 seconds' WHERE id = $1",
      [challengeId1]
    );

    // 2. Resend Registration OTP
    clearTestCapturedOtps();
    const resendRes = await apiRequest("POST", "/api/auth/register/resend-otp", {
      challenge_id: challengeId1,
    });

    assert.strictEqual(resendRes.statusCode, 200, `Resend failed: ${JSON.stringify(resendRes.body)}`);
    const challengeId2 = resendRes.body.challenge_id || resendRes.body.challengeId;
    const maskedEmail2 = resendRes.body.email || resendRes.body.maskedEmail;
    assert(challengeId2, "Resend must return new challenge_id");
    assert.notStrictEqual(challengeId2, challengeId1, "Resend should issue a new challenge ID");
    assert.strictEqual(maskedEmail2, maskedEmail1, "Masked email should remain consistent");
    assert.notStrictEqual(maskedEmail2, testEmail, "Resend API must never return full unmasked email");

    // CRITICAL CHECK: Real email was passed to emailService, NOT masked email
    const resendCaptured = getTestCapturedOtp(testEmail);
    assert(resendCaptured, "Resend must pass real email from PostgreSQL to email service");
    assert.strictEqual(
      getTestCapturedOtp(maskedEmail1),
      null,
      "Resend must NEVER pass masked email to email service"
    );
    assert(resendCaptured.otp, "A fresh OTP must have been generated");
    console.log("✓ Test 2 Passed: Resend sends fresh OTP to real address from PostgreSQL (never masked address)");

    // Verify in database: old challenge is consumed, new challenge is active
    const { rows: oldChallengeRows } = await pool.query(
      "SELECT * FROM email_otp_challenges WHERE id = $1",
      [challengeId1]
    );
    assert(oldChallengeRows[0].consumed_at !== null, "Old challenge must be marked consumed");

    const { rows: newChallengeRows } = await pool.query(
      "SELECT * FROM email_otp_challenges WHERE id = $1",
      [challengeId2]
    );
    assert.strictEqual(newChallengeRows.length, 1);
    assert.strictEqual(newChallengeRows[0].consumed_at, null, "New challenge must be active");
    console.log("✓ Test 3 Passed: Old challenge is consumed and new challenge is active in database");

    // 3. Test SMTP Failure Recovery (Old challenge remains valid if delivery fails)
    await pool.query(
      "UPDATE email_otp_challenges SET last_sent_at = NOW() - INTERVAL '65 seconds' WHERE id = $1",
      [challengeId2]
    );

    const originalSendOtp = emailService.sendOtpEmail;
    let simulatedFailureTriggered = false;
    emailService.sendOtpEmail = async () => {
      simulatedFailureTriggered = true;
      const err = new Error("Simulated SMTP network connection timeout");
      err.status = 503;
      throw err;
    };

    try {
      const failedResendRes = await apiRequest("POST", "/api/auth/register/resend-otp", {
        challenge_id: challengeId2,
      });

      assert.strictEqual(simulatedFailureTriggered, true, "Simulated failure should have been triggered");
      assert.strictEqual(failedResendRes.statusCode, 503, "SMTP failure must return HTTP 503");
      assert.strictEqual(
        failedResendRes.body.message,
        "Email delivery service is currently unavailable. Please try again later."
      );

      // CRITICAL: challengeId2 MUST STILL BE UNCONSUMED (recoverable!)
      const { rows: checkRecoverable } = await pool.query(
        "SELECT consumed_at FROM email_otp_challenges WHERE id = $1",
        [challengeId2]
      );
      assert.strictEqual(
        checkRecoverable[0].consumed_at,
        null,
        "Old challenge must remain active and unconsumed if email delivery failed"
      );
      console.log("✓ Test 4 Passed: SMTP failure keeps old challenge active and recoverable, returning sanitized 503");
    } finally {
      // Restore original email service
      emailService.sendOtpEmail = originalSendOtp;
    }

    // 4. Verify that the user can still verify with the OTP from challengeId2!
    const verifyRes = await apiRequest("POST", "/api/auth/register/verify-otp", {
      challenge_id: challengeId2,
      otp: resendCaptured.otp,
    });
    assert.strictEqual(verifyRes.statusCode, 200, `Verification should succeed with active challenge: ${JSON.stringify(verifyRes.body)}`);
    console.log("✓ Test 5 Passed: Registration successfully completes using the unstranded challenge");

    // 5. Concurrent Resend Test
    // Create a new pending challenge to test race condition handling
    const concurrentEmail = `concurrent_test_${Date.now()}@example.com`;
    const regResConcurrent = await apiRequest("POST", "/api/auth/register", {
      name: "Concurrent Test User",
      email: concurrentEmail,
      password: "Password123!",
    });
    assert.strictEqual(regResConcurrent.statusCode, 201);
    const concurrentChallengeId = regResConcurrent.body.challenge_id || regResConcurrent.body.challengeId;

    await pool.query(
      "UPDATE email_otp_challenges SET last_sent_at = NOW() - INTERVAL '65 seconds' WHERE id = $1",
      [concurrentChallengeId]
    );

    // Trigger two resends simultaneously
    const [resendA, resendB] = await Promise.all([
      apiRequest("POST", "/api/auth/register/resend-otp", { challenge_id: concurrentChallengeId }),
      apiRequest("POST", "/api/auth/register/resend-otp", { challenge_id: concurrentChallengeId }),
    ]);

    // One must succeed (200), the second must either encounter consumed challenge (400) or cooldown (429)
    const statuses = [resendA.statusCode, resendB.statusCode].sort();
    assert.strictEqual(statuses[0], 200, "At least one concurrent resend must succeed");
    assert(
      statuses[1] === 400 || statuses[1] === 429,
      `Second concurrent resend must be rejected with 400 or 429, got: ${statuses[1]}`
    );

    // Verify only ONE active challenge remains for this pending registration
    const { rows: activeChallenges } = await pool.query(
      "SELECT id FROM email_otp_challenges WHERE email = $1 AND consumed_at IS NULL",
      [concurrentEmail]
    );
    assert.strictEqual(
      activeChallenges.length,
      1,
      `Expected exactly 1 active challenge, found ${activeChallenges.length}`
    );
    console.log("✓ Test 6 Passed: Concurrent resends serialized safely with FOR UPDATE; exactly 1 active challenge remains");

    // Clean up test data
    await pool.query("DELETE FROM users WHERE email IN ($1, $2)", [testEmail, concurrentEmail]);
    await pool.query("DELETE FROM pending_registrations WHERE email IN ($1, $2)", [testEmail, concurrentEmail]);
    await pool.query("DELETE FROM email_otp_challenges WHERE email IN ($1, $2)", [testEmail, concurrentEmail]);

    console.log("\nALL REGISTRATION OTP RESEND TESTS PASSED SUCCESSFULLY.\n");
  } finally {
    server.close();
    await pool.end();
  }
}

runTests().catch(async (err) => {
  console.error("Test failure:", err);
  if (server) server.close();
  try {
    await pool.end();
  } catch (_) {}
  process.exit(1);
});
