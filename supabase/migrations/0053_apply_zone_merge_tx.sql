-- RunWar - Migration 53
-- Atomic stored procedure for the claim_territory adjacent-zone merge path.
-- Wraps the survivor aggregate UPDATE and every absorbed-row DELETE in a
-- single transaction so a crash mid-merge can never leave a stale absorbed
-- row alongside an already-updated survivor (or vice versa).
--
-- This function was originally drafted in runwar_database (migration 0031)
-- but that repo's migration history is not the one actually deployed against
-- the live project (glwsmxjptgmxaiyvdqzp) - runwar_app/supabase/migrations
-- is. Moved here so it is deployable. Column types were re-verified directly
-- against the live table (information_schema.columns) rather than assumed
-- from either repo's migration text: zones.id and zones.owner_id are UUID
-- (from the table's original creation, predating both repos' visible
-- migration history); zones.geom_json, zones.status, zones.influence,
-- zones.credits_earned, zones.last_active_at, zones.shield_active,
-- zones.shield_expires_at, zones.area_m2, zones.influence_level and
-- zones.geom all match the types used below. p_survivor_id/p_absorbed_ids
-- are UUID/UUID[] to match the real column, not TEXT.
--
-- All aggregate values (influence, influence_level, credits_earned,
-- last_active_at, shield_active, shield_expires_at, area_m2) are computed by
-- the caller (claim_territory edge function) from the merged group and
-- passed in already-final; this function only performs the atomic write.
-- No history is kept on unification: absorbed rows are deleted outright,
-- no lineage-tracking column is written.

CREATE OR REPLACE FUNCTION apply_zone_merge(
  p_survivor_id       UUID,
  p_absorbed_ids      UUID[],
  p_geom_wkt          TEXT,
  p_geom_json         TEXT,
  p_influence         REAL,
  p_influence_level   SMALLINT,
  p_credits_earned    REAL,
  p_last_active_at    TIMESTAMPTZ,
  p_shield_active     BOOLEAN,
  p_shield_expires_at TIMESTAMPTZ,
  p_area_m2           DOUBLE PRECISION,
  p_updated_at        TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE zones
     SET geom              = p_geom_wkt::geometry,
         geom_json         = p_geom_json,
         influence         = p_influence,
         influence_level   = p_influence_level,
         credits_earned    = p_credits_earned,
         last_active_at    = p_last_active_at,
         shield_active     = p_shield_active,
         shield_expires_at = p_shield_expires_at,
         area_m2           = p_area_m2,
         updated_at        = p_updated_at
   WHERE id = p_survivor_id;

  IF p_absorbed_ids IS NOT NULL AND array_length(p_absorbed_ids, 1) > 0 THEN
    DELETE FROM zones WHERE id = ANY(p_absorbed_ids);
  END IF;
END;
$$;

COMMENT ON FUNCTION apply_zone_merge IS
  'Atomic survivor UPDATE + absorbed-row DELETE for the adjacent-zone merge '
  'path in claim_territory. No lineage column is written; absorbed rows are '
  'removed outright in the same transaction as the survivor aggregate write.';
