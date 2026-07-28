-- 0064_run_summary_schema_capture.sql
--
-- Schema-capture only: the run distance, end time, and finalize time columns
-- are already written by stopRun()/cancelRun() and read by finalize_run on
-- the live database today, but no migration file anywhere in this repo
-- defines them (runs was created by 0029_runwar_full_schema.sql with only
-- started_at/closed_at). This migration documents the existing live shape;
-- it does not change any behavior, claim-gate threshold, or RLS policy, and
-- does not alter any existing row's data. Idempotent (IF NOT EXISTS), same
-- pattern as 0062_db_only_table_schema_capture.sql.

ALTER TABLE runs
  ADD COLUMN IF NOT EXISTS distance_m   NUMERIC,
  ADD COLUMN IF NOT EXISTS ended_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS finalized_at TIMESTAMPTZ;
