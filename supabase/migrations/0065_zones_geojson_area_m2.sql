-- 0065_zones_geojson_area_m2.sql
--
-- zones.area_m2 already exists on the underlying zones table (written by
-- apply_zone_merge/apply_zone_split and read directly by passive_income_tick),
-- but the zones_geojson view - the only read path the Flutter Zone model has -
-- does not select it. This adds it to the SELECT list only; no column is
-- renamed or removed, so CREATE OR REPLACE VIEW is sufficient (a DROP is only
-- required when a rename forces it, per 0060's own precedent, which does not
-- apply here). Every other pre-existing column from 0060's view is carried
-- forward unchanged.

CREATE OR REPLACE VIEW zones_geojson AS
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
  z.updated_at,
  z.area_m2
FROM zones z;
