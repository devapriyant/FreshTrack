require("dotenv").config();
const fs = require("fs");
const path = require("path");
const pool = require("../config/database");

async function runMigration() {
  console.log("=== FreshTrack Database Migration: Email OTP & Security ===");

  const sqlPath = path.join(__dirname, "email_otp_auth.sql");
  const sql = fs.readFileSync(sqlPath, "utf-8");

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    console.log("Executing email_otp_auth.sql...");
    await client.query(sql);

    // Guarded development-only migration step:
    // Only mark existing users verified if explicitly requested via environment variable or CLI flag
    const devVerifyFlag =
      process.env.MIGRATE_DEV_VERIFY_EXISTING_ACCOUNTS === "true" ||
      process.argv.includes("--dev-verify-existing");

    if (devVerifyFlag) {
      console.log(
        "Development guard detected: Marking existing unverified accounts as verified..."
      );
      const updateResult = await client.query(`
        UPDATE users
        SET email_verified = TRUE,
            email_verified_at = NOW()
        WHERE email_verified IS FALSE
        RETURNING id, email
      `);
      console.log(
        `✓ Marked ${updateResult.rowCount} existing account(s) verified for development.`
      );
    } else {
      console.log(
        "Production safety: Existing user verification state was NOT altered."
      );
    }

    await client.query("COMMIT");
    console.log("✓ Migration completed successfully!");
  } catch (err) {
    await client.query("ROLLBACK");
    console.error("Migration failed:", err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

runMigration();
