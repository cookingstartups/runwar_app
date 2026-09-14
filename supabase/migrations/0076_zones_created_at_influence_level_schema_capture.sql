-- 0076_zones_created_at_influence_level_schema_capture.sql
--
-- Documents two real, live zones columns that predate this repo's visible
-- migration history: zones.created_at and zones.influence_level. Both are
-- already read by existing views/functions (0060_zones_geojson_status_from_
-- zone_row.sql, 0065_zones_geojson_area_m2.sql select z.created_at and
-- z.influence_level; 0073_activate_shield_on_zone_tx.sql's own comment
-- confirms zones.influence_level is live), but no CREATE TABLE/ADD COLUMN
-- ever defined them in this repo's migration history, so ops_db_verification_
-- schema_grounding_test.ts could not ground a check referencing them. Same
-- pattern already used for zones.geom by
-- 0054_zones_geom_widen_multipolygon.sql: a COMMENT ON COLUMN that
-- documents an existing live column with no ALTER of its type or default.
-- This is a pure documentation migration - it changes nothing about the
-- live schema.

COMMENT ON COLUMN zones.created_at IS
  'Row creation timestamp. Live column, predates this repo''s migration '
  'history; documented here so schema-grounding checks can reference it.';

COMMENT ON COLUMN zones.influence_level IS
  'Zone influence tier used by the merge/adjacency and passive-income '
  'logic. Live column, predates this repo''s migration history; documented '
  'here so schema-grounding checks can reference it.';
