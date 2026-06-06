-- 0032_bots_table.sql
-- NPC/demo bot players — no FK to auth.users; managed server-side only.

CREATE TABLE IF NOT EXISTS bots (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  username   TEXT        NOT NULL,
  city       TEXT        NOT NULL,
  color      TEXT        NOT NULL DEFAULT '#888888',
  score      INTEGER     NOT NULL DEFAULT 1,
  is_active  BOOLEAN     NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for city-scoped leaderboard / map queries
CREATE INDEX IF NOT EXISTS idx_bots_city ON bots(city);

-- RLS: authenticated users may read; writes restricted to service role only
ALTER TABLE bots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bots_select_authenticated"
  ON bots FOR SELECT
  TO authenticated
  USING (true);

-- No INSERT/UPDATE/DELETE policy for regular users — service role bypasses RLS.

-- View: union of real players and active bots, used by map and leaderboard queries.
-- players.score is not yet a column (score lives in zones); use 0 as placeholder.
CREATE OR REPLACE VIEW players_and_bots AS
  SELECT id, username, city, color, 0 AS score, false AS is_bot FROM players
  UNION ALL
  SELECT id, username, city, color, score, true AS is_bot FROM bots WHERE is_active = true;

-- Seed: 5 fixed Valencia bots (idempotent via ON CONFLICT DO NOTHING)
INSERT INTO bots (id, username, city, color, score, is_active)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'RUNNER-LUCA', 'Valencia', '#FF6B35', 7,  true),
  ('00000000-0000-0000-0000-000000000002', 'RUNNER-MARC', 'Valencia', '#00A8CC', 5,  true),
  ('00000000-0000-0000-0000-000000000003', 'RUNNER-SARA', 'Valencia', '#5CB85C', 9,  true),
  ('00000000-0000-0000-0000-000000000004', 'RUNNER-DANI', 'Valencia', '#9B59B6', 3,  true),
  ('00000000-0000-0000-0000-000000000005', 'RUNNER-ALEX', 'Valencia', '#E74C3C', 11, true)
ON CONFLICT (id) DO NOTHING;

-- Cleanup: remove any old bot-placeholder rows that were previously seeded in players
DELETE FROM players WHERE id IN (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002'
);
