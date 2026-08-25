-- =============================================================================
-- 0071_player_badges.sql
-- Minimal, generic durable-badge table for permanent cosmetic/prestige
-- rewards that are not credits and not a superpower grant (superpower_grants
-- is expiry-driven; badges are permanent and one-per-player-per-key).
--
-- First consumer: the day-21 full-streak "21_day_marathon" capstone reward
-- granted from record_daily_login.
-- =============================================================================

CREATE TABLE IF NOT EXISTS player_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_key TEXT NOT NULL,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, badge_key)
);

CREATE INDEX IF NOT EXISTS idx_player_badges_user_id ON player_badges(user_id);

ALTER TABLE player_badges ENABLE ROW LEVEL SECURITY;

-- Players may read only their own badges. All writes go through the
-- service-role edge function (record_daily_login), never client-side.
DROP POLICY IF EXISTS player_badges_select_own ON player_badges;
CREATE POLICY player_badges_select_own ON player_badges
  FOR SELECT
  USING (auth.uid() = user_id);
