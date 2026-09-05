const jwt = require("jsonwebtoken");

/**
 * Express middleware to authenticate JWT and enforce valid user identity.
 * Validates that req.user.id exists and is a positive integer.
 */
function authenticateToken(req, res, next) {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) {
    return res.status(401).json({
      message: "Access token required. Please log in.",
    });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(401).json({
        message: "Invalid or expired access token. Please log in again.",
      });
    }

    // Strictly validate req.user.id as a positive integer
    if (!user || !Number.isInteger(user.id) || user.id <= 0) {
      return res.status(401).json({
        message: "Invalid token payload identity. Please log in again.",
      });
    }

    req.user = user;
    next();
  });
}

module.exports = authenticateToken;
