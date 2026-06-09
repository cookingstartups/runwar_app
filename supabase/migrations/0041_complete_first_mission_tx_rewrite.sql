-- Migration 0041: complete_first_mission_tx RPC rewrite
-- Redirects reads/writes from players to player_progress and player_streaks.
-- Depends on: 0036 (player_progress), 0037 (player_streaks), 0040 (apply_credit_delta).
--
-- Lock order (alphabetical, prevents deadlock against other RPCs):
--   1. player_progress FOR UPDATE
--   2. player_streaks  FOR UPDATE
--   3. player_economy  (acquired inside apply_credit_delta)
--
-- Idempotency: if first_mission_completed_at IS NOT NULL, returns existing values without
-- re-crediting. Calling this function twice has the same net effect as calling it once.

DROP FUNCTION IF EXISTS complete_first_mission_tx(UUID) CASCADE;

CREATE OR REPLACE FUNCTION complete_first_mission_tx(p_player_id UUID)
RETURNS TABLE(
  already_completed          BOOLEAN,
  first_mission_completed_at TIMESTAMPTZ,
  streak_started_at          TIMESTAMPTZ,
  credits_after              BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_progress   RECORD;
  v_streaks    RECORD;
  v_now        TIMESTAMPTZ := now();
  v_streak_at  TIMESTAMPTZ;
  v_credits    BIGINT;
BEGIN
  -- Lock player_progress first (alphabetical lock order).
  SELECT pp.first_mission_completed_at, pp.updated_at
    INTO v_progress
    FROM player_progress pp
   WHERE pp.player_id = p_player_id
     FOR UPDATE;

  -- Idempotency: already completed -- return without side effects.
  IF v_progress.first_mission_completed_at IS NOT NULL THEN
    SELECT ps.streak_started_at
      INTO v_streaks
      FROM player_streaks ps
     WHERE ps.player_id = p_player_id;

    RETURN QUERY SELECT
      true,
      v_progress.first_mission_completed_at,
      v_streaks.streak_started_at,
      NULL::BIGINT;
    RETURN;
  END IF;

  -- Lock player_streaks second (alphabetical lock order).
  SELECT ps.streak_started_at
    INTO v_streaks
    FROM player_streaks ps
   WHERE ps.player_id = p_player_id
     FOR UPDATE;

  v_streak_at := COALESCE(v_streaks.streak_started_at, v_now);

  -- Stamp first_mission_completed_at on player_progress.
  UPDATE player_progress
     SET first_mission_completed_at = v_now,
         updated_at                 = v_now
   WHERE player_id = p_player_id
     AND first_mission_completed_at IS NULL;

  -- Set streak_started_at on player_streaks if not already set.
  UPDATE player_streaks
     SET streak_started_at = v_streak_at,
         updated_at        = v_now
   WHERE player_id = p_player_id
     AND streak_started_at IS NULL;

  -- Award 50 credits via apply_credit_delta (acquires player_economy lock -- third in chain).
  SELECT apply_credit_delta(
    p_player_id,
    50,
    'first_mission_reward',
    NULL,
    NULL,
    '{}'::jsonb
  ) INTO v_credits;

  -- Best-effort daily login tick (may not exist in older deploys).
  BEGIN
    PERFORM record_daily_login(p_player_id);
  EXCEPTION WHEN undefined_function THEN
    NULL;
  END;

  RETURN QUERY SELECT
    false,
    v_now,
    v_streak_at,
    v_credits;
END;
$$;

REVOKE ALL    ON FUNCTION complete_first_mission_tx(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION complete_first_mission_tx(UUID) TO service_role;
