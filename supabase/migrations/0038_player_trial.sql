-- Migration 0038: player_trial child table
-- Splits trial lifecycle columns out of players into a dedicated 1:1 child table.

CREATE TABLE IF NOT EXISTS player_trial (
  player_id             uuid        PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  trial_started_at      timestamptz,
  trial_days_remaining  integer     NOT NULL DEFAULT 14,
  trial_last_tick_date  date,
  updated_at            timestamptz NOT NULL DEFAULT now()
);

-- Backfill: one row per existing player, reading trial columns from players.
DO $$
DECLARE
  expected_count INT;
  actual_count   INT;
BEGIN
  INSERT INTO player_trial
    (player_id, trial_started_at, trial_days_remaining, trial_last_tick_date)
  SELECT
    id,
    trial_started_at,
    COALESCE(trial_days_remaining, 14),
    trial_last_tick_date
  FROM players
  ON CONFLICT (player_id) DO NOTHING;

  SELECT COUNT(*) INTO expected_count FROM players;
  SELECT COUNT(*) INTO actual_count   FROM player_trial;

  IF actual_count <> expected_count THEN
    RAISE EXCEPTION
      'player_trial backfill mismatch: expected %, got %',
      expected_count, actual_count;
  END IF;
END $$;

-- RLS: enable and restrict reads to own row only; no write policies (service_role bypasses RLS)
ALTER TABLE player_trial ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS player_trial_select_own ON player_trial;
CREATE POLICY player_trial_select_own ON player_trial
  FOR SELECT
  USING (player_id = auth.uid());
