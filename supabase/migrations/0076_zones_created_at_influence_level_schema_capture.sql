-- 0076_zones_created_at_influence_level_schema_capture.sql
--
-- Documents zones.influence_level, a real, live column that predates this
-- repo's visible migration history: it is read by existing views/functions
-- (0060_zones_geojson_status_from_zone_row.sql, 0065_zones_geojson_area_m2.sql
-- select z.influence_level; 0073_activate_shield_on_zone_tx.sql's own comment
-- confirms it is live), but no CREATE TABLE/ADD COLUMN ever defined it in
-- this repo's migration history, so ops_db_verification_schema_grounding_
-- test.ts could not ground a check referencing it. Same pattern already
-- used for zones.geom by 0054_zones_geom_widen_multipolygon.sql: a
-- COMMENT ON COLUMN that documents an existing live column with no ALTER of
-- its type or default. This is a pure documentation migration - it changes
-- nothing about the live schema.
--
-- zones.created_at needs no capture statement here: it IS already defined
-- by a CREATE TABLE in this repo's migration history
-- (0029_runwar_full_schema.sql, `created_at TIMESTAMPTZ NOT NULL DEFAULT
-- now()` in the zones table body), so the schema-grounding test already
-- finds it with no COMMENT ON COLUMN needed. An earlier version of this
-- migration's header wrongly claimed created_at was undefined too.

COMMENT ON COLUMN zones.influence_level IS
  'Zone influence tier used by the merge/adjacency and passive-income '
  'logic. Live column, predates this repo''s migration history; documented '
  'here so schema-grounding checks can reference it.';
