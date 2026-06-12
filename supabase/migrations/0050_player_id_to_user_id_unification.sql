-- Do NOT add CONCURRENTLY or VACUUM inside this transaction.
--
-- Migration 0050: Rename player_id -> user_id across all tables, RPCs, indexes, and policies.
-- Renames players.id -> players.user_id as the canonical auth subject identifier.
-- All foreign keys, indexes, RLS policies, views, RPCs, and triggers are atomically updated.
-- Depends on: 0049 (gps_samples realtime), 0043 (signup trigger), 0041 (complete_first_mission_tx),
--             0040 (apply_credit_delta), 0017 (credit_ledger_drops_superpowers).

BEGIN;

-- -------------------------------------------------------------------------
-- (A) Drop dependent views and RPCs that reference player_id
-- -------------------------------------------------------------------------

DROP VIEW IF EXISTS players_and_bots;

DROP FUNCTION IF EXISTS apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) CASCADE;
DROP FUNCTION IF EXISTS complete_first_mission_tx(UUID) CASCADE;
DROP FUNCTION IF EXISTS consume_ghost_run_charge(UUID) CASCADE;
DROP FUNCTION IF EXISTS create_offer_with_supersede(UUID, UUID, TEXT, TEXT, TEXT, INT, INT) CASCADE;
DROP FUNCTION IF EXISTS decline_offer(UUID) CASCADE;

DROP TRIGGER  IF EXISTS trg_players_create_child_rows ON players;
DROP FUNCTION IF EXISTS fn_players_create_child_rows() CASCADE;

-- -------------------------------------------------------------------------
-- (B) Drop RLS policies whose predicates reference player_id
-- -------------------------------------------------------------------------

DROP POLICY IF EXISTS dmp_own_all                  ON daily_mission_progress;
DROP POLICY IF EXISTS dmp_select_own               ON daily_mission_progress;
DROP POLICY IF EXISTS player_economy_select_own    ON player_economy;
DROP POLICY IF EXISTS player_economy_insert_own    ON player_economy;
DROP POLICY IF EXISTS player_economy_update_own    ON player_economy;
DROP POLICY IF EXISTS player_progress_select_own   ON player_progress;
DROP POLICY IF EXISTS player_progress_insert_own   ON player_progress;
DROP POLICY IF EXISTS player_progress_update_own   ON player_progress;
DROP POLICY IF EXISTS player_streaks_select_own    ON player_streaks;
DROP POLICY IF EXISTS player_streaks_insert_own    ON player_streaks;
DROP POLICY IF EXISTS player_streaks_update_own    ON player_streaks;
DROP POLICY IF EXISTS player_trial_select_own      ON player_trial;
DROP POLICY IF EXISTS player_trial_insert_own      ON player_trial;
DROP POLICY IF EXISTS player_trial_update_own      ON player_trial;
DROP POLICY IF EXISTS player_devices_select_own    ON player_devices;
DROP POLICY IF EXISTS player_devices_insert_own    ON player_devices;
DROP POLICY IF EXISTS player_devices_update_own    ON player_devices;
DROP POLICY IF EXISTS "players insert own samples" ON gps_samples;
DROP POLICY IF EXISTS "players select own samples" ON gps_samples;
DROP POLICY IF EXISTS "service role full access"   ON gps_samples;
DROP POLICY IF EXISTS credit_tx_own_read           ON credit_transactions;
DROP POLICY IF EXISTS runs_self                    ON runs;
DROP POLICY IF EXISTS gps_self                     ON gps_samples;
DROP POLICY IF EXISTS sp_self                      ON superpower_grants;
DROP POLICY IF EXISTS offers_own_read              ON superpower_offers;
DROP POLICY IF EXISTS challenges_self_read         ON challenges;

-- -------------------------------------------------------------------------
-- (C) Drop indexes that name player_id explicitly
-- -------------------------------------------------------------------------

