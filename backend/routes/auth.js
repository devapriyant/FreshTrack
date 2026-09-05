const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");
const pool = require("../config/database");
const authenticateToken = require("../middleware/auth");
const {
  createOtpChallenge,
  verifyOtpChallenge,
  resendOtpChallenge,
  invalidateChallenge,
  maskEmail,
} = require("../services/otpService");
const { sendOtpEmail } = require("../services/emailService");
const {
  ipStrictLimiter,
  ipOtpLimiter,
  emailRegisterLimiter,
  emailLoginLimiter,
  emailVerifyStartLimiter,
  challengeVerifyLimiter,
  challengeResendLimiter,
} = require("../middleware/rateLimiter");

const router = express.Router();

function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

// ==========================================
// 1. Registration Flow with Pending Table
// ==========================================

// POST /api/auth/register - Initiates registration, sends OTP (NO JWT issued)
router.post(
  "/register",
  ipStrictLimiter,
  emailRegisterLimiter,
  async (req, res, next) => {
    try {
      const { name, email, password } = req.body;

      if (!name || typeof name !== "string" || name.trim().length === 0) {
        return res.status(400).json({ message: "Name is required." });
      }

      if (!email || typeof email !== "string" || !isValidEmail(email.trim())) {
        return res
          .status(400)
          .json({ message: "A valid email address is required." });
      }

      if (!password || typeof password !== "string" || password.length < 6) {
        return res.status(400).json({
          message: "Password must be at least 6 characters long.",
        });
      }

      const normalizedEmail = email.trim().toLowerCase();
      const trimmedName = name.trim();

      // Check if verified account already exists in users
      const existingUser = await pool.query(
        "SELECT id FROM users WHERE LOWER(email) = $1",
        [normalizedEmail]
      );

      if (existingUser.rows.length > 0) {
        return res.status(409).json({
          message: "An account with this email address already exists.",
        });
      }

      // Hash password with bcryptjs
      const saltRounds = 10;
      const passwordHash = await bcrypt.hash(password, saltRounds);

      // Insert or update pending_registrations table (unverified records NEVER touch users table)
      const pendingRegId = crypto.randomUUID();
      const pendingRes = await pool.query(
        `INSERT INTO pending_registrations (id, name, email, password_hash, created_at, updated_at)
         VALUES ($1, $2, $3, $4, NOW(), NOW())
         ON CONFLICT (email) DO UPDATE SET
           name = EXCLUDED.name,
           password_hash = EXCLUDED.password_hash,
           updated_at = NOW()
         RETURNING id`,
        [pendingRegId, trimmedName, normalizedEmail, passwordHash]
      );

      const actualPendingId = pendingRes.rows[0].id;

      // Create OTP challenge linked to pending registration
      const challenge = await createOtpChallenge({
        email: normalizedEmail,
        purpose: "register",
        pendingRegistrationId: actualPendingId,
      });

      // Dispatch real email via emailService
      try {
        await sendOtpEmail({
          to: normalizedEmail,
          name: trimmedName,
          otp: challenge.plainOtp,
          purpose: "register",
        });
      } catch (emailErr) {
        // SMTP delivery failure: invalidate the challenge immediately and return 503
        await invalidateChallenge(challenge.challengeId);
        return res.status(503).json({
          message:
            "Email delivery service is currently unavailable. Please try again later.",
        });
      }

      return res.status(201).json({
        message: "Verification code sent to your email.",
        challenge_id: challenge.challengeId,
        email: challenge.maskedEmail,
        expires_in_seconds: challenge.expiresInSeconds,
      });
    } catch (error) {
      next(error);
    }
  }
);

