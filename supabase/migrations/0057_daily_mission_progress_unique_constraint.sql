-- Migration 0057: Restore the unique constraint on daily_mission_progress that was
-- lost during the player_id -> user_id unification (0050). That migration dropped the
-- legacy player_id column, which had carried UNIQUE(player_id, mission_id, date), and
-- never recreated an equivalent constraint on user_id. Without it, upserts that target
-- ON CONFLICT (user_id, mission_id, date) fail with Postgres error 42P10 (no unique or
-- exclusion constraint matching the ON CONFLICT specification).

BEGIN;

-- Pre-flight guard: abort if any duplicate (user_id, mission_id, date) groups exist.
-- If this fires, resolve duplicates (keep the row with the latest updated_at, delete
-- the rest) before re-running this migration.
DO $$
DECLARE
  dup_count INT;
BEGIN
  SELECT count(*) INTO dup_count FROM (
    SELECT user_id, mission_id, date
      FROM daily_mission_progress
     GROUP BY user_id, mission_id, date
    HAVING count(*) > 1
  ) d;

  IF dup_count > 0 THEN
    RAISE EXCEPTION 'Migration aborted: % duplicate (user_id, mission_id, date) groups found in daily_mission_progress. Resolve before re-running.', dup_count;
  END IF;
END $$;

ALTER TABLE daily_mission_progress
  ADD CONSTRAINT daily_mission_progress_user_mission_date_key
  UNIQUE (user_id, mission_id, date);

COMMIT;
