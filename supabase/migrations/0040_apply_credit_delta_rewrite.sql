-- Migration 0040: apply_credit_delta RPC rewrite
-- Redirects all credit reads and writes from players.credits to player_economy.credits.
-- Depends on: 0035 (player_economy table must exist and be backfilled).
-- The increment_credits shim in runwar_database/0017 calls PERFORM apply_credit_delta(...)
-- so this single rewrite automatically routes all callers through player_economy.
--
-- Lock-order contract for transactions that call this function:
--   player_progress -> player_streaks -> player_economy (alphabetical)
-- This is a strict superset of the prior contract (players -> superpower_grants -> ...).

DROP FUNCTION IF EXISTS apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) CASCADE;

CREATE OR REPLACE FUNCTION apply_credit_delta(
  p_player_id           UUID,
  p_delta               BIGINT,
  p_reason              TEXT,
  p_related_entity_id   UUID    DEFAULT NULL,
  p_related_entity_type TEXT    DEFAULT NULL,
  p_metadata            JSONB   DEFAULT '{}'::jsonb
) RETURNS BIGINT AS $$
DECLARE
  new_balance BIGINT;
BEGIN
  UPDATE player_economy
     SET credits    = credits + p_delta,
         updated_at = now()
   WHERE player_id = p_player_id
  RETURNING credits INTO new_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'apply_credit_delta: no player_economy row for player %', p_player_id;
  END IF;

  IF new_balance < 0 AND p_reason <> 'admin_clawback' THEN
    RAISE EXCEPTION
      'apply_credit_delta: insufficient balance (would be %)', new_balance;
  END IF;

  INSERT INTO credit_transactions
    (player_id, delta, reason, related_entity_id, related_entity_type, metadata)
  VALUES
    (p_player_id, p_delta, p_reason, p_related_entity_id, p_related_entity_type, p_metadata);

  RETURN new_balance;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

COMMENT ON FUNCTION apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) IS
  'Single chokepoint for all credit movement. Writes to player_economy.credits (post-0040). '
  'Lock-order contract: player_progress -> player_streaks -> player_economy (alphabetical). '
  'Raises exception if no player_economy row exists for the given player_id.';

REVOKE ALL    ON FUNCTION apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) TO service_role;
