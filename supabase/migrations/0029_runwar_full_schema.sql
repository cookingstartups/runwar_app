-- =============================================================================
-- 0029_runwar_full_schema.sql
-- RunWar full remote schema: extends players, creates zones/runs/prefs/events/
-- feedback/daily_mission_progress, enables RLS on all new tables.
-- Idempotent: uses IF NOT EXISTS / IF NOT EXISTS guards throughout.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Extend players with missing profile columns
-- ---------------------------------------------------------------------------
ALTER TABLE players
  ADD COLUMN IF NOT EXISTS username              TEXT        NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS city                  TEXT        NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS color                 TEXT        NOT NULL DEFAULT '#FF7A00',
  ADD COLUMN IF NOT EXISTS invited_at            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_tester             INTEGER     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS phone                 TEXT,
  ADD COLUMN IF NOT EXISTS created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS trial_started_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS trial_days_remaining  INTEGER     NOT NULL DEFAULT 14,
  ADD COLUMN IF NOT EXISTS trial_last_tick_date  DATE,
  ADD COLUMN IF NOT EXISTS streak_started_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS first_mission_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS first_attack_completed_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_bot                INTEGER     NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 2. zones
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zones (
  id               TEXT        PRIMARY KEY,
  owner_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  city             TEXT        NOT NULL,
  geom_json        TEXT        NOT NULL,
  influence        REAL        NOT NULL DEFAULT 1,
  status           TEXT        NOT NULL DEFAULT 'owned'
                               CHECK (status IN ('owned', 'disputed')),
  contested_by_id  UUID        REFERENCES auth.users(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  credits_earned   REAL        NOT NULL DEFAULT 0,
  last_income_at   TIMESTAMPTZ,
  last_active_at   TIMESTAMPTZ,
  dispute_at       TIMESTAMPTZ,
  parent_id        TEXT        REFERENCES zones(id)
);

-- Indexes for zones are in 0030_zones_fixup.sql (applied after ALTER TABLE
-- adds the status column to the pre-existing remote zones table).

-- ---------------------------------------------------------------------------
-- 3. runs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS runs (
  id         TEXT        PRIMARY KEY,
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  city       TEXT        NOT NULL,
  track_json TEXT        NOT NULL,
  started_at TIMESTAMPTZ NOT NULL,
  closed_at  TIMESTAMPTZ NOT NULL,
  zone_id    TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for runs is in 0030_zones_fixup.sql after ALTER TABLE adds user_id.

-- ---------------------------------------------------------------------------
-- 4. prefs  (per-user key-value; device-global SQLite prefs are scoped here)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS prefs (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key     TEXT NOT NULL,
  value   TEXT NOT NULL,
  PRIMARY KEY (user_id, key)
);

-- ---------------------------------------------------------------------------
-- 5. events  (telemetry; service role reads, authenticated users insert only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS events (
  id         TEXT        PRIMARY KEY,
  user_id    UUID        REFERENCES auth.users(id),
  name       TEXT        NOT NULL,
  props_json TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index in 0030_zones_fixup.sql after ALTER TABLE guards.

-- ---------------------------------------------------------------------------
-- 6. feedback  (insert-only for authenticated users)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feedback (
  id         TEXT        PRIMARY KEY,
  user_id    UUID        REFERENCES auth.users(id),
  trigger    TEXT        NOT NULL,
  rating     TEXT        NOT NULL,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 7. daily_mission_progress
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_mission_progress (
  id           TEXT        PRIMARY KEY,
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date         DATE        NOT NULL,
  slug         TEXT        NOT NULL,
  progress     INTEGER     NOT NULL DEFAULT 0,
  target       INTEGER     NOT NULL DEFAULT 1,
  completed_at TIMESTAMPTZ,
  synced_at    TIMESTAMPTZ,
  UNIQUE (user_id, date, slug)
);

-- Index in 0030_zones_fixup.sql after ALTER TABLE guards.

-- ---------------------------------------------------------------------------
-- 8. Enable RLS on all new tables + city_waitlists
-- ---------------------------------------------------------------------------

ALTER TABLE zones                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE runs                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE prefs                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE events                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback               ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_mission_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE city_waitlists         ENABLE ROW LEVEL SECURITY;

-- RLS policies moved to 0030_zones_fixup.sql (applied after ALTER TABLE
-- adds the columns they reference to pre-existing remote tables).
