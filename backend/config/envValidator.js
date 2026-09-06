/**
 * FreshTrack Environment Validator
 * Validates mandatory environment variables, numeric ports, boolean flags,
 * and cryptographic JWT secret format before application startup.
 *
 * Enforces fail-fast security: reports variable names ONLY, never secret values.
 */

const MANDATORY_VARS = [
  "DB_HOST",
  "DB_PORT",
  "DB_NAME",
  "DB_USER",
  "DB_PASSWORD",
  "JWT_SECRET",
  "JWT_EXPIRES_IN",
];

const REQUIRED_SMTP_VARS = [
  "SMTP_HOST",
  "SMTP_PORT",
  "SMTP_USER",
  "SMTP_PASSWORD",
];

const BOOLEAN_VARS = [
  "ENABLE_REMINDER_SCHEDULER",
  "SMTP_SECURE",
  "ALLOW_INTEGRATION_TEST_DB",
  "ALLOW_TEST_OTP_CAPTURE",
  "ALLOW_PRODUCTION_MIGRATIONS",
];

/**
 * Validates whether a secret key provides at least 32 bytes (256 bits)
 * of cryptographically decoded key material.
 *
 * @param {string} secret
 * @returns {boolean}
 */
function isValidCryptographicKey(secret) {
  if (typeof secret !== "string") return false;
  const trimmed = secret.trim();

  // 1. Hexadecimal format (at least 64 hex characters = 32 bytes)
  const isHex = /^[0-9a-fA-F]{64,}$/.test(trimmed);
  if (isHex && trimmed.length % 2 === 0) {
    const buf = Buffer.from(trimmed, "hex");
    if (buf.length >= 32) return true;
  }

  // 2. Base64 / Base64URL format (at least 43 chars = 32 bytes)
  const isBase64 = /^[A-Za-z0-9+/=_-]{43,}$/.test(trimmed);
  if (isBase64) {
    // Normalize Base64URL
    let base64 = trimmed.replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4 !== 0) base64 += "=";
    const buf = Buffer.from(base64, "base64");
    if (buf.length >= 32) return true;
  }

  return false;
}

/**
 * Validates a network port number (1-65535).
 *
 * @param {*} val
 * @returns {boolean}
 */
function isValidPort(val) {
  if (val === undefined || val === null || String(val).trim() === "") {
    return false;
  }
  const n = Number(String(val).trim());
  return Number.isInteger(n) && n >= 1 && n <= 65535;
}

/**
 * Validates all mandatory environment configuration.
 * Throws Error listing missing or invalid variable names only.
 *
 * @param {object} [env=process.env]
 */
function validateEnv(env = process.env) {
  const missing = [];
  const invalid = [];

  // 1. Check mandatory presence
  for (const v of MANDATORY_VARS) {
    if (!env[v] || String(env[v]).trim() === "") {
      missing.push(v);
    }
  }

  // 2. Check SMTP variables (skipped strictly in triple-guarded test capture mode)
  const isTestOtpCaptureMode =
    env.NODE_ENV === "test" && env.ALLOW_TEST_OTP_CAPTURE === "true";

  if (!isTestOtpCaptureMode) {
    for (const v of REQUIRED_SMTP_VARS) {
      if (!env[v] || String(env[v]).trim() === "") {
        missing.push(v);
      }
    }
  }

  // 3. Require CORS_ALLOWED_ORIGINS in production
  if (env.NODE_ENV === "production") {
    if (!env.CORS_ALLOWED_ORIGINS || String(env.CORS_ALLOWED_ORIGINS).trim() === "") {
      missing.push("CORS_ALLOWED_ORIGINS");
    }
  }

  // 3. Check port validation
  if (env.DB_PORT && !isValidPort(env.DB_PORT)) {
    invalid.push("DB_PORT");
  }
  if (env.PORT && !isValidPort(env.PORT)) {
    invalid.push("PORT");
  }
  if (!isTestOtpCaptureMode && env.SMTP_PORT && !isValidPort(env.SMTP_PORT)) {
    invalid.push("SMTP_PORT");
  }

  // 4. Check boolean formats
  for (const b of BOOLEAN_VARS) {
    if (env[b] !== undefined && env[b] !== null && String(env[b]).trim() !== "") {
      const val = String(env[b]).trim().toLowerCase();
      if (val !== "true" && val !== "false") {
        invalid.push(b);
      }
    }
  }

  // 5. Check cryptographic JWT secret format & decoded entropy
  if (env.JWT_SECRET && !isValidCryptographicKey(env.JWT_SECRET)) {
    invalid.push("JWT_SECRET");
  }

  // 6. Fail fast with variable names only
  if (missing.length > 0 || invalid.length > 0) {
    const errorParts = [];
    if (missing.length > 0) {
      errorParts.push(`Missing variable(s): ${missing.join(", ")}`);
    }
    if (invalid.length > 0) {
      errorParts.push(`Invalid format/range for: ${invalid.join(", ")}`);
    }
    throw new Error(`Environment configuration error: ${errorParts.join("; ")}`);
  }
}

module.exports = {
  validateEnv,
  isValidCryptographicKey,
  isValidPort,
};