DROP INDEX IF EXISTS gps_samples_dedup;
DROP INDEX IF EXISTS idx_gps_samples_player_ts;

-- -------------------------------------------------------------------------
-- (D) Rename PK on parent table: players.id -> players.user_id
-- -------------------------------------------------------------------------

ALTER TABLE players RENAME COLUMN id TO user_id;

-- -------------------------------------------------------------------------
-- (E) Rename player_id -> user_id on every child / FK table
-- -------------------------------------------------------------------------

ALTER TABLE player_economy           RENAME COLUMN player_id TO user_id;
ALTER TABLE player_progress          RENAME COLUMN player_id TO user_id;
ALTER TABLE player_streaks           RENAME COLUMN player_id TO user_id;
ALTER TABLE player_trial             RENAME COLUMN player_id TO user_id;
ALTER TABLE player_devices           RENAME COLUMN player_id TO user_id;
-- daily_mission_progress already has user_id (nullable) from a prior migration;
-- backfill, constrain, then drop the legacy player_id instead of rename.
UPDATE daily_mission_progress SET user_id = player_id WHERE user_id IS NULL;
ALTER TABLE daily_mission_progress ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE daily_mission_progress DROP COLUMN player_id;
ALTER TABLE anticheat_flags          RENAME COLUMN player_id TO user_id;
ALTER TABLE suspicion_scores         RENAME COLUMN player_id TO user_id;
ALTER TABLE superpower_grants        RENAME COLUMN player_id TO user_id;
ALTER TABLE superpower_offers        RENAME COLUMN player_id TO user_id;
ALTER TABLE behavioral_fingerprints  RENAME COLUMN player_id TO user_id;
ALTER TABLE challenges               RENAME COLUMN player_id TO user_id;
ALTER TABLE credit_transactions      RENAME COLUMN player_id TO user_id;
ALTER TABLE gps_samples              RENAME COLUMN player_id TO user_id;
ALTER TABLE ctf_participants         RENAME COLUMN player_id TO user_id;
-- referrals: no rename -- uses invitee_id/inviter_id, no player_id column
-- presences: no rename -- no DB table; Realtime Presence is a transient broadcast channel

-- -------------------------------------------------------------------------
-- (F) Drop duplicate runs.player_id (runs.user_id already exists and is NOT NULL)
-- -------------------------------------------------------------------------

ALTER TABLE runs DROP COLUMN IF EXISTS player_id;

-- -------------------------------------------------------------------------
-- (G) Recreate indexes with user_id
-- -------------------------------------------------------------------------

CREATE UNIQUE INDEX gps_samples_dedup    ON gps_samples (session_id, ts, user_id);
CREATE        INDEX idx_gps_samples_user_ts ON gps_samples (user_id, ts);

-- -------------------------------------------------------------------------
-- (H) Recreate RLS policies with user_id predicates
-- -------------------------------------------------------------------------

CREATE POLICY dmp_own_all
  ON daily_mission_progress FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY dmp_select_own
  ON daily_mission_progress FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY player_economy_select_own
  ON player_economy FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY player_economy_insert_own
  ON player_economy FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_economy_update_own
  ON player_economy FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_progress_select_own
  ON player_progress FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY player_progress_insert_own
  ON player_progress FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_progress_update_own
  ON player_progress FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_streaks_select_own
  ON player_streaks FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY player_streaks_insert_own
  ON player_streaks FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_streaks_update_own
  ON player_streaks FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_trial_select_own
  ON player_trial FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY player_trial_insert_own
  ON player_trial FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_trial_update_own
  ON player_trial FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_devices_select_own
  ON player_devices FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY player_devices_insert_own
  ON player_devices FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY player_devices_update_own
  ON player_devices FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "players insert own samples"
  ON gps_samples FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "players select own samples"
  ON gps_samples FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "service role full access"
  ON gps_samples
  USING (auth.role() = 'service_role');

