-- Migration 0037: player_streaks child table
-- Splits streak columns out of players.
-- Canonical streak column is players.streak (NOT current_streak, which is a redundant alias).
-- current_streak does NOT appear as a column on this table.

CREATE TABLE IF NOT EXISTS player_streaks (
  player_id          uuid        PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  streak             integer     NOT NULL DEFAULT 0,
  longest_streak     integer     NOT NULL DEFAULT 0,
  last_login_at      timestamptz,
  streak_started_at  timestamptz,
  milestones_claimed integer[]   NOT NULL DEFAULT '{}',
  freeze_tokens      integer     NOT NULL DEFAULT 2,
  freeze_refreshed_at timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- Backfill: one row per existing player.
-- Reads players.streak as canonical (players.current_streak is the redundant alias - skip it).
DO $$
DECLARE
  expected_count INT;
  actual_count   INT;
  has_streak     BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'players' AND column_name = 'streak'
  ) INTO has_streak;

  IF has_streak THEN
    INSERT INTO player_streaks
      (player_id, streak, longest_streak, last_login_at, streak_started_at,
       milestones_claimed, freeze_tokens, freeze_refreshed_at)
    SELECT
      id,
      COALESCE(streak, 0),
      COALESCE(longest_streak, 0),
      last_login_at,
      streak_started_at,
      COALESCE(milestones_claimed, '{}'),
      COALESCE(freeze_tokens, 2),
      COALESCE(freeze_refreshed_at, now())
    FROM players
    ON CONFLICT (player_id) DO NOTHING;
  ELSE
    INSERT INTO player_streaks (player_id)
    SELECT id FROM players
    ON CONFLICT (player_id) DO NOTHING;
  END IF;

  SELECT COUNT(*) INTO expected_count FROM players;
  SELECT COUNT(*) INTO actual_count   FROM player_streaks;

  IF actual_count <> expected_count THEN
    RAISE EXCEPTION
      'player_streaks backfill mismatch: expected %, got %',
      expected_count, actual_count;
  END IF;
END $$;

-- RLS: enable and restrict reads to own row only; no write policies (service_role bypasses RLS)
ALTER TABLE player_streaks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS player_streaks_select_own ON player_streaks;
CREATE POLICY player_streaks_select_own ON player_streaks
  FOR SELECT
  USING (player_id = auth.uid());
