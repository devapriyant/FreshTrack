const rateLimit = require("express-rate-limit");

/**
 * FreshTrack Two-Tier Independent Rate Limiting
 *
 * NOTE: The default in-memory store is local to a single Node.js process.
 * For production multi-instance / clustered deployments, configure a
 * shared distributed store such as Redis using `rate-limit-redis`.
 */

// Helper to disable rate limiting if explicitly requested by test runner
const shouldSkip = () => process.env.DISABLE_RATE_LIMITING === "true";

// Standard 429 JSON response handler
const rateLimitHandler = (message) => (req, res) => {
  res.status(429).json({
    message: message || "Too many requests. Please try again later.",
  });
};

// 1. Independent IP Limiters
const ipStrictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_IP_STRICT_MAX || "30", 10),
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
  skip: shouldSkip,
  handler: rateLimitHandler(
    "Too many requests from this IP. Please try again later."
  ),
});

const ipOtpLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_IP_OTP_MAX || "60", 10),
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
  skip: shouldSkip,
  handler: rateLimitHandler(
    "Too many OTP requests from this IP. Please try again later."
  ),
});

// 2. Independent Identity Limiters
const emailRegisterLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_EMAIL_REGISTER_MAX || "5", 10),
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
  skip: shouldSkip,
  keyGenerator: (req) => {
    if (req.body && typeof req.body.email === "string") {
      return `reg_${req.body.email.trim().toLowerCase()}`;
    }
    return `reg_ip_${req.ip}`;
  },
  handler: rateLimitHandler(
    "Too many registration attempts for this email. Please try again later."
  ),
});

const emailLoginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_EMAIL_LOGIN_MAX || "5", 10),
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
  skip: shouldSkip,
  keyGenerator: (req) => {
    if (req.body && typeof req.body.email === "string") {
      return `login_${req.body.email.trim().toLowerCase()}`;
    }
    return `login_ip_${req.ip}`;
  },
  handler: rateLimitHandler(
    "Too many login attempts for this email. Please try again later."
  ),
});

const emailVerifyStartLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_EMAIL_VERIFY_START_MAX || "5", 10),
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
  skip: shouldSkip,
  keyGenerator: (req) => {
    if (req.body && typeof req.body.email === "string") {
      return `verify_start_${req.body.email.trim().toLowerCase()}`;
    }
    return `verify_start_ip_${req.ip}`;
  },
  handler: rateLimitHandler(
    "Too many verification requests for this email. Please try again later."
  ),
});

const challengeVerifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_CHALLENGE_VERIFY_MAX || "10", 10),
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
  skip: shouldSkip,
  keyGenerator: (req) => {
    if (req.body && typeof req.body.challenge_id === "string") {
      return `challenge_v_${req.body.challenge_id.trim()}`;
    }
    return `challenge_v_ip_${req.ip}`;
  },
  handler: rateLimitHandler(
    "Too many code verification attempts for this challenge. Please request a new code."
  ),
});

const challengeResendLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_CHALLENGE_RESEND_MAX || "3", 10),
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
  skip: shouldSkip,
  keyGenerator: (req) => {
    if (req.body && typeof req.body.challenge_id === "string") {
      return `challenge_r_${req.body.challenge_id.trim()}`;
    }
    return `challenge_r_ip_${req.ip}`;
  },
  handler: rateLimitHandler(
    "Too many code resend attempts. Please wait before requesting another code."
  ),
});

module.exports = {
  ipStrictLimiter,
  ipOtpLimiter,
  emailRegisterLimiter,
  emailLoginLimiter,
  emailVerifyStartLimiter,
  challengeVerifyLimiter,
  challengeResendLimiter,
};