CREATE POLICY credit_tx_own_read
  ON credit_transactions FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY runs_self
  ON runs FOR ALL
  USING (user_id = auth.uid());
CREATE POLICY gps_self
  ON gps_samples FOR ALL
  USING (user_id = auth.uid());
CREATE POLICY sp_self
  ON superpower_grants FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY offers_own_read
  ON superpower_offers FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY challenges_self_read
  ON challenges FOR SELECT
  USING (user_id = auth.uid());

-- -------------------------------------------------------------------------
-- (I) Recreate view, RPCs, and trigger
-- -------------------------------------------------------------------------

-- players_and_bots view
CREATE OR REPLACE VIEW players_and_bots AS
  SELECT
    p.user_id,
    p.username::text                AS username,
    p.color,
    COALESCE(pp.score, 0)::integer  AS score,
    false                           AS is_bot
  FROM players p
  LEFT JOIN player_progress pp ON pp.user_id = p.user_id
UNION ALL
  SELECT
    id   AS user_id,
    username,
    color,
    score,
    true AS is_bot
  FROM bots
  WHERE is_active = true;

-- apply_credit_delta
-- Sole chokepoint for all credit movement. Lock-order contract:
--   players FOR UPDATE -> superpower_grants -> zones -> hex_ownership.
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
  UPDATE players
     SET credits = credits + p_delta
   WHERE user_id = p_user_id
  RETURNING credits INTO new_balance;

  IF new_balance IS NULL THEN
    RAISE EXCEPTION 'apply_credit_delta: player % not found', p_user_id;
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

-- complete_first_mission_tx
-- Lock order (alphabetical, prevents deadlock):
--   1. player_progress FOR UPDATE
--   2. player_streaks  FOR UPDATE
--   3. player_economy  (acquired inside apply_credit_delta)
-- Idempotency: if first_mission_completed_at IS NOT NULL, returns existing values
-- without re-crediting.
CREATE OR REPLACE FUNCTION complete_first_mission_tx(p_user_id UUID)
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
   WHERE pp.user_id = p_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'complete_first_mission_tx: no player_progress row for player %', p_user_id;
  END IF;

  -- Idempotency: already completed -- return without side effects.
  IF v_progress.first_mission_completed_at IS NOT NULL THEN
    SELECT ps.streak_started_at
      INTO v_streaks
      FROM player_streaks ps
     WHERE ps.user_id = p_user_id;

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
   WHERE ps.user_id = p_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'complete_first_mission_tx: no player_streaks row for player %', p_user_id;
  END IF;

  v_streak_at := COALESCE(v_streaks.streak_started_at, v_now);

  -- Stamp first_mission_completed_at on player_progress.
  UPDATE player_progress
     SET first_mission_completed_at = v_now,
         updated_at                 = v_now
   WHERE user_id = p_user_id
     AND first_mission_completed_at IS NULL;

  -- Set streak_started_at on player_streaks if not already set.
  UPDATE player_streaks
     SET streak_started_at = v_streak_at,
         updated_at        = v_now
   WHERE user_id = p_user_id
     AND streak_started_at IS NULL;

  -- Award 50 credits via apply_credit_delta (acquires player_economy lock -- third in chain).
  SELECT apply_credit_delta(
    p_user_id,
    50,
    'first_mission_reward',
    NULL,
    NULL,
    '{}'::jsonb
  ) INTO v_credits;

  -- Best-effort daily login tick (may not exist in older deploys).
  BEGIN
    PERFORM record_daily_login(p_user_id);
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

