-- RunWar - Migration 56
-- Atomic stored procedure for the claim_territory reversible-split path
-- (a re-run that retraces PART of an existing same-owner zone's own edge -
-- see supabase/functions/claim_territory/merge_geometry.ts's
-- computeZoneSplit and index.ts's caller).
--
-- Mirrors apply_zone_merge's (migration 0053) atomic-write discipline but is
-- a distinct RPC because it is a different transaction shape: one UPDATE
-- writing the untouched remainder back onto the original zone row, no
-- absorbed-row DELETE. The remainder's id, owner_id, influence_level and
-- created_at are all left untouched - only the geometry and area change. The
-- re-run's own polygon proceeds through the existing, unmodified
-- insert-and-merge-scan path as an ordinary new claim.
--
-- Column types match apply_zone_merge's own re-verification against the live
-- table (information_schema.columns): zones.id is UUID, zones.geom_json and
-- zones.geom match the types used below.

CREATE OR REPLACE FUNCTION apply_zone_split(
  p_zone_id    UUID,
  p_geom_wkt   TEXT,
  p_geom_json  TEXT,
  p_area_m2    DOUBLE PRECISION,
  p_updated_at TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE zones
     SET geom       = p_geom_wkt::geometry,
         geom_json  = p_geom_json,
         area_m2    = p_area_m2,
         updated_at = p_updated_at
   WHERE id = p_zone_id;
END;
$$;

COMMENT ON FUNCTION apply_zone_split IS
  'Atomic remainder-geometry UPDATE for the reversible-split-on-re-run path '
  'in claim_territory. Same row id, owner_id, influence_level and created_at '
  'as before - only geometry and area change. No absorbed-row DELETE (that '
  'is apply_zone_merge''s shape, not this one).';
