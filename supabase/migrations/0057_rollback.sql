-- Rollback for 0057_daily_mission_progress_unique_constraint.sql

BEGIN;

ALTER TABLE daily_mission_progress
  DROP CONSTRAINT IF EXISTS daily_mission_progress_user_mission_date_key;

COMMIT;