// POST /api/auth/register/verify-otp - Verifies OTP and transactionally creates the user
router.post(
  "/register/verify-otp",
  ipOtpLimiter,
  challengeVerifyLimiter,
  async (req, res, next) => {
    const { challenge_id, otp } = req.body;

    if (!challenge_id || !otp) {
      return res.status(400).json({
        message: "Challenge ID and verification code are required.",
      });
    }

    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      // 1. Lock challenge row and validate OTP
      const { challenge } = await verifyOtpChallenge({
        challengeId: challenge_id,
        plainOtp: otp,
        expectedPurpose: "register",
        client,
      });

      // 2. Mark challenge consumed
      await client.query(
        `UPDATE email_otp_challenges SET consumed_at = NOW() WHERE id = $1`,
        [challenge.id]
      );

      // 3. Load pending registration data
      const pendingRes = await client.query(
        `SELECT * FROM pending_registrations WHERE email = $1 FOR UPDATE`,
        [challenge.email]
      );

      if (pendingRes.rows.length === 0) {
        await client.query("ROLLBACK");
        return res.status(400).json({
          message:
            "Registration session not found or has expired. Please register again.",
        });
      }

      const pendingUser = pendingRes.rows[0];

      // 4. Double check users table to prevent race conditions
      const duplicateCheck = await client.query(
        "SELECT id FROM users WHERE LOWER(email) = $1",
        [pendingUser.email.toLowerCase()]
      );

      if (duplicateCheck.rows.length > 0) {
        await client.query("ROLLBACK");
        return res.status(409).json({
          message: "An account with this email address already exists.",
        });
      }

      // 5. Insert verified user into users table
      await client.query(
        `INSERT INTO users (name, email, password_hash, email_verified, email_verified_at, created_at)
         VALUES ($1, $2, $3, TRUE, NOW(), NOW())`,
        [pendingUser.name, pendingUser.email, pendingUser.password_hash]
      );

      // 6. Delete pending registration record (foreign key on challenge automatically sets to NULL)
      await client.query(`DELETE FROM pending_registrations WHERE id = $1`, [
        pendingUser.id,
      ]);

      await client.query("COMMIT");

      // NO JWT is issued upon registration; normal login is strictly required
      return res.json({
        message:
          "Email verified successfully! You can now log in with your credentials.",
      });
    } catch (error) {
      try {
        await client.query("ROLLBACK");
      } catch (_) {}
      if (error.status) {
        return res.status(error.status).json({ message: error.message });
      }
      next(error);
    } finally {
      client.release();
    }
  }
);

// POST /api/auth/register/resend-otp - Resends registration OTP
router.post(
  "/register/resend-otp",
  ipOtpLimiter,
  challengeResendLimiter,
  async (req, res, next) => {
    try {
      const { challenge_id } = req.body;
      if (!challenge_id) {
        return res.status(400).json({ message: "Challenge ID is required." });
      }

      const newChallenge = await resendOtpChallenge({
        challengeId: challenge_id,
        expectedPurpose: "register",
      });

      try {
        await sendOtpEmail({
          to: newChallenge.maskedEmail, // masked email placeholder; sendOtpEmail extracts recipient if passed
          otp: newChallenge.plainOtp,
          purpose: "register",
        });
      } catch (err) {
        // Find recipient email from new challenge record
        const emailRes = await pool.query(
          "SELECT email FROM email_otp_challenges WHERE id = $1",
          [newChallenge.challengeId]
        );
        const recipient =
          emailRes.rows.length > 0 ? emailRes.rows[0].email : null;

        if (recipient) {
          try {
            await sendOtpEmail({
              to: recipient,
              otp: newChallenge.plainOtp,
              purpose: "register",
            });
          } catch (deliveryErr) {
            await invalidateChallenge(newChallenge.challengeId);
            return res.status(503).json({
              message:
                "Email delivery service is currently unavailable. Please try again later.",
            });
          }
        }
      }

      return res.json({
        message: "A new verification code has been sent to your email.",
        challenge_id: newChallenge.challengeId,
        email: newChallenge.maskedEmail,
        expires_in_seconds: newChallenge.expiresInSeconds,
      });
    } catch (error) {
      if (error.status) {
        return res.status(error.status).json({ message: error.message });
      }
      next(error);
    }
  }
);

