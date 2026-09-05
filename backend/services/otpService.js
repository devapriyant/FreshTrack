const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const pool = require("../config/database");

const DEFAULT_EXPIRY_MINUTES = 10;
const DEFAULT_COOLDOWN_SECONDS = 60;
const MAX_VERIFICATION_ATTEMPTS = 5;

/**
 * Masks an email address for safe public responses (e.g., 'j***@example.com').
 *
 * @param {string} email
 * @returns {string}
 */
function maskEmail(email) {
  if (!email || typeof email !== "string" || !email.includes("@")) {
    return "***";
  }
  const [localPart, domain] = email.trim().toLowerCase().split("@");
  if (localPart.length <= 1) {
    return `${localPart}***@${domain}`;
  }
  return `${localPart[0]}***@${domain}`;
}

/**
 * Validates whether a string is a valid UUID v4 format.
 *
 * @param {string} str
 * @returns {boolean}
 */
function isValidUuid(str) {
  if (typeof str !== "string") return false;
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str.trim());
}

/**
 * Generates a cryptographically secure 6-digit numeric string.
 *
 * @returns {string} 6-digit numeric string (100000 - 999999)
 */
function generateSixDigitOtp() {
  return crypto.randomInt(100000, 1000000).toString();
}

/**
 * Creates an OTP challenge record in PostgreSQL.
 * Invalidates any prior active challenge for the same email and purpose.
 *
 * @param {object} params
 * @param {string} params.email - Normalized recipient email
 * @param {'register' | 'login' | 'verify_email'} params.purpose - Purpose of challenge
 * @param {number} [params.userId] - Optional user_id (for login or existing account verification)
 * @param {string} [params.pendingRegistrationId] - Optional UUID from pending_registrations
 * @param {object} [params.client=pool] - Optional database client for transaction context
 * @returns {Promise<{ challengeId: string, plainOtp: string, maskedEmail: string, expiresInSeconds: number }>}
 */
async function createOtpChallenge({
  email,
  purpose,
  userId = null,
  pendingRegistrationId = null,
  client = pool,
}) {
  const normalizedEmail = email.trim().toLowerCase();
  const expiryMinutes = parseInt(
    process.env.OTP_EXPIRY_MINUTES || DEFAULT_EXPIRY_MINUTES,
    10
  );

  // 1. Invalidate previous active challenges for this email and purpose
  await client.query(
    `UPDATE email_otp_challenges
     SET consumed_at = NOW()
     WHERE email = $1 AND purpose = $2 AND consumed_at IS NULL`,
    [normalizedEmail, purpose]
  );

  // 2. Generate UUID, 6-digit OTP, and bcrypt hash
  const challengeId = crypto.randomUUID();
  const plainOtp = generateSixDigitOtp();
  const otpHash = await bcrypt.hash(plainOtp, 10);

  // 3. Insert challenge with TIMESTAMPTZ columns
  await client.query(
    `INSERT INTO email_otp_challenges (
       id, user_id, pending_registration_id, email, purpose,
       otp_hash, expires_at, attempts, max_attempts,
       consumed_at, created_at, last_sent_at
     )
     VALUES (
       $1, $2, $3, $4, $5,
       $6, NOW() + ($7 || ' minutes')::INTERVAL, 0, $8,
       NULL, NOW(), NOW()
     )`,
    [
      challengeId,
      userId,
      pendingRegistrationId,
      normalizedEmail,
      purpose,
      otpHash,
      expiryMinutes,
      MAX_VERIFICATION_ATTEMPTS,
    ]
  );

  return {
    challengeId,
    plainOtp,
    maskedEmail: maskEmail(normalizedEmail),
    expiresInSeconds: expiryMinutes * 60,
  };
}

/**
 * Validates and locks an OTP challenge row.
 * Atomically increments attempts counter on invalid OTP code.
 *
 * @param {object} params
 * @param {string} params.challengeId - Challenge UUID
 * @param {string} params.plainOtp - Submitted 6-digit OTP
 * @param {'register' | 'login' | 'verify_email'} params.expectedPurpose
 * @param {object} [params.client=pool] - Active database client for transaction
 * @returns {Promise<{ challenge: object, isValid: boolean }>}
 */
