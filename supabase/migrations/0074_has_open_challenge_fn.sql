-- =============================================================================
-- 0074_has_open_challenge_fn.sql
-- Anti-cheat pipeline, pass 2: preflight helper for claim_territory.
--
-- Doctrine (phase-4-trust-layer.md section 4.2.10) specifies this function
-- against a player_id column and an "open" status value; the live challenges
-- table (0062_db_only_table_schema_capture.sql) has no player_id column -
-- only user_id - and its default/unique-index status convention is
-- "pending" (idx_challenges_one_open_per_player is WHERE status = 'pending').
-- This function is written against the live schema, matching what this
-- task's own write path (anticheat_score/complete_challenge) actually
-- inserts, on the same precedent Pass 1 established for anticheat_score
-- against anticheat_flags. See rw_app-T0539 design.md for the full note.
-- =============================================================================

CREATE OR REPLACE FUNCTION has_open_challenge(p_player_id uuid)
RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT id FROM public.challenges
  WHERE user_id = p_player_id AND status = 'pending'
  ORDER BY issued_at DESC
  LIMIT 1;
$$;

-- Called only by claim_territory's service-role client - no player ever
-- calls this directly, so no auth.uid() gate is needed inside the body,
-- matching the upsert_suspicion_score precedent (0063).
REVOKE ALL    ON FUNCTION has_open_challenge(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION has_open_challenge(uuid) TO service_role;