// ==========================================
// 2. Login Flow with Two-Factor Email OTP
// ==========================================

// POST /api/auth/login - Step 1: Validates credentials, issues login OTP challenge (NO JWT)
router.post(
  "/login",
  ipStrictLimiter,
  emailLoginLimiter,
  async (req, res, next) => {
    try {
      const { email, password } = req.body;

      if (!email || !password) {
        return res.status(400).json({
          message: "Email and password are required.",
        });
      }

      const normalizedEmail = email.trim().toLowerCase();

      // Find user by email
      const result = await pool.query(
        "SELECT id, name, email, password_hash, email_verified, created_at FROM users WHERE LOWER(email) = $1",
        [normalizedEmail]
      );

      // Generic error response to prevent user enumeration
      if (result.rows.length === 0) {
        return res.status(401).json({
          message: "Invalid email or password.",
        });
      }

      const user = result.rows[0];

      // Compare password hash
      const isMatch = await bcrypt.compare(password, user.password_hash);
      if (!isMatch) {
        return res.status(401).json({
          message: "Invalid email or password.",
        });
      }

      // Check email verification status
      if (!user.email_verified) {
        return res.status(403).json({
          message:
            "Email verification is required before logging in. Please verify your email.",
          verification_required: true,
          email: maskEmail(user.email),
        });
      }

      // Create login OTP challenge linked to user
      const challenge = await createOtpChallenge({
        email: user.email,
        purpose: "login",
        userId: user.id,
      });

      // Dispatch login OTP email
      try {
        await sendOtpEmail({
          to: user.email,
          name: user.name,
          otp: challenge.plainOtp,
          purpose: "login",
        });
      } catch (err) {
        await invalidateChallenge(challenge.challengeId);
        return res.status(503).json({
          message:
            "Email delivery service is currently unavailable. Please try again later.",
        });
      }

      // Return challenge response (NO JWT is issued here)
      return res.json({
        message: "Verification code sent to your email.",
        challenge_id: challenge.challengeId,
        email: challenge.maskedEmail,
        expires_in_seconds: challenge.expiresInSeconds,
      });
    } catch (error) {
      next(error);
    }
  }
);

// POST /api/auth/login/verify-otp - Step 2: Verifies OTP and signs verified JWT
// NOTE: This is the ONLY endpoint permitted to return an access JWT
router.post(
  "/login/verify-otp",
  ipOtpLimiter,
  challengeVerifyLimiter,
  async (req, res, next) => {
    const { challenge_id, otp } = req.body;

    if (!challenge_id || !otp) {
      return res.status(400).json({
        message: "Challenge ID and verification code are required.",
      });
    }

    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      // 1. Lock challenge row and verify OTP code
      const { challenge } = await verifyOtpChallenge({
        challengeId: challenge_id,
        plainOtp: otp,
        expectedPurpose: "login",
        client,
      });

      // 2. Mark challenge consumed
      await client.query(
        `UPDATE email_otp_challenges SET consumed_at = NOW() WHERE id = $1`,
        [challenge.id]
      );

      // 3. Load verified user record
      const userRes = await client.query(
        `SELECT id, name, email, email_verified, created_at FROM users WHERE id = $1`,
        [challenge.user_id]
      );

      if (userRes.rows.length === 0) {
        await client.query("ROLLBACK");
        return res.status(404).json({
          message: "User account associated with this challenge was not found.",
        });
      }

      const user = userRes.rows[0];

      if (!user.email_verified) {
        await client.query("ROLLBACK");
        return res.status(403).json({
          message: "Account email is unverified.",
          verification_required: true,
        });
      }

      await client.query("COMMIT");

      // 4. Sign JWT strictly containing authenticated user identity
      const tokenPayload = {
        id: user.id,
        email: user.email,
      };

      const token = jwt.sign(tokenPayload, process.env.JWT_SECRET, {
        expiresIn: process.env.JWT_EXPIRES_IN || "7d",
      });

      return res.json({
        message: "Login successful.",
        token,
        user: {
          id: user.id,
          name: user.name,
          email: user.email,
          email_verified: user.email_verified,
          created_at: user.created_at,
        },
      });
    } catch (error) {
      await client.query("ROLLBACK");
      if (error.status) {
        return res.status(error.status).json({ message: error.message });
      }
      next(error);
    } finally {
      client.release();
    }
  }
);

