require("dotenv").config();
const assert = require("assert");
const { runMigrations } = require("./sql/migrate");
const pool = require("./config/database");

async function runTests() {
  console.log("=== Running Database Migration & Guard Tests ===");

  const originalDbName = process.env.DB_NAME;
  const originalAllowProd = process.env.ALLOW_PRODUCTION_MIGRATIONS;

  try {
    // Test 1: Strict Production Guard blocks freshtrack_db by default
    process.env.DB_NAME = "freshtrack_db";
    process.env.ALLOW_PRODUCTION_MIGRATIONS = "false";

    await assert.rejects(
      async () => {
        await runMigrations({ closePool: false });
      },
      (err) => {
        assert(
          err.message.includes("SAFETY GUARD: Migrations against 'freshtrack_db' are denied by default"),
          `Expected safety guard error, got: ${err.message}`
        );
        return true;
      },
      "Must reject migrations targeting freshtrack_db when ALLOW_PRODUCTION_MIGRATIONS is false"
    );
    console.log("✓ Test 1 Passed: Safety guard strictly blocks freshtrack_db before any database query");

    // Restore to test database
    process.env.DB_NAME = "freshtrack_test_db";
    process.env.ALLOW_PRODUCTION_MIGRATIONS = "false";

    // Test 2: Run migrations against freshtrack_test_db
    const appliedFirst = await runMigrations({ closePool: false });
    console.log(`✓ Test 2 Passed: Migrations executed against freshtrack_test_db (${appliedFirst.length} new applied)`);

    // Test 3: Idempotency check: Running again applies 0 new migrations
    const appliedSecond = await runMigrations({ closePool: false });
    assert.strictEqual(
      appliedSecond.length,
      0,
      "Second migration run should apply 0 migrations (fully idempotent)"
    );
    console.log("✓ Test 3 Passed: Re-running migrations is completely idempotent (0 applied)");

    // Test 4: Verify all required tables exist in freshtrack_test_db
    const { rows: tableRows } = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      ORDER BY table_name;
    `);
    const tables = tableRows.map((r) => r.table_name);
    const expectedTables = [
      "email_otp_challenges",
      "food_items",
      "notification_preferences",
      "notifications",
      "pending_registrations",
      "schema_migrations",
      "users",
    ];
    for (const expected of expectedTables) {
      assert(
        tables.includes(expected),
        `Table '${expected}' must exist in freshtrack_test_db, found: ${tables.join(", ")}`
      );
    }
    console.log("✓ Test 4 Passed: All 7 required tables verified in freshtrack_test_db");

    // Test 5: Verify schema_migrations versions
    const { rows: migrationRows } = await pool.query(
      "SELECT version FROM schema_migrations ORDER BY version;"
    );
    const recordedVersions = migrationRows.map((r) => r.version);
    assert(recordedVersions.includes("001_initial_schema.sql"));
    assert(recordedVersions.includes("002_email_otp_auth.sql"));
    assert(recordedVersions.includes("003_phase3_notifications.sql"));
    console.log("✓ Test 5 Passed: schema_migrations accurately records numbered migrations");

    console.log("\nALL DATABASE MIGRATION TESTS PASSED SUCCESSFULLY.\n");
  } finally {
    process.env.DB_NAME = originalDbName;
    process.env.ALLOW_PRODUCTION_MIGRATIONS = originalAllowProd;
    await pool.end();
  }
}

runTests().catch((err) => {
  console.error("Migration test failed:", err);
  process.exit(1);
});
