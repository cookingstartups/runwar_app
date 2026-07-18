-- RunWar - Migration 55
-- Mark runs produced by the on-device replay simulation so they are always
-- distinguishable from real gameplay.
--
-- The simulation replays a recorded session through the real recorder, which
-- means it writes to the same runs, gps_samples and zones tables as a real
-- run. That is deliberate: exercising the real write path is the point of an
-- end-to-end test. Simulated GPS rows are already forced to is_mocked = true,
-- but runs had no equivalent marker, so a replay was indistinguishable from a
-- genuine run at the run level.
--
-- Purely additive. NOT NULL with DEFAULT false means every existing row and
-- every normal gameplay write is unaffected without any code change.
-- ADD COLUMN IF NOT EXISTS is deliberate: the live schema is known to drift
-- from this migration history (see 0030_zones_fixup.sql and
-- 0053_apply_zone_merge_tx.sql), so this must be safe against the real shape.

ALTER TABLE public.runs
  ADD COLUMN IF NOT EXISTS is_simulated boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.runs.is_simulated IS
  'True when the run was produced by the replay simulation rather than by a player physically running. Exclude these rows from leaderboards, stats and territory analytics.';