// POST /api/auth/login/resend-otp - Resends login OTP
router.post(
  "/login/resend-otp",
  ipOtpLimiter,
  challengeResendLimiter,
  async (req, res, next) => {
    try {
      const { challenge_id } = req.body;
      if (!challenge_id) {
        return res.status(400).json({ message: "Challenge ID is required." });
      }

      const newChallenge = await resendOtpChallenge({
        challengeId: challenge_id,
        expectedPurpose: "login",
      });

      // Fetch user name and email for delivery
      const infoRes = await pool.query(
        `SELECT u.name, eoc.email
         FROM email_otp_challenges eoc
         LEFT JOIN users u ON eoc.user_id = u.id
         WHERE eoc.id = $1`,
        [newChallenge.challengeId]
      );

      const recipient =
        infoRes.rows.length > 0 ? infoRes.rows[0].email : null;
      const recipientName =
        infoRes.rows.length > 0 && infoRes.rows[0].name
          ? infoRes.rows[0].name
          : "User";

      if (recipient) {
        try {
          await sendOtpEmail({
            to: recipient,
            name: recipientName,
            otp: newChallenge.plainOtp,
            purpose: "login",
          });
        } catch (deliveryErr) {
          await invalidateChallenge(newChallenge.challengeId);
          return res.status(503).json({
            message:
              "Email delivery service is currently unavailable. Please try again later.",
          });
        }
      }

      return res.json({
        message: "A new verification code has been sent to your email.",
        challenge_id: newChallenge.challengeId,
        email: newChallenge.maskedEmail,
        expires_in_seconds: newChallenge.expiresInSeconds,
      });
    } catch (error) {
      if (error.status) {
        return res.status(error.status).json({ message: error.message });
      }
      next(error);
    }
  }
);

// ==================================================
// 3. Existing Account Email Verification Flow
// ==================================================

// POST /api/auth/email-verification/start - Starts verification for unverified existing account (requires password)
router.post(
  "/email-verification/start",
  ipStrictLimiter,
  emailVerifyStartLimiter,
  async (req, res, next) => {
    try {
      const { email, password } = req.body;

      if (!email || !password) {
        return res.status(400).json({
          message: "Email and password are required to start verification.",
        });
      }

      const normalizedEmail = email.trim().toLowerCase();

      // Find user
      const userRes = await pool.query(
        "SELECT id, name, email, password_hash, email_verified FROM users WHERE LOWER(email) = $1",
        [normalizedEmail]
      );

      if (userRes.rows.length === 0) {
        return res.status(401).json({
          message: "Invalid email or password.",
        });
      }

      const user = userRes.rows[0];

      // Validate password
      const isMatch = await bcrypt.compare(password, user.password_hash);
      if (!isMatch) {
        return res.status(401).json({
          message: "Invalid email or password.",
        });
      }

      if (user.email_verified) {
        return res.status(400).json({
          message: "Email is already verified. You can proceed to log in.",
        });
      }

      // Create challenge with purpose 'verify_email'
      const challenge = await createOtpChallenge({
        email: user.email,
        purpose: "verify_email",
        userId: user.id,
      });

      // Dispatch email
      try {
        await sendOtpEmail({
          to: user.email,
          name: user.name,
          otp: challenge.plainOtp,
          purpose: "verify_email",
        });
      } catch (err) {
        await invalidateChallenge(challenge.challengeId);
        return res.status(503).json({
          message:
            "Email delivery service is currently unavailable. Please try again later.",
        });
      }

      return res.json({
        message: "Verification code sent to your email.",
        challenge_id: challenge.challengeId,
        email: challenge.maskedEmail,
        expires_in_seconds: challenge.expiresInSeconds,
      });
    } catch (error) {
      next(error);
    }
  }
);

