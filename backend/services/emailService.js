const nodemailer = require("nodemailer");

// In-memory test store for automated integration tests ONLY
// Strictly guarded by three mandatory environment variables
const _testCapturedOtps = new Map();

/**
 * Checks whether triple-guarded test capture is authorized
 */
function isTestOtpCaptureEnabled() {
  return (
    process.env.NODE_ENV === "test" &&
    process.env.ALLOW_TEST_OTP_CAPTURE === "true" &&
    process.env.ALLOW_INTEGRATION_TEST_DB === "true"
  );
}

/**
 * Retrieves captured OTP for test runner assertions.
 * Returns null if not in authorized test mode or not found.
 */
function getTestCapturedOtp(email) {
  if (!isTestOtpCaptureEnabled()) {
    return null;
  }
  return _testCapturedOtps.get(email.toLowerCase().trim()) || null;
}

/**
 * Clears captured test OTPs.
 */
function clearTestCapturedOtps() {
  _testCapturedOtps.clear();
}

/**
 * Builds or retrieves the configured nodemailer transporter.
 * Returns null if SMTP is unconfigured.
 */
function getTransporter() {
  const host = process.env.SMTP_HOST;
  const port = process.env.SMTP_PORT;
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASSWORD;

  if (!host || !port || !user || !pass) {
    return null;
  }

  return nodemailer.createTransport({
    host: host.trim(),
    port: parseInt(port, 10),
    secure: process.env.SMTP_SECURE === "true" || parseInt(port, 10) === 465,
    auth: {
      user: user.trim(),
      pass: pass,
    },
  });
}

/**
 * Dispatches an OTP verification email to the recipient.
 *
 * @param {object} params
 * @param {string} params.to - Recipient email address
 * @param {string} [params.name] - User name
 * @param {string} params.otp - Plain 6-digit OTP
 * @param {'register' | 'login' | 'verify_email'} params.purpose - Purpose of verification
 * @param {number} [params.expiryMinutes=10] - Expiry time in minutes
 * @returns {Promise<boolean>} True if dispatched or captured in test mode
 * @throws {Error} Throws if SMTP is unavailable or delivery fails (never fakes delivery in dev/prod)
 */
async function sendOtpEmail({
  to,
  name = "User",
  otp,
  purpose,
  expiryMinutes = 10,
}) {
  const normalizedTo = to.toLowerCase().trim();

  // 1. Check triple-guarded test mode for automated test suites
  if (isTestOtpCaptureEnabled()) {
    _testCapturedOtps.set(normalizedTo, {
      otp,
      purpose,
      capturedAt: new Date(),
    });
    return true;
  }

  // 2. Production / Development Real SMTP Dispatch
  const transporter = getTransporter();
  if (!transporter) {
    const err = new Error(
      "SMTP email service is unconfigured. Please configure SMTP credentials in .env."
    );
    err.code = "SMTP_UNCONFIGURED";
    err.status = 503;
    throw err;
  }

  let subject = "FreshTrack Verification Code";
  let headline = "Verification Code";
  let actionText = "verify your request";

  if (purpose === "register") {
    subject = "Verify Your FreshTrack Account";
    headline = "Welcome to FreshTrack!";
    actionText = "complete your account registration";
  } else if (purpose === "login") {
    subject = "Your FreshTrack Login Code";
    headline = "Login Verification";
    actionText = "log in to your FreshTrack account";
  } else if (purpose === "verify_email") {
    subject = "Verify Your FreshTrack Email";
    headline = "Email Verification";
    actionText = "verify your email address";
  }

  const fromName = process.env.SMTP_FROM_NAME || "FreshTrack Security";
  const fromEmail = process.env.SMTP_FROM_EMAIL || process.env.SMTP_USER;
  const fromAddress = `"${fromName}" <${fromEmail}>`;

  const htmlContent = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 32px 24px; background-color: #ffffff; border-radius: 12px; border: 1px solid #e0e0e0;">
      <div style="text-align: center; margin-bottom: 24px;">
        <h2 style="color: #2E7D32; margin: 0; font-size: 24px;">FreshTrack</h2>
        <p style="color: #666; font-size: 14px; margin-top: 4px;">Track. Use. Waste Less.</p>
      </div>
      <h3 style="color: #333; font-size: 20px; margin-bottom: 12px;">${headline}</h3>
      <p style="color: #555; font-size: 15px; line-height: 1.5; margin-bottom: 24px;">
        Hello <strong>${name}</strong>,<br>
        Use the following single-use verification code to ${actionText}. This code will expire in <strong>${expiryMinutes} minutes</strong>.
      </p>
      <div style="text-align: center; margin: 32px 0;">
        <div style="display: inline-block; background-color: #f1f8e9; border: 2px dashed #4caf50; border-radius: 8px; padding: 16px 36px;">
          <span style="font-family: monospace; font-size: 32px; font-weight: bold; letter-spacing: 8px; color: #1b5e20;">${otp}</span>
        </div>
      </div>
      <p style="color: #777; font-size: 13px; line-height: 1.4;">
        If you did not request this verification code, please ignore this email or change your password immediately.
      </p>
      <hr style="border: none; border-top: 1px solid #eee; margin: 24px 0;">
      <p style="color: #999; font-size: 12px; text-align: center; margin: 0;">
        &copy; ${new Date().getFullYear()} FreshTrack. All rights reserved.
      </p>
    </div>
  `;

  const textContent = `
FreshTrack - ${headline}

Hello ${name},

Use the following verification code to ${actionText}:
${otp}

This code expires in ${expiryMinutes} minutes.

If you did not make this request, you can safely ignore this email.
`;

  try {
    await transporter.sendMail({
      from: fromAddress,
      to: normalizedTo,
      subject,
      text: textContent,
      html: htmlContent,
    });
    return true;
  } catch (err) {
    // Sanitize error: never log credentials, OTPs, or sensitive connection dumps
    console.error("SMTP dispatch failed:", err.message);
    const error = new Error(
      "Failed to deliver verification email. Please check SMTP settings or try again later."
    );
    error.code = "SMTP_DELIVERY_FAILED";
    error.status = 503;
    throw error;
  }
}

module.exports = {
  sendOtpEmail,
  isTestOtpCaptureEnabled,
  getTestCapturedOtp,
  clearTestCapturedOtps,
};
