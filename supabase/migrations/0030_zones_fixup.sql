-- =============================================================================
-- 0030_zones_fixup.sql
-- zones and runs already existed on remote with different/fewer columns.
-- Add all missing gameplay columns then create indexes.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- zones: add missing columns
-- ---------------------------------------------------------------------------
ALTER TABLE zones
  ADD COLUMN IF NOT EXISTS owner_id        UUID        REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS city            TEXT        NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS geom_json       TEXT        NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS influence       REAL        NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS status          TEXT        NOT NULL DEFAULT 'owned',
  ADD COLUMN IF NOT EXISTS contested_by_id UUID        REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS credits_earned  REAL        NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_income_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_active_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS dispute_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS parent_id       TEXT;

DO $$
BEGIN
  ALTER TABLE zones ADD CONSTRAINT zones_status_check
    CHECK (status IN ('owned', 'disputed'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_zones_city_status ON zones(city, status);
CREATE INDEX IF NOT EXISTS idx_zones_owner       ON zones(owner_id);

-- ---------------------------------------------------------------------------
-- runs: add missing columns
-- ---------------------------------------------------------------------------
ALTER TABLE runs
  ADD COLUMN IF NOT EXISTS user_id    UUID        REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS city       TEXT        NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS track_json TEXT        NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS zone_id    TEXT;

CREATE INDEX IF NOT EXISTS idx_runs_user ON runs(user_id);

-- ---------------------------------------------------------------------------
-- events: add missing columns if pre-existing
-- ---------------------------------------------------------------------------
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS user_id    UUID        REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS name       TEXT        NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS props_json TEXT;

CREATE INDEX IF NOT EXISTS idx_events_user_name ON events(user_id, name);

-- ---------------------------------------------------------------------------
-- daily_mission_progress: add missing columns if pre-existing
-- ---------------------------------------------------------------------------
ALTER TABLE daily_mission_progress
  ADD COLUMN IF NOT EXISTS user_id      UUID        REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS date         DATE,
  ADD COLUMN IF NOT EXISTS slug         TEXT        NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS progress     INTEGER     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS target       INTEGER     NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS synced_at    TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_dmp_user_date ON daily_mission_progress(user_id, date);

-- ---------------------------------------------------------------------------
-- RLS policies (moved here from 0029 so columns exist before referencing them)
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS zones_owner_all ON zones;
DROP POLICY IF EXISTS zones_city_read ON zones;
CREATE POLICY zones_owner_all ON zones
  FOR ALL
  USING  (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);
CREATE POLICY zones_city_read ON zones
  FOR SELECT
  USING (
    auth.role() = 'authenticated'
    AND city IN (SELECT p.city FROM players p WHERE p.id = auth.uid())
  );

DROP POLICY IF EXISTS runs_own_all ON runs;
CREATE POLICY runs_own_all ON runs
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS prefs_own_all ON prefs;
CREATE POLICY prefs_own_all ON prefs
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS events_insert_auth ON events;
CREATE POLICY events_insert_auth ON events
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS feedback_insert_auth ON feedback;
CREATE POLICY feedback_insert_auth ON feedback
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS dmp_own_all ON daily_mission_progress;
CREATE POLICY dmp_own_all ON daily_mission_progress
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS city_waitlists_own_all ON city_waitlists;
CREATE POLICY city_waitlists_own_all ON city_waitlists
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