// POST /api/auth/email-verification/verify - Completes email verification for existing account
router.post(
  "/email-verification/verify",
  ipOtpLimiter,
  challengeVerifyLimiter,
  async (req, res, next) => {
    const { challenge_id, otp } = req.body;

    if (!challenge_id || !otp) {
      return res.status(400).json({
        message: "Challenge ID and verification code are required.",
      });
    }

    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      const { challenge } = await verifyOtpChallenge({
        challengeId: challenge_id,
        plainOtp: otp,
        expectedPurpose: "verify_email",
        client,
      });

      // Mark challenge consumed
      await client.query(
        `UPDATE email_otp_challenges SET consumed_at = NOW() WHERE id = $1`,
        [challenge.id]
      );

      // Update user row
      await client.query(
        `UPDATE users SET email_verified = TRUE, email_verified_at = NOW() WHERE id = $1`,
        [challenge.user_id]
      );

      await client.query("COMMIT");

      // NO JWT is issued here; normal login is required
      return res.json({
        message:
          "Email verified successfully! You can now log in with your credentials.",
      });
    } catch (error) {
      await client.query("ROLLBACK");
      if (error.status) {
        return res.status(error.status).json({ message: error.message });
      }
      next(error);
    } finally {
      client.release();
    }
  }
);

// POST /api/auth/email-verification/resend - Resends email verification code
router.post(
  "/email-verification/resend",
  ipOtpLimiter,
  challengeResendLimiter,
  async (req, res, next) => {
    try {
      const { challenge_id } = req.body;
      if (!challenge_id) {
        return res.status(400).json({ message: "Challenge ID is required." });
      }

      const newChallenge = await resendOtpChallenge({
        challengeId: challenge_id,
        expectedPurpose: "verify_email",
      });

      // Fetch user name and email
      const infoRes = await pool.query(
        `SELECT u.name, eoc.email
         FROM email_otp_challenges eoc
         LEFT JOIN users u ON eoc.user_id = u.id
         WHERE eoc.id = $1`,
        [newChallenge.challengeId]
      );

      const recipient =
        infoRes.rows.length > 0 ? infoRes.rows[0].email : null;
      const recipientName =
        infoRes.rows.length > 0 && infoRes.rows[0].name
          ? infoRes.rows[0].name
          : "User";

      if (recipient) {
        try {
          await sendOtpEmail({
            to: recipient,
            name: recipientName,
            otp: newChallenge.plainOtp,
            purpose: "verify_email",
          });
        } catch (deliveryErr) {
          await invalidateChallenge(newChallenge.challengeId);
          return res.status(503).json({
            message:
              "Email delivery service is currently unavailable. Please try again later.",
          });
        }
      }

      return res.json({
        message: "A new verification code has been sent to your email.",
        challenge_id: newChallenge.challengeId,
        email: newChallenge.maskedEmail,
        expires_in_seconds: newChallenge.expiresInSeconds,
      });
    } catch (error) {
      if (error.status) {
        return res.status(error.status).json({ message: error.message });
      }
      next(error);
    }
  }
);

// ==========================================
// 4. Authenticated Profile
// ==========================================

// GET /api/auth/profile - Fetch current authenticated profile
router.get("/profile", authenticateToken, async (req, res, next) => {
  try {
    const userId = req.user.id;

    const result = await pool.query(
      "SELECT id, name, email, email_verified, created_at FROM users WHERE id = $1",
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "User profile not found.",
      });
    }

    const user = result.rows[0];

    return res.json({
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        email_verified: user.email_verified,
        created_at: user.created_at,
      },
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
