const assert = require("assert");
const http = require("http");
const express = require("express");
const { isOriginAllowed, corsMiddleware } = require("./config/corsConfig");
const { validateEnv } = require("./config/envValidator");

async function runTests() {
  console.log("=== Running CORS Security Tests ===");

  const devEnv = { NODE_ENV: "development", CORS_ALLOWED_ORIGINS: "https://app.freshtrack.com" };
  const prodEnv = { NODE_ENV: "production", CORS_ALLOWED_ORIGINS: "https://app.freshtrack.com" };

  // Test 1: Requests without Origin header succeed (mobile apps, curl)
  assert.strictEqual(isOriginAllowed(undefined, devEnv), true);
  assert.strictEqual(isOriginAllowed("", devEnv), true);
  assert.strictEqual(isOriginAllowed(null, devEnv), true);
  assert.strictEqual(isOriginAllowed(undefined, prodEnv), true);
  console.log("✓ Test 1 Passed: Requests without Origin header allowed (mobile/curl)");

  // Test 2: Localhost and 127.0.0.1 on arbitrary ports permitted in dev
  assert.strictEqual(isOriginAllowed("http://localhost:3000", devEnv), true);
  assert.strictEqual(isOriginAllowed("http://localhost:54321", devEnv), true);
  assert.strictEqual(isOriginAllowed("http://127.0.0.1:8080", devEnv), true);
  assert.strictEqual(isOriginAllowed("https://localhost:443", devEnv), true);
  console.log("✓ Test 2 Passed: Localhost and 127.0.0.1 on arbitrary ports permitted in development");

  // Test 3: Substring domain attacks strictly rejected
  const attacks = [
    "http://localhost.evil.com",
    "http://evil-localhost.com",
    "http://127.0.0.1.attacker.net",
    "http://attacker127.0.0.1.com",
    "https://app.freshtrack.com.attacker.com",
  ];
  for (const attack of attacks) {
    assert.strictEqual(
      isOriginAllowed(attack, devEnv),
      false,
      `Substring attack ${attack} must be rejected in dev`
    );
    assert.strictEqual(
      isOriginAllowed(attack, prodEnv),
      false,
      `Substring attack ${attack} must be rejected in prod`
    );
  }
  console.log("✓ Test 3 Passed: Substring / spoofed origin attacks strictly rejected");

  // Test 4: Production requires exact allowlist match
  assert.strictEqual(isOriginAllowed("http://localhost:3000", prodEnv), false);
  assert.strictEqual(isOriginAllowed("https://app.freshtrack.com", prodEnv), true);
  assert.strictEqual(isOriginAllowed("http://app.freshtrack.com", prodEnv), false); // Scheme mismatch rejected
  console.log("✓ Test 4 Passed: Production strictly enforces exact configured allowlist");

  // Test 5: Production startup fails fast when CORS_ALLOWED_ORIGINS is missing
  const prodEnvWithoutCors = {
    NODE_ENV: "production",
    DB_HOST: "localhost",
    DB_PORT: "5432",
    DB_NAME: "freshtrack_test_db",
    DB_USER: "postgres",
    DB_PASSWORD: "secret_password",
    JWT_SECRET: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    JWT_EXPIRES_IN: "7d",
    SMTP_HOST: "smtp.example.com",
    SMTP_PORT: "587",
    SMTP_USER: "user",
    SMTP_PASSWORD: "pwd",
  };
  assert.throws(
    () => validateEnv(prodEnvWithoutCors),
    (err) => {
      assert(err.message.includes("CORS_ALLOWED_ORIGINS"));
      return true;
    },
    "validateEnv in production must fail if CORS_ALLOWED_ORIGINS is missing"
  );
  console.log("✓ Test 5 Passed: Production startup validation fails when CORS_ALLOWED_ORIGINS is missing");

  // Test 6: HTTP request verification: Disallowed origin returns sanitized 403 (not 500)
  const testApp = express();
  testApp.use(corsMiddleware);
  testApp.get("/api/health", (req, res) => res.json({ status: "ok" }));

  const server = http.createServer(testApp);
  await new Promise((resolve) => server.listen(0, resolve));
  const port = server.address().port;

  // 6a: Allowed request without Origin
  await new Promise((resolve, reject) => {
    http.get(`http://localhost:${port}/api/health`, (res) => {
      assert.strictEqual(res.statusCode, 200);
      resolve();
    }).on("error", reject);
  });

  // 6b: Disallowed origin returns HTTP 403 with sanitized JSON
  await new Promise((resolve, reject) => {
    const req = http.request(
      `http://localhost:${port}/api/health`,
      {
        headers: { Origin: "http://malicious-site.com" },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          try {
            assert.strictEqual(res.statusCode, 403, "Disallowed origin must receive 403 Forbidden");
            const parsed = JSON.parse(data);
            assert.strictEqual(parsed.message, "Cross-Origin request forbidden.");
            assert(!res.headers["access-control-allow-origin"]);
            resolve();
          } catch (e) {
            reject(e);
          }
        });
      }
    );
    req.on("error", reject);
    req.end();
  });

  // 6c: Preflight OPTIONS request for allowed origin returns 204 No Content
  await new Promise((resolve, reject) => {
    const req = http.request(
      `http://localhost:${port}/api/health`,
      {
        method: "OPTIONS",
        headers: {
          Origin: "http://localhost:3000",
          "Access-Control-Request-Method": "POST",
        },
      },
      (res) => {
        try {
          assert.strictEqual(res.statusCode, 204, "Preflight OPTIONS should return 204");
          assert.strictEqual(res.headers["access-control-allow-origin"], "http://localhost:3000");
          assert(res.headers["access-control-allow-methods"].includes("POST"));
          resolve();
        } catch (e) {
          reject(e);
        }
      }
    );
    req.on("error", reject);
    req.end();
  });

  server.close();
  console.log("✓ Test 6 Passed: Express CORS middleware returns sanitized 403 on rejected origins and 204 on preflight");

  console.log("\nALL CORS SECURITY TESTS PASSED SUCCESSFULLY.\n");
}

runTests().catch((err) => {
  console.error("CORS test failure:", err);
  process.exit(1);
});
