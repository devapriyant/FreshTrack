require("dotenv").config();
const fs = require("fs");
const path = require("path");
const pool = require("../config/database");

/**
 * Executes migration files in backend/sql/migrations/ in ascending numerical order.
 * Strictly guards against unapproved migrations on 'freshtrack_db'.
 */
async function runMigrations({ closePool = true } = {}) {
  // STRICT PRODUCTION MIGRATION GUARD
  // Must execute before any database-connecting or mutating operations
  if (
    process.env.DB_NAME === "freshtrack_db" &&
    process.env.ALLOW_PRODUCTION_MIGRATIONS !== "true"
  ) {
    throw new Error(
      "SAFETY GUARD: Migrations against 'freshtrack_db' are denied by default. Set ALLOW_PRODUCTION_MIGRATIONS=true to authorize."
    );
  }

  const migrationsDir = path.join(__dirname, "migrations");
  if (!fs.existsSync(migrationsDir)) {
    throw new Error(`Migrations directory not found: ${migrationsDir}`);
  }

  // Find all SQL files conforming to the numbered convention: e.g. 001_initial_schema.sql
  const files = fs
    .readdirSync(migrationsDir)
    .filter((f) => /^\d+_.+\.sql$/.test(f))
    .sort((a, b) => {
      const numA = parseInt(a.split("_")[0], 10);
      const numB = parseInt(b.split("_")[0], 10);
      return numA - numB;
    });

  const client = await pool.connect();
  try {
    // Ensure tracking table exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(255) PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Fetch applied migrations
    const { rows } = await client.query(
      "SELECT version FROM schema_migrations;"
    );
    const appliedSet = new Set(rows.map((r) => r.version));

    const appliedThisRun = [];

    for (const file of files) {
      if (appliedSet.has(file)) {
        continue;
      }

      console.log(`Applying migration: ${file}`);
      const filePath = path.join(migrationsDir, file);
      const sqlContent = fs.readFileSync(filePath, "utf-8");

      await client.query("BEGIN");
      try {
        await client.query(sqlContent);
        await client.query(
          "INSERT INTO schema_migrations (version) VALUES ($1);",
          [file]
        );
        await client.query("COMMIT");
        appliedThisRun.push(file);
        console.log(`Successfully applied: ${file}`);
      } catch (migrationErr) {
        await client.query("ROLLBACK");
        console.error(`Failed to apply migration ${file}:`, migrationErr.message);
        throw migrationErr;
      }
    }

    return appliedThisRun;
  } finally {
    client.release();
    if (closePool) {
      await pool.end();
    }
  }
}

if (require.main === module) {
  runMigrations({ closePool: true })
    .then((applied) => {
      console.log(
        `Migrations complete. ${applied.length} new migrations applied.`
      );
      process.exit(0);
    })
    .catch((err) => {
      console.error("Migration runner failed:", err.message);
      process.exit(1);
    });
}

module.exports = { runMigrations };
