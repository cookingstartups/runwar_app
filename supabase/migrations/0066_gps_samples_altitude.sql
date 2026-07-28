-- 0066_gps_samples_altitude.sql
--
-- No altitude data is captured anywhere today - the only altitude reference
-- in the codebase is a hardcoded simulation-fixture stub, never a real
-- device fix. This migration adds a nullable altitude column to gps_samples
-- so a future capture pass can start populating it from the real device
-- Position.altitude value. It does not touch any claim-gate threshold or RLS
-- policy, and does not alter any existing row's data. Idempotent
-- (IF NOT EXISTS).

ALTER TABLE gps_samples
  ADD COLUMN IF NOT EXISTS altitude DOUBLE PRECISION;
