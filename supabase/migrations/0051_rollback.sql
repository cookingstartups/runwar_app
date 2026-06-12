-- ROLLBACK NOTE: Rolling back 0051 to the 0050 apply_credit_delta body is UNSAFE
-- because 0050's body targets players.credits (dropped in 0044_players_cleanup.sql).
-- To roll back: write a new CREATE OR REPLACE FUNCTION targeting player_economy.credits
-- with the desired corrected logic instead of restoring the 0050 body.
SELECT 1; -- no-op
