-- 0049_gps_realtime_streaming.sql
-- Adds session-stub support to runs; creates gps_samples with dedup index.
--
-- runs: add status, session_id, lasso_id; relax NOT NULL on track_json/closed_at
ALTER TABLE runs
  ADD COLUMN IF NOT EXISTS status     TEXT NOT NULL DEFAULT 'active'
                                       CHECK (status IN ('active', 'completed', 'cancelled')),
  ADD COLUMN IF NOT EXISTS session_id UUID,
  ADD COLUMN IF NOT EXISTS lasso_id   UUID;

ALTER TABLE runs ALTER COLUMN track_json DROP NOT NULL;
ALTER TABLE runs ALTER COLUMN closed_at  DROP NOT NULL;

-- gps_samples: NEW table
CREATE TABLE IF NOT EXISTS gps_samples (
  id         BIGSERIAL PRIMARY KEY,
  session_id UUID,
  player_id  UUID,
  lat        DOUBLE PRECISION NOT NULL,
  lng        DOUBLE PRECISION NOT NULL,
  ts         TIMESTAMPTZ NOT NULL,
  speed_ms   REAL,
  is_mocked  BOOLEAN NOT NULL DEFAULT false
);

-- Dedup index: crash-replay via upsert is idempotent on this composite key.
-- Column order must match the onConflict string used in OutboxDrainer and
-- OutboxAwareWriter: 'session_id,ts,player_id'.
CREATE UNIQUE INDEX IF NOT EXISTS gps_samples_dedup
  ON gps_samples (session_id, ts, player_id);

CREATE INDEX IF NOT EXISTS idx_gps_samples_player_ts
  ON gps_samples (player_id, ts);

-- RLS: append-only for authenticated players; full access for service role.
ALTER TABLE gps_samples ENABLE ROW LEVEL SECURITY;

CREATE POLICY "players insert own samples" ON gps_samples
  FOR INSERT WITH CHECK (player_id = auth.uid());

CREATE POLICY "players select own samples" ON gps_samples
  FOR SELECT USING (player_id = auth.uid());

CREATE POLICY "service role full access" ON gps_samples
  USING (auth.role() = 'service_role');

-- runs INSERT RLS: the existing runs_own_all policy (0030_zones_fixup.sql)
-- is FOR ALL USING/WITH CHECK (auth.uid() = user_id), which already covers
-- INSERT for the status='active' stub row written by startRun. No additional
-- policy is added here.
