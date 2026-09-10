-- RunWar - Migration 73
-- Atomic stored procedure for the activate_shield edge function's
-- consume-from-inventory SHIELD activation. Modelled directly on
-- consume_ghost_run_charge (migration 0050): locks the target zone row,
-- checks ownership inside that lock, consumes the oldest unconsumed SHIELD
-- grant for the caller with FOR UPDATE SKIP LOCKED, and writes the zone's
-- shield fields, all in one transaction, so a rejected activation (zone not
-- found, not owned by the caller, or no grant available) leaves every row
-- exactly as it was.
--
-- zones.shield_active and zones.shield_expires_at already exist on the live
-- table (present live, absent from this repo's migration history per the
-- live-schema read-only check performed before writing this file), so this
-- function only reads and writes them - it does not add or alter either
-- column. superpower_grants stays user-scoped with no per-zone targeting
-- column: SHIELD grants are consumed oldest-unconsumed-first, the same
-- zone-agnostic rule consume_ghost_run_charge already uses for GHOST_RUN.
--
-- Column types match the live table and the types already used by
-- apply_zone_merge (migration 0053) and consume_ghost_run_charge
-- (migration 0050): zones.id/owner_id are UUID, zones.influence_level is
-- SMALLINT, zones.shield_active is BOOLEAN, zones.shield_expires_at and
-- zones.updated_at are TIMESTAMPTZ; superpower_grants.id/user_id are UUID,
-- charges/charges_used are integer columns, consumed_at is TIMESTAMPTZ.
--
-- Rollback: DROP FUNCTION IF EXISTS activate_shield_on_zone_tx(UUID, UUID, NUMERIC);
-- Kept as this header comment rather than a separate 0073_rollback.sql file,
-- per this repo's rollback-file naming footgun (a same-numeric-prefix
-- rollback file is re-applied forward by a plain db push against an
-- unrecorded history) - not worth adding for a single DROP FUNCTION.

CREATE OR REPLACE FUNCTION activate_shield_on_zone_tx(
  p_user_id         UUID,
  p_zone_id         UUID,
  p_hours_per_level NUMERIC
)
RETURNS TABLE (
  outcome           TEXT,
  shield_expires_at TIMESTAMPTZ,
  influence_level   INT,
  grant_id          UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_owner_id     UUID;
  v_level        SMALLINT;
  v_grant_id     UUID;
  v_expires_at   TIMESTAMPTZ;
BEGIN
  -- Lock the target zone row first. Ownership is checked inside this same
  -- lock so a concurrent transfer of the zone cannot race the check, and
  -- neither branch below performs any write before both the zone and the
  -- grant are confirmed.
  SELECT owner_id, influence_level
    INTO v_owner_id, v_level
    FROM zones
   WHERE id = p_zone_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'zone_not_found'::TEXT, NULL::TIMESTAMPTZ, NULL::INT, NULL::UUID;
    RETURN;
  END IF;

  IF v_owner_id <> p_user_id THEN
    RETURN QUERY SELECT 'not_owner'::TEXT, NULL::TIMESTAMPTZ, NULL::INT, NULL::UUID;
    RETURN;
  END IF;

  -- Oldest unconsumed SHIELD grant for this caller, zone-agnostic, exactly
  -- mirroring consume_ghost_run_charge's own selection and locking.
  SELECT id INTO v_grant_id
    FROM superpower_grants
   WHERE user_id     = p_user_id
     AND power_type   = 'SHIELD'
     AND charges      > charges_used
     AND consumed_at IS NULL
   ORDER BY created_at ASC
   LIMIT 1
   FOR UPDATE SKIP LOCKED;

  IF v_grant_id IS NULL THEN
    RETURN QUERY SELECT 'no_grant'::TEXT, NULL::TIMESTAMPTZ, NULL::INT, NULL::UUID;
    RETURN;
  END IF;

  UPDATE superpower_grants
     SET charges_used = charges_used + 1,
         consumed_at  = CASE
                           WHEN charges_used + 1 >= charges THEN NOW()
                           ELSE consumed_at
                         END
   WHERE id = v_grant_id;

  v_expires_at := NOW() + (p_hours_per_level * v_level) * INTERVAL '1 hour';

  UPDATE zones
     SET shield_active     = TRUE,
         shield_expires_at = v_expires_at,
         updated_at        = NOW()
   WHERE id = p_zone_id;

  RETURN QUERY SELECT 'ok'::TEXT, v_expires_at, v_level::INT, v_grant_id;
END;
$$;

REVOKE ALL    ON FUNCTION activate_shield_on_zone_tx(UUID, UUID, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION activate_shield_on_zone_tx(UUID, UUID, NUMERIC) TO service_role;