async function verifyOtpChallenge({
  challengeId,
  plainOtp,
  expectedPurpose,
  client = pool,
}) {
  if (!isValidUuid(challengeId)) {
    const err = new Error("Invalid or malformed verification request.");
    err.status = 400;
    throw err;
  }

  if (
    !plainOtp ||
    typeof plainOtp !== "string" ||
    plainOtp.trim().length !== 6 ||
    !/^\d{6}$/.test(plainOtp.trim())
  ) {
    const err = new Error("A valid 6-digit numeric code is required.");
    err.status = 400;
    throw err;
  }

  // Row-level lock to prevent race conditions during verification
  const res = await client.query(
    `SELECT * FROM email_otp_challenges WHERE id = $1 FOR UPDATE`,
    [challengeId.trim()]
  );

  if (res.rows.length === 0) {
    const err = new Error("Verification challenge not found or has expired.");
    err.status = 400;
    throw err;
  }

  const challenge = res.rows[0];

  if (challenge.purpose !== expectedPurpose) {
    const err = new Error("Invalid challenge purpose.");
    err.status = 400;
    throw err;
  }

  if (challenge.consumed_at !== null) {
    const err = new Error("This verification code has already been used.");
    err.status = 400;
    throw err;
  }

  const now = new Date();
  if (new Date(challenge.expires_at) < now) {
    const err = new Error(
      "Verification code has expired. Please request a new one."
    );
    err.status = 400;
    throw err;
  }

  if (challenge.attempts >= challenge.max_attempts) {
    const err = new Error(
      "Maximum verification attempts exceeded. Please request a new code."
    );
    err.status = 400;
    throw err;
  }

  // Compare submitted OTP against stored bcrypt hash
  const isMatch = await bcrypt.compare(plainOtp.trim(), challenge.otp_hash);

  if (!isMatch) {
    // Atomically increment failed attempts and commit to DB
    await client.query(
      `UPDATE email_otp_challenges SET attempts = attempts + 1 WHERE id = $1`,
      [challenge.id]
    );

    try {
      await client.query("COMMIT");
    } catch (_) {
      // In case client was not in an explicit transaction block
    }

    const remainingAttempts = challenge.max_attempts - (challenge.attempts + 1);
    const err = new Error(
      remainingAttempts > 0
        ? `Invalid verification code. ${remainingAttempts} attempt(s) remaining.`
        : "Maximum verification attempts exceeded. Please request a new code."
    );
    err.status = 400;
    throw err;
  }

  return {
    challenge,
    isValid: true,
  };
}

/**
 * Resends an OTP challenge, enforcing the 60-second cooldown period.
 *
 * @param {object} params
 * @param {string} params.challengeId
 * @param {'register' | 'login' | 'verify_email'} params.expectedPurpose
 * @param {object} [params.client=pool]
 * @returns {Promise<{ challengeId: string, plainOtp: string, maskedEmail: string, expiresInSeconds: number }>}
 */
async function resendOtpChallenge({
  challengeId,
  expectedPurpose,
  client = pool,
}) {
  if (!isValidUuid(challengeId)) {
    const err = new Error("Invalid challenge ID.");
    err.status = 400;
    throw err;
  }

  const res = await client.query(
    `SELECT * FROM email_otp_challenges WHERE id = $1 FOR UPDATE`,
    [challengeId.trim()]
  );

  if (res.rows.length === 0) {
    const err = new Error("Verification challenge not found.");
    err.status = 404;
    throw err;
  }

  const challenge = res.rows[0];

  if (challenge.purpose !== expectedPurpose) {
    const err = new Error("Invalid challenge purpose.");
    err.status = 400;
    throw err;
  }

  const cooldownSeconds = parseInt(
    process.env.OTP_RESEND_COOLDOWN_SECONDS || DEFAULT_COOLDOWN_SECONDS,
    10
  );

  const lastSent = new Date(challenge.last_sent_at).getTime();
  const now = Date.now();
  const elapsedSeconds = Math.floor((now - lastSent) / 1000);

  if (elapsedSeconds < cooldownSeconds) {
    const remainingSeconds = cooldownSeconds - elapsedSeconds;
    const err = new Error(
      `Please wait ${remainingSeconds} second(s) before requesting another code.`
    );
    err.status = 429;
    err.retryAfter = remainingSeconds;
    throw err;
  }

  // Invalidate old challenge
  await client.query(
    `UPDATE email_otp_challenges SET consumed_at = NOW() WHERE id = $1`,
    [challenge.id]
  );

  // Issue new challenge
  return await createOtpChallenge({
    email: challenge.email,
    purpose: challenge.purpose,
    userId: challenge.user_id,
    pendingRegistrationId: challenge.pending_registration_id,
    client,
  });
}

/**
 * Safely deletes or invalidates a newly created challenge upon delivery failure.
 *
 * @param {string} challengeId
 * @param {object} [client=pool]
 */
async function invalidateChallenge(challengeId, client = pool) {
  if (!isValidUuid(challengeId)) return;
  try {
    await client.query(`DELETE FROM email_otp_challenges WHERE id = $1`, [
      challengeId,
    ]);
  } catch (err) {
    console.error("Failed to invalidate challenge after error:", err.message);
  }
}

module.exports = {
  maskEmail,
  isValidUuid,
  generateSixDigitOtp,
  createOtpChallenge,
  verifyOtpChallenge,
  resendOtpChallenge,
  invalidateChallenge,
  MAX_VERIFICATION_ATTEMPTS,
};
