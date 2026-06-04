ALTER TABLE players
  ADD COLUMN IF NOT EXISTS last_login_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS current_streak        INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS longest_streak        INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS freeze_tokens         INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS freeze_refreshed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS milestones_claimed    INTEGER[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS subscription_tier     TEXT NOT NULL DEFAULT 'free'
    CHECK (subscription_tier IN ('free', 'trial_extended', 'pro')),
  ADD COLUMN IF NOT EXISTS subscription_expires  TIMESTAMPTZ;
