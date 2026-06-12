-- apply_credit_delta: retarget to player_economy.credits
-- The 0050 body targeted players.credits which was dropped in 0044_players_cleanup.sql.
-- This migration replaces the function body to target player_economy instead.

CREATE OR REPLACE FUNCTION apply_credit_delta(
  p_user_id             UUID,
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
   WHERE user_id = p_user_id
  RETURNING credits INTO new_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'apply_credit_delta: no player_economy row for user %', p_user_id;
  END IF;

  IF new_balance < 0 AND p_reason <> 'admin_clawback' THEN
    RAISE EXCEPTION 'apply_credit_delta: insufficient balance (would be %)', new_balance;
  END IF;

  INSERT INTO credit_transactions
    (user_id, delta, reason, related_entity_id, related_entity_type, metadata)
  VALUES
    (p_user_id, p_delta, p_reason, p_related_entity_id, p_related_entity_type, p_metadata);

  RETURN new_balance;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

REVOKE ALL    ON FUNCTION apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) TO service_role;
