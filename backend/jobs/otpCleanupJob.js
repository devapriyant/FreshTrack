const pool = require("../config/database");

/**
 * Safely prunes expired/consumed OTP challenges and abandoned pending registrations.
 *
 * @param {object} [client=pool]
 * @returns {Promise<{ deletedChallenges: number, deletedRegistrations: number }>}
 */
async function cleanExpiredOtpAndRegistrations(client = pool) {
  let deletedChallenges = 0;
  let deletedRegistrations = 0;

  try {
    // 1. Delete consumed or expired challenges older than 7 days
    const challengeRes = await client.query(`
      DELETE FROM email_otp_challenges
      WHERE (consumed_at IS NOT NULL OR expires_at < NOW())
        AND created_at < NOW() - INTERVAL '7 days'
      RETURNING id
    `);
    deletedChallenges = challengeRes.rowCount;

    // 2. Delete abandoned pending registrations older than 24 hours with no active unexpired challenge
    const pendingRes = await client.query(`
      DELETE FROM pending_registrations pr
      WHERE pr.created_at < NOW() - INTERVAL '24 hours'
        AND NOT EXISTS (
          SELECT 1 FROM email_otp_challenges eoc
          WHERE eoc.pending_registration_id = pr.id
            AND eoc.consumed_at IS NULL
            AND eoc.expires_at > NOW()
        )
      RETURNING id
    `);
    deletedRegistrations = pendingRes.rowCount;

    if (deletedChallenges > 0 || deletedRegistrations > 0) {
      console.log(
        `[Cleanup] Pruned ${deletedChallenges} old OTP challenge(s) and ${deletedRegistrations} abandoned registration(s).`
      );
    }
  } catch (err) {
    console.error("Cleanup job error:", err.message);
  }

  return { deletedChallenges, deletedRegistrations };
}

module.exports = {
  cleanExpiredOtpAndRegistrations,
};
