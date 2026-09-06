/**
 * FreshTrack CORS Configuration
 *
 * Implements strict, URL-parsed origin validation:
 * - Allows requests without an Origin header (Flutter mobile, curl, server clients).
 * - Development: Allows localhost and 127.0.0.1 on any port, plus configured allowlist.
 * - Production: Requires exact matches against CORS_ALLOWED_ORIGINS (fails closed).
 * - Disallowed cross-origin requests receive a sanitized HTTP 403 Forbidden.
 * - Bearer authentication does not require cookie credentials (credentials: false).
 */

const { URL } = require("url");

/**
 * Validates whether an incoming Origin is permitted.
 *
 * @param {string|undefined} origin
 * @param {object} [env=process.env]
 * @returns {boolean}
 */
function isOriginAllowed(origin, env = process.env) {
  // 1. Allow non-browser requests with no Origin header (mobile apps, curl, etc.)
  if (!origin || typeof origin !== "string" || origin.trim() === "") {
    return true;
  }

  const trimmedOrigin = origin.trim();
  let parsedOrigin;
  try {
    parsedOrigin = new URL(trimmedOrigin);
  } catch (_) {
    return false;
  }

  const isProduction = env.NODE_ENV === "production";
  const allowedOriginsEnv = env.CORS_ALLOWED_ORIGINS;

  // Build normalized allowlist from environment
  const allowedList = [];
  if (allowedOriginsEnv && allowedOriginsEnv.trim().length > 0) {
    const rawEntries = allowedOriginsEnv.split(",");
    for (const raw of rawEntries) {
      const entry = raw.trim();
      if (entry) {
        try {
          const parsed = new URL(entry);
          allowedList.push(parsed.origin.toLowerCase());
        } catch (_) {}
      }
    }
  }

  // 2. Production: exact allowlist match only
  if (isProduction) {
    return allowedList.includes(parsedOrigin.origin.toLowerCase());
  }

  // 3. Development / Test: allow localhost and 127.0.0.1 on any port, or configured allowlist
  const hostname = parsedOrigin.hostname.toLowerCase();
  if (
    (parsedOrigin.protocol === "http:" || parsedOrigin.protocol === "https:") &&
    (hostname === "localhost" || hostname === "127.0.0.1")
  ) {
    return true;
  }

  return allowedList.includes(parsedOrigin.origin.toLowerCase());
}

/**
 * Custom Express middleware for CORS validation.
 * Directly returns sanitized HTTP 403 on rejected origins.
 */
function corsMiddleware(req, res, next) {
  const origin = req.headers.origin;

  if (!isOriginAllowed(origin)) {
    return res.status(403).json({
      message: "Cross-Origin request forbidden.",
    });
  }

  if (origin) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }

  res.setHeader(
    "Access-Control-Allow-Methods",
    "GET, POST, PUT, PATCH, DELETE, OPTIONS"
  );
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization"
  );

  // Handle preflight requests
  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }

  next();
}

module.exports = {
  isOriginAllowed,
  corsMiddleware,
};