-- consume_ghost_run_charge
-- Decrements charges on one active GHOST_RUN grant for the player.
-- Returns TRUE if a charge was consumed, FALSE if no active charges exist.
CREATE OR REPLACE FUNCTION consume_ghost_run_charge(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_grant_id UUID;
BEGIN
  SELECT id INTO v_grant_id
    FROM superpower_grants
   WHERE user_id    = p_user_id
     AND power_type  = 'GHOST_RUN'
     AND charges     > charges_used
     AND consumed_at IS NULL
   ORDER BY created_at ASC
   LIMIT 1
   FOR UPDATE SKIP LOCKED;

  IF v_grant_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE superpower_grants
     SET charges_used = charges_used + 1,
         consumed_at  = CASE
                          WHEN charges_used + 1 >= charges THEN NOW()
                          ELSE consumed_at
                        END
   WHERE id = v_grant_id;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION consume_ghost_run_charge(UUID) TO service_role;

-- create_offer_with_supersede
-- Serialises concurrent earn events for the same player by locking the player
-- row first, expiring any pending offer, then inserting the new one.
-- Eliminates the TOCTOU race between "expire previous pending" and "insert new".
CREATE OR REPLACE FUNCTION create_offer_with_supersede(
  p_user_id            UUID,
  p_triggering_grant   UUID,
  p_offer_type         TEXT,
  p_offered_power_type TEXT,
  p_tier               TEXT,
  p_cost_credits       INT,
  p_window_seconds     INT
) RETURNS UUID AS $$
DECLARE
  new_offer_id UUID;
BEGIN
  -- Lock the player row to serialise concurrent earn events.
  PERFORM 1 FROM players WHERE user_id = p_user_id FOR UPDATE;

  -- Mark any pending offer expired (idempotent -- re-running with no rows is fine).
  UPDATE superpower_offers
     SET status = 'expired', resolved_at = NOW()
   WHERE user_id = p_user_id AND status = 'pending';

  INSERT INTO superpower_offers
    (user_id, triggering_grant_id, offer_type, offered_power_type, tier,
     cost_credits, expires_at)
  VALUES
    (p_user_id, p_triggering_grant, p_offer_type, p_offered_power_type, p_tier,
     p_cost_credits, NOW() + (p_window_seconds || ' seconds')::INTERVAL)
  RETURNING id INTO new_offer_id;

  RETURN new_offer_id;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

REVOKE ALL    ON FUNCTION create_offer_with_supersede(UUID, UUID, TEXT, TEXT, TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_offer_with_supersede(UUID, UUID, TEXT, TEXT, TEXT, INT, INT) TO service_role;

-- decline_offer
-- Uses auth.uid() to ensure only the offer's owner can decline it.
-- RETURNS VOID -- UPDATE either applies or no-ops (already resolved rows don't match WHERE).
CREATE OR REPLACE FUNCTION decline_offer(p_offer_id UUID)
RETURNS VOID AS $$
  UPDATE superpower_offers
     SET status      = 'declined',
         resolved_at = NOW()
   WHERE id      = p_offer_id
     AND user_id = auth.uid()
     AND status  = 'pending';
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION decline_offer(UUID) TO authenticated;

-- fn_players_create_child_rows (signup trigger)
-- Atomically inserts default rows into all four 1:1 child tables on player creation.
-- player_devices is NOT included -- device registration is an explicit separate action.
-- ON CONFLICT DO NOTHING makes the trigger safe against the backfill race window.
CREATE OR REPLACE FUNCTION fn_players_create_child_rows()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO player_economy  (user_id) VALUES (NEW.user_id) ON CONFLICT DO NOTHING;
  INSERT INTO player_progress (user_id) VALUES (NEW.user_id) ON CONFLICT DO NOTHING;
  INSERT INTO player_streaks  (user_id) VALUES (NEW.user_id) ON CONFLICT DO NOTHING;
  INSERT INTO player_trial    (user_id) VALUES (NEW.user_id) ON CONFLICT DO NOTHING;
  -- NOT player_devices: device registration is explicit per spec.
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_players_create_child_rows
  AFTER INSERT ON players
  FOR EACH ROW
  EXECUTE FUNCTION fn_players_create_child_rows();

COMMIT;
