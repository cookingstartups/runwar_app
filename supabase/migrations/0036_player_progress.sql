-- Migration 0036: player_progress child table
-- Splits progress columns out of players. influence_total is renamed to score.
-- Backfills score from players.influence_total (or players.score if already renamed by 0031).

CREATE TABLE IF NOT EXISTS player_progress (
  player_id                  uuid        PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  score                      integer     NOT NULL DEFAULT 0,
  first_mission_completed_at timestamptz,
  first_attack_completed_at  timestamptz,
  updated_at                 timestamptz NOT NULL DEFAULT now()
);

-- Backfill: coalesce influence_total and score (0031 renamed influence_level to score on players).
-- Use COALESCE(score, influence_total, 0) to handle both schema states idempotently.
DO $$
DECLARE
  expected_count INT;
  actual_count   INT;
  has_score      BOOLEAN;
  has_influence  BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'players' AND column_name = 'score'
  ) INTO has_score;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'players' AND column_name = 'influence_total'
  ) INTO has_influence;

  IF has_score THEN
    INSERT INTO player_progress
      (player_id, score, first_mission_completed_at, first_attack_completed_at)
    SELECT
      id,
      COALESCE(score, 0),
      first_mission_completed_at,
      first_attack_completed_at
    FROM players
    ON CONFLICT (player_id) DO NOTHING;
  ELSIF has_influence THEN
    INSERT INTO player_progress
      (player_id, score, first_mission_completed_at, first_attack_completed_at)
    SELECT
      id,
      COALESCE(influence_total, 0),
      first_mission_completed_at,
      first_attack_completed_at
    FROM players
    ON CONFLICT (player_id) DO NOTHING;
  ELSE
    INSERT INTO player_progress (player_id)
    SELECT id FROM players
    ON CONFLICT (player_id) DO NOTHING;
  END IF;

  SELECT COUNT(*) INTO expected_count FROM players;
  SELECT COUNT(*) INTO actual_count   FROM player_progress;

  IF actual_count <> expected_count THEN
    RAISE EXCEPTION
      'player_progress backfill mismatch: expected %, got %',
      expected_count, actual_count;
  END IF;
END $$;

-- RLS: enable and restrict reads to own row only; no write policies (service_role bypasses RLS)
ALTER TABLE player_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS player_progress_select_own ON player_progress;
CREATE POLICY player_progress_select_own ON player_progress
  FOR SELECT
  USING (player_id = auth.uid());
