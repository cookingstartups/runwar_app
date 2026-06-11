-- Do NOT add CONCURRENTLY or VACUUM inside this transaction.
--
-- Rollback for migration 0050: restore player_id everywhere.
-- Reverses every rename applied by 0050_player_id_to_user_id_unification.sql.
-- Apply this file only to revert a post-0050 production regression.

BEGIN;

-- -------------------------------------------------------------------------
-- (A) Drop views, RPCs, and trigger that reference user_id
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
-- (B) Drop RLS policies that use user_id predicates
-- -------------------------------------------------------------------------

DROP POLICY IF EXISTS dmp_own_all                  ON daily_mission_progress;
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

-- -------------------------------------------------------------------------
-- (C) Drop indexes that reference user_id
-- -------------------------------------------------------------------------

DROP INDEX IF EXISTS gps_samples_dedup;
DROP INDEX IF EXISTS idx_gps_samples_user_ts;

-- -------------------------------------------------------------------------
-- (D) Restore PK column name on players: user_id -> id
-- -------------------------------------------------------------------------

ALTER TABLE players RENAME COLUMN user_id TO id;

-- -------------------------------------------------------------------------
-- (E) Restore player_id on every child / FK table
-- -------------------------------------------------------------------------

ALTER TABLE player_economy           RENAME COLUMN user_id TO player_id;
ALTER TABLE player_progress          RENAME COLUMN user_id TO player_id;
ALTER TABLE player_streaks           RENAME COLUMN user_id TO player_id;
ALTER TABLE player_trial             RENAME COLUMN user_id TO player_id;
ALTER TABLE player_devices           RENAME COLUMN user_id TO player_id;
ALTER TABLE daily_mission_progress   RENAME COLUMN user_id TO player_id;
ALTER TABLE anticheat_flags          RENAME COLUMN user_id TO player_id;
ALTER TABLE suspicion_scores         RENAME COLUMN user_id TO player_id;
ALTER TABLE superpower_grants        RENAME COLUMN user_id TO player_id;
ALTER TABLE superpower_offers        RENAME COLUMN user_id TO player_id;
ALTER TABLE behavioral_fingerprints  RENAME COLUMN user_id TO player_id;
ALTER TABLE challenges               RENAME COLUMN user_id TO player_id;
ALTER TABLE credit_transactions      RENAME COLUMN user_id TO player_id;
ALTER TABLE gps_samples              RENAME COLUMN user_id TO player_id;

