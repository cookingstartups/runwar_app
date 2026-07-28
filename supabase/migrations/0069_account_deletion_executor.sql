CREATE EXTENSION IF NOT EXISTS pg_net;

-- =============================================================================
-- 0069_account_deletion_executor.sql
-- Bot-transfer executor for expired account_deletion_requests (spec R8;
-- infra/meta/specs/runwar/settings-screen/design.md section 3.7/3.8/4).
--
-- pg_net is required because the final step of deleting a real auth.users
-- row correctly goes through the GoTrue Admin API, which is only reachable
-- over HTTP - so the daily sweep below invokes a service-role edge function
-- via net.http_post rather than doing everything in pure SQL.
--
-- Depends on: 0068 (account_deletion_requests), 0029 (zones).
-- =============================================================================

-- ── resolve_deletion_target_bot ────────────────────────────────────────────
-- Deliberately a small, separate, pluggable function - a deterministic pick
-- from the active seeded bots, hashed against the deleted user's id. Reads
-- only from the bots table, never the retired NPC pattern.
CREATE OR REPLACE FUNCTION resolve_deletion_target_bot(p_user_id UUID)
RETURNS UUID LANGUAGE sql STABLE AS $$
  SELECT id FROM bots
   WHERE is_active = true
   ORDER BY md5(id::text || p_user_id::text)
   LIMIT 1;
$$;

-- One-time backfill: the 5 seeded bots currently have no matching players
-- row. zones.owner_id FKs to players(user_id), not auth.users, so a bot
-- needs only a players row (not a shadow auth.users account) to legally own
-- a zone. Idempotent - a no-op for any bot that already has one.
INSERT INTO players (user_id, username, color)
SELECT b.id, b.username, b.color
  FROM bots b
 WHERE b.is_active = true
ON CONFLICT (user_id) DO NOTHING;

-- ── claim_and_transfer_zones ───────────────────────────────────────────────
-- Claim-then-transact: the claiming UPDATE runs FIRST inside the transaction
-- so its row lock, plus the status = 'pending' predicate no longer matching
-- once committed, is what actually prevents a concurrent daily sweep and a
-- concurrent manual admin trigger from both transferring the same zones.
CREATE OR REPLACE FUNCTION claim_and_transfer_zones(p_request_id UUID)
RETURNS UUID -- the deleted-candidate user_id, or NULL if not claimed
LANGUAGE plpgsql AS $$
DECLARE
  v_user_id UUID;
  v_bot_id  UUID;
BEGIN
  -- Claim FIRST. If any later step in this transaction raises, the whole
  -- transaction (including this claim) rolls back, so the row reverts to
  -- pending and is retried next sweep.
  UPDATE account_deletion_requests
     SET status = 'executed'
   WHERE id = p_request_id AND status = 'pending' AND scheduled_deletion_at <= now()
   RETURNING user_id INTO v_user_id;

  IF v_user_id IS NULL THEN
    RETURN NULL; -- already claimed, already executed, or reactivated meanwhile
  END IF;

  v_bot_id := resolve_deletion_target_bot(v_user_id);
  IF v_bot_id IS NULL THEN
    RAISE EXCEPTION 'no resolvable bot for user %', v_user_id; -- rolls back the claim above
  END IF;

  -- Idempotent safety net: guarantee the resolved bot has a players row
  -- before the zone transfer below needs to satisfy the owner_id FK, even
  -- if a bot was added after this migration's one-time backfill ran.
  INSERT INTO players (user_id, username, color)
  SELECT b.id, b.username, b.color FROM bots b WHERE b.id = v_bot_id
  ON CONFLICT (user_id) DO NOTHING;

  -- Clear attacker references first (FK-safety precondition).
  UPDATE zones
     SET contested_by_id = NULL, status = 'owned',
         dispute_at = NULL, dispute_overlap_m2 = NULL
   WHERE contested_by_id = v_user_id;

  -- Transfer owned zones - the exact resolve_zone_disputes() field-reset set.
  UPDATE zones
     SET owner_id = v_bot_id, influence_level = 1, status = 'owned',
         contested_by_id = NULL, dispute_at = NULL, dispute_overlap_m2 = NULL,
         shield_active = FALSE, shield_expires_at = NULL, updated_at = now()
   WHERE owner_id = v_user_id;

  RETURN v_user_id; -- caller (edge function) now deletes this auth.users row
END;
$$;

REVOKE ALL ON FUNCTION claim_and_transfer_zones(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_and_transfer_zones(UUID) TO service_role;

-- ── admin_pending_deletions ─────────────────────────────────────────────────
-- Minimal admin surface (not a full admin panel) - lists still-pending,
-- past-due requests joined to their originating ticket for visibility.
CREATE OR REPLACE VIEW admin_pending_deletions AS
SELECT adr.id, adr.user_id, adr.requested_at, adr.scheduled_deletion_at,
       st.subject, st.body
  FROM account_deletion_requests adr
  LEFT JOIN support_tickets st
    ON st.user_id = adr.user_id AND st.kind = 'account_deletion'
 WHERE adr.status = 'pending' AND adr.scheduled_deletion_at <= now();

-- ── Daily sweep ─────────────────────────────────────────────────────────────
-- Invokes the account-deletion-executor edge function once a day; the edge
-- function itself calls claim_and_transfer_zones per eligible row, then
-- deletes the auth user via the Admin API.
SELECT cron.schedule('account-deletion-sweep', '0 3 * * *', $$
  SELECT net.http_post(
    url := '<project-ref>.supabase.co/functions/v1/account-deletion-executor',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
$$);
