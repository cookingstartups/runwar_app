-- Migration 0035: player_economy child table
-- Splits economy columns out of players into a dedicated 1:1 child table.
-- Backfills from players, enables RLS with select-own policy only (no write policies).

CREATE TABLE IF NOT EXISTS player_economy (
  player_id             uuid        PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  credits               bigint      NOT NULL DEFAULT 0,
  total_kickback_earned bigint      NOT NULL DEFAULT 0,
  subscription_tier     text        NOT NULL DEFAULT 'free'
    CHECK (subscription_tier IN ('free', 'trial_extended', 'pro')),
  subscription_expires  timestamptz,
  reputation            integer     NOT NULL DEFAULT 100,
  updated_at            timestamptz NOT NULL DEFAULT now()
);

-- Backfill: one row per existing player, idempotent via ON CONFLICT DO NOTHING
DO $$
DECLARE
  expected_count INT;
  actual_count   INT;
BEGIN
  INSERT INTO player_economy
    (player_id, credits, total_kickback_earned, subscription_tier,
     subscription_expires, reputation)
  SELECT
    id,
    COALESCE(credits, 0),
    COALESCE(total_kickback_earned, 0),
    COALESCE(subscription_tier, 'free'),
    subscription_expires,
    COALESCE(reputation, 100)
  FROM players
  ON CONFLICT (player_id) DO NOTHING;

  SELECT COUNT(*) INTO expected_count FROM players;
  SELECT COUNT(*) INTO actual_count   FROM player_economy;

  IF actual_count <> expected_count THEN
    RAISE EXCEPTION
      'player_economy backfill mismatch: expected %, got %',
      expected_count, actual_count;
  END IF;
END $$;

-- RLS: enable and restrict reads to own row only; no write policies (service_role bypasses RLS)
ALTER TABLE player_economy ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS player_economy_select_own ON player_economy;
CREATE POLICY player_economy_select_own ON player_economy
  FOR SELECT
  USING (player_id = auth.uid());
