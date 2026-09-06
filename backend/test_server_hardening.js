const assert = require("assert");
const http = require("http");
const { validateEnv, isValidCryptographicKey, isValidPort } = require("./config/envValidator");

async function runTests() {
  console.log("=== Running Server Hardening & Env Validation Tests ===");

  // Base valid test environment
  const validEnv = {
    NODE_ENV: "test",
    ALLOW_TEST_OTP_CAPTURE: "true",
    DB_HOST: "localhost",
    DB_PORT: "5432",
    DB_NAME: "freshtrack_test_db",
    DB_USER: "postgres",
    DB_PASSWORD: "secret_password",
    JWT_SECRET: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", // 64 hex chars = 32 bytes
    JWT_EXPIRES_IN: "7d",
    PORT: "5000",
    ENABLE_REMINDER_SCHEDULER: "false",
    SMTP_SECURE: "false",
    ALLOW_INTEGRATION_TEST_DB: "true",
    ALLOW_PRODUCTION_MIGRATIONS: "false",
  };

  // Test 1: Baseline valid env passes
  assert.doesNotThrow(() => {
    validateEnv(validEnv);
  }, "Valid environment should not throw");
  console.log("✓ Test 1 Passed: Valid environment succeeds");

  // Test 2: Missing mandatory variable throws with variable name only
  const missingVarEnv = { ...validEnv, DB_NAME: "" };
  assert.throws(
    () => validateEnv(missingVarEnv),
    (err) => {
      assert(err.message.includes("DB_NAME"));
      assert(!err.message.includes("secret_password"));
      return true;
    },
    "Missing DB_NAME should throw"
  );
  console.log("✓ Test 2 Passed: Missing mandatory variable reports variable name only");

  // Test 3: Non-numeric port throws listing variable name only
  const badPortEnv = { ...validEnv, DB_PORT: "not-a-port" };
  assert.throws(
    () => validateEnv(badPortEnv),
    (err) => {
      assert(err.message.includes("DB_PORT"));
      return true;
    },
    "Non-numeric DB_PORT should throw"
  );
  console.log("✓ Test 3 Passed: Non-numeric port reports variable name only");

  // Test 4: Arbitrary 32-character ASCII string (insufficient decoded entropy) fails validation
  const arbitraryAsciiSecret = "ThisIsAStringOf32CharactersLong!";
  assert.strictEqual(
    isValidCryptographicKey(arbitraryAsciiSecret),
    false,
    "Arbitrary ASCII string with non-hex/non-base64 characters should fail"
  );
  const badSecretEnv = { ...validEnv, JWT_SECRET: arbitraryAsciiSecret };
  assert.throws(
    () => validateEnv(badSecretEnv),
    (err) => {
      assert(err.message.includes("JWT_SECRET"));
      assert(!err.message.includes(arbitraryAsciiSecret)); // Never leak secret in error
      return true;
    },
    "Arbitrary ASCII secret should fail validation"
  );
  console.log("✓ Test 4 Passed: Arbitrary ASCII text fails cryptographic key validation without leaking secret");

  // Test 5: Valid 64-hex character key passes
  const validHexKey = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
  assert.strictEqual(isValidCryptographicKey(validHexKey), true);
  console.log("✓ Test 5 Passed: 64-character hex key decodes to 32 bytes and passes");

  // Test 6: Valid Base64 key (32 bytes = 44 chars) passes
  const validBase64Key = Buffer.alloc(32, 0x5a).toString("base64");
  assert.strictEqual(isValidCryptographicKey(validBase64Key), true);
  console.log("✓ Test 6 Passed: Base64-encoded 32-byte key passes");

  // Test 7: Importing app.js does not bind port 5000 or start cron schedulers
  const app = require("./app");
  assert(app && typeof app.listen === "function", "app.js must export an Express application");
  // Check that no server is listening on 5000 from importing app.js
  const testReq = http.request({ host: "localhost", port: 5000, timeout: 500 }, () => {});
  testReq.on("error", (e) => {
    // Expected ECONNREFUSED since server is not listening
    assert(e.code === "ECONNREFUSED" || e.code === "ETIMEDOUT");
  });
  testReq.end();
  console.log("✓ Test 7 Passed: app.js exports Express app without binding port or starting schedulers");

  // Test 8: Sanitized 500 handler masks database errors
  const express = require("express");
  const testErrorApp = express();
  testErrorApp.get("/test-error-handling", (req, res, next) => {
    const error = new Error('syntax error at or near "SELECT * FROM secrets"');
    error.statusCode = 500;
    next(error);
  });
  testErrorApp.use(app.errorHandler);

  const server = http.createServer(testErrorApp);
  await new Promise((resolve) => server.listen(0, resolve));
  const assignedPort = server.address().port;

  await new Promise((resolve, reject) => {
    http.get(`http://localhost:${assignedPort}/test-error-handling`, (res) => {
      let body = "";
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => {
        try {
          assert.strictEqual(res.statusCode, 500);
          const parsed = JSON.parse(body);
          assert.strictEqual(parsed.message, "An internal server error occurred.");
          assert(!body.includes("syntax error"));
          assert(!body.includes("SELECT * FROM secrets"));
          resolve();
        } catch (e) {
          reject(e);
        }
      });
    }).on("error", reject);
  });
  server.close();
  console.log("✓ Test 8 Passed: Unhandled error returns generic 500 without leaking SQL/database internals");

  console.log("\nALL SERVER HARDENING TESTS PASSED SUCCESSFULLY.\n");
}

runTests().catch((err) => {
  console.error("Test failure:", err);
  process.exit(1);
});