-- -------------------------------------------------------------------------
-- (F) Restore runs.player_id (was dropped by 0050; re-add as nullable to avoid
--     data loss -- existing rows will have player_id = NULL after this rollback,
--     which matches state before PR #39 dual-write. Backfill from user_id if needed.)
-- -------------------------------------------------------------------------

ALTER TABLE runs ADD COLUMN IF NOT EXISTS player_id UUID REFERENCES players(id) ON DELETE CASCADE;

-- -------------------------------------------------------------------------
-- (G) Recreate indexes with player_id
-- -------------------------------------------------------------------------

CREATE UNIQUE INDEX gps_samples_dedup       ON gps_samples (session_id, ts, player_id);
CREATE        INDEX idx_gps_samples_player_ts ON gps_samples (player_id, ts);

-- -------------------------------------------------------------------------
-- (H) Recreate RLS policies with player_id predicates
-- -------------------------------------------------------------------------

CREATE POLICY dmp_own_all
  ON daily_mission_progress FOR ALL
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY player_economy_select_own
  ON player_economy FOR SELECT
  USING (player_id = auth.uid());

CREATE POLICY player_economy_insert_own
  ON player_economy FOR INSERT TO authenticated
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_economy_update_own
  ON player_economy FOR UPDATE TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_progress_select_own
  ON player_progress FOR SELECT
  USING (player_id = auth.uid());

CREATE POLICY player_progress_insert_own
  ON player_progress FOR INSERT TO authenticated
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_progress_update_own
  ON player_progress FOR UPDATE TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_streaks_select_own
  ON player_streaks FOR SELECT
  USING (player_id = auth.uid());

CREATE POLICY player_streaks_insert_own
  ON player_streaks FOR INSERT TO authenticated
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_streaks_update_own
  ON player_streaks FOR UPDATE TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_trial_select_own
  ON player_trial FOR SELECT
  USING (player_id = auth.uid());

CREATE POLICY player_trial_insert_own
  ON player_trial FOR INSERT TO authenticated
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_trial_update_own
  ON player_trial FOR UPDATE TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_devices_select_own
  ON player_devices FOR SELECT
  USING (player_id = auth.uid());

CREATE POLICY player_devices_insert_own
  ON player_devices FOR INSERT TO authenticated
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_devices_update_own
  ON player_devices FOR UPDATE TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

CREATE POLICY "players insert own samples"
  ON gps_samples FOR INSERT
  WITH CHECK (player_id = auth.uid());

CREATE POLICY "players select own samples"
  ON gps_samples FOR SELECT
  USING (player_id = auth.uid());

CREATE POLICY credit_tx_own_read
  ON credit_transactions FOR SELECT
  USING (player_id = auth.uid());

-- -------------------------------------------------------------------------
-- (I) Restore view, RPCs, and trigger with original player_id signatures
-- -------------------------------------------------------------------------

-- players_and_bots view (pre-0050 form: p.id aliased as id in human branch)
CREATE OR REPLACE VIEW players_and_bots AS
  SELECT
    p.id                            AS id,
    p.username::text                AS username,
    p.color,
    COALESCE(pp.score, 0)::integer  AS score,
    false                           AS is_bot
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

-- apply_credit_delta (original p_player_id signature from 0017/0040)
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
  UPDATE players
     SET credits = credits + p_delta
   WHERE id = p_player_id
  RETURNING credits INTO new_balance;

  IF new_balance IS NULL THEN
    RAISE EXCEPTION 'apply_credit_delta: player % not found', p_player_id;
  END IF;

  IF new_balance < 0 AND p_reason <> 'admin_clawback' THEN
    RAISE EXCEPTION 'apply_credit_delta: insufficient balance (would be %)', new_balance;
  END IF;

  INSERT INTO credit_transactions
    (player_id, delta, reason, related_entity_id, related_entity_type, metadata)
  VALUES
    (p_player_id, p_delta, p_reason, p_related_entity_id, p_related_entity_type, p_metadata);

  RETURN new_balance;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

REVOKE ALL    ON FUNCTION apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION apply_credit_delta(UUID, BIGINT, TEXT, UUID, TEXT, JSONB) TO service_role;

-- complete_first_mission_tx (original p_player_id signature from 0041)
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
  SELECT pp.first_mission_completed_at, pp.updated_at
    INTO v_progress
    FROM player_progress pp
   WHERE pp.player_id = p_player_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'complete_first_mission_tx: no player_progress row for player %', p_player_id;
  END IF;

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

  SELECT ps.streak_started_at
    INTO v_streaks
    FROM player_streaks ps
   WHERE ps.player_id = p_player_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'complete_first_mission_tx: no player_streaks row for player %', p_player_id;
  END IF;

  v_streak_at := COALESCE(v_streaks.streak_started_at, v_now);

  UPDATE player_progress
     SET first_mission_completed_at = v_now,
         updated_at                 = v_now
   WHERE player_id = p_player_id
     AND first_mission_completed_at IS NULL;

  UPDATE player_streaks
     SET streak_started_at = v_streak_at,
         updated_at        = v_now
   WHERE player_id = p_player_id
     AND streak_started_at IS NULL;

  SELECT apply_credit_delta(
    p_player_id,
    50,
    'first_mission_reward',
    NULL,
    NULL,
    '{}'::jsonb
  ) INTO v_credits;

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

-- consume_ghost_run_charge (original p_player_id signature from 0017)
CREATE OR REPLACE FUNCTION consume_ghost_run_charge(p_player_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_grant_id UUID;
BEGIN
  SELECT id INTO v_grant_id
    FROM superpower_grants
   WHERE player_id   = p_player_id
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

-- create_offer_with_supersede (original p_player_id signature from 0017)
CREATE OR REPLACE FUNCTION create_offer_with_supersede(
  p_player_id          UUID,
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
  PERFORM 1 FROM players WHERE id = p_player_id FOR UPDATE;

  UPDATE superpower_offers
     SET status = 'expired', resolved_at = NOW()
   WHERE player_id = p_player_id AND status = 'pending';

  INSERT INTO superpower_offers
    (player_id, triggering_grant_id, offer_type, offered_power_type, tier,
     cost_credits, expires_at)
  VALUES
    (p_player_id, p_triggering_grant, p_offer_type, p_offered_power_type, p_tier,
     p_cost_credits, NOW() + (p_window_seconds || ' seconds')::INTERVAL)
  RETURNING id INTO new_offer_id;

  RETURN new_offer_id;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

REVOKE ALL    ON FUNCTION create_offer_with_supersede(UUID, UUID, TEXT, TEXT, TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_offer_with_supersede(UUID, UUID, TEXT, TEXT, TEXT, INT, INT) TO service_role;

-- decline_offer (original form from 0017 -- uses auth.uid(), no param rename needed)
CREATE OR REPLACE FUNCTION decline_offer(p_offer_id UUID)
RETURNS VOID AS $$
  UPDATE superpower_offers
     SET status      = 'declined',
         resolved_at = NOW()
   WHERE id        = p_offer_id
     AND player_id = auth.uid()
     AND status    = 'pending';
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION decline_offer(UUID) TO authenticated;

-- fn_players_create_child_rows (original form from 0043)
CREATE OR REPLACE FUNCTION fn_players_create_child_rows()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO player_economy  (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO player_progress (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO player_streaks  (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO player_trial    (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  -- NOT player_devices: device registration is explicit per spec.
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_players_create_child_rows ON players;
CREATE TRIGGER trg_players_create_child_rows
  AFTER INSERT ON players
  FOR EACH ROW
  EXECUTE FUNCTION fn_players_create_child_rows();

COMMIT;
