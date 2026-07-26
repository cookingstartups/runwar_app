-- =============================================================================
-- 0060_zones_geojson_status_from_zone_row.sql
--
-- Implementer-discovered gap, not explicitly named in design.md/requirements.md
-- but required for the pvp-dispute-e2e feature to actually function: the live
-- zones_geojson view (originally runwar_database/supabase/migrations/0006_zones_view.sql,
-- confirmed via the Management API to be the exact view currently deployed)
-- derives its `status` and dispute-expiry columns from a LEFT JOIN LATERAL
-- against the `disputes` table (mechanic A) - the same table the Team Lead
-- brief confirmed has zero rows, ever, in production. Every Flutter read path
-- (SupabaseZonesRepository.fetchByCity/fetchById, and therefore
-- disputeCountdownProvider once re-pointed at ZonesRepository, spec R11) goes
-- through this view. Left unfixed, the view would ALWAYS report status =
-- 'owned' regardless of the zones.status/zones.dispute_at this feature's
-- claim_territory + resolver changes actually write - the whole dispute UI
-- would silently show nothing, no matter how correct the server-side timer
-- and resolver logic is.
--
-- Fix: source status/dispute_at/contested_by_id directly from the zones row
-- itself (already correctly written by claim_territory - see 0030's
-- dispute_at column and this feature's handler.ts changes), dropping the
-- dependency on the disputes table entirely. This also unblocks migration
-- 0061's retirement of the disputes table/trigger/function: that migration
-- must run AFTER this one, since dropping `disputes` while this view still
-- joins against it would break the view outright.
-- =============================================================================

-- CREATE OR REPLACE VIEW cannot rename an existing view column
-- (dispute_expires_at -> dispute_at, attacker_id -> contested_by_id) -
-- Postgres error 42P16. DROP + CREATE is required for this column rename.
DROP VIEW IF EXISTS zones_geojson;

CREATE VIEW zones_geojson AS
SELECT
  z.id,
  z.owner_id,
  z.city,
  z.influence_level,
  z.status,
  z.dispute_at,
  z.dispute_overlap_m2,
  z.contested_by_id,
  z.shield_active,
  z.shield_expires_at,
  ST_AsGeoJSON(z.geom)::jsonb AS geom_json,
  z.created_at,
  z.updated_at
FROM zones z;
