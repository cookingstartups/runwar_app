-- 0075_anticheat_flags_schema_capture.sql
--
-- Idempotent capture of the anticheat_flags table shape. The table itself
-- predates this repo's visible migration history (0050_player_id_to_
-- user_id_unification.sql only ever RENAMEs its player_id column to
-- user_id - it never CREATEs the table), but id/user_id/run_id/flag_type/
-- details/created_at are all real, live columns written today by
-- supabase/functions/anticheat_score/index.ts (flagRows insert, ~lines
-- 119-126). This migration documents the existing live shape only, the
-- same "capture a db-only table" pattern already used by
-- 0062_db_only_table_schema_capture.sql for referrals/challenges/
-- invitation_codes/drops/passive_income_runs. It changes nothing on a
-- database where the table already exists (CREATE TABLE IF NOT EXISTS is a
-- no-op there); it only matters for a fresh database that has never run the
-- out-of-band creation that produced the live table.

CREATE TABLE IF NOT EXISTS public.anticheat_flags (
  id         uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  run_id     text        NULL,
  flag_type  text        NOT NULL,
  details    jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_anticheat_flags_user_id
  ON public.anticheat_flags (user_id);

ALTER TABLE public.anticheat_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS anticheat_flags_admin_only ON public.anticheat_flags;
CREATE POLICY anticheat_flags_admin_only ON public.anticheat_flags
  FOR SELECT
  USING (false);
