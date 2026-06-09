-- Migration 0042: players_and_bots view rewrite
-- Sources score from player_progress via LEFT JOIN instead of a literal 0 constant.
-- COALESCE ensures players with no player_progress row still appear with score = 0.
-- Depends on: 0036 (player_progress table must exist).
-- Column set (id, username, color, score, is_bot) is identical to the pre-0042 set.

CREATE OR REPLACE VIEW players_and_bots AS
  SELECT
    p.id,
    p.username::text              AS username,
    p.color,
    COALESCE(pp.score, 0)::integer AS score,
    false                         AS is_bot
  FROM players p
  LEFT JOIN player_progress pp ON pp.player_id = p.id
UNION ALL
  SELECT
    id,
    username,
    color,
    score,
    true AS is_bot
  FROM bots
  WHERE is_active = true;
