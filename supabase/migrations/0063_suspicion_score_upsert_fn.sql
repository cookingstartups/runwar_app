-- =============================================================================
-- 0063_suspicion_score_upsert_fn.sql
-- Anti-cheat pipeline, pass 1: atomic UPSERT support for suspicion_scores.
--
-- suspicion_scores is keyed on user_id with no separate id column (confirmed
-- live). The scoring edge function needs to upsert this table with
-- conditional/incremental semantics a plain PostgREST upsert cannot express:
-- score must become the greatest of the existing value and this batch's
-- session_max_score (a lifetime running max that never decreases), and
-- flags_count must accumulate across batches rather than being overwritten.
-- A single atomic SQL statement is the correct fix here rather than a
-- read-then-write in the edge function, which would introduce a lost-update
-- race under concurrent batches for the same user (two devices, or a
-- retried flush). This follows the same established codebase convention as
-- apply_credit_delta (0040_apply_credit_delta_rewrite.sql) and decline_offer
-- (0050_player_id_to_user_id_unification.sql) - an atomic write wrapped in a
-- small SQL function invoked through .rpc(), not a new pattern.
--
-- ON CONFLICT (user_id) requires a unique constraint on that column. The
-- constraint is added defensively and idempotently below (caught exception
-- if it already exists) rather than assumed, since the live schema query
-- that confirmed this table's columns did not itself confirm a constraint.
-- =============================================================================

DO $$ BEGIN
  ALTER TABLE public.suspicion_scores
    ADD CONSTRAINT suspicion_scores_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION upsert_suspicion_score(
  p_user_id           uuid,
  p_session_max_score double precision,
  p_run_id            uuid,
  p_flags_this_batch  integer
) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO public.suspicion_scores
    (user_id, score, flags_count, last_flag_at, updated_at,
     session_max_score, last_session_id)
  VALUES (
    p_user_id,
    p_session_max_score,
    p_flags_this_batch,
    CASE WHEN p_flags_this_batch > 0 THEN now() ELSE NULL END,
    now(),
    p_session_max_score,
    p_run_id
  )
  ON CONFLICT (user_id) DO UPDATE SET
    score             = GREATEST(suspicion_scores.score, EXCLUDED.session_max_score),
    flags_count       = suspicion_scores.flags_count + EXCLUDED.flags_count,
    last_flag_at      = COALESCE(EXCLUDED.last_flag_at, suspicion_scores.last_flag_at),
    updated_at        = now(),
    session_max_score = EXCLUDED.session_max_score,
    last_session_id   = EXCLUDED.last_session_id;
$$;

-- Called only by the edge function's service-role client - no player ever
-- calls this directly, so no auth.uid() gate is needed inside the body
-- (unlike decline_offer, which is client-invoked).
GRANT EXECUTE ON FUNCTION upsert_suspicion_score(uuid, double precision, uuid, integer)
  TO service_role;
