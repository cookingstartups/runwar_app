-- RunWar — Migration 54
-- Harmless safety widen: relax zones.geom from GEOMETRY(Polygon,4326) to a
-- generic GEOMETRY(Geometry,4326) so the column can hold a non-Polygon shape
-- if one is ever produced or ingested, without requiring a further schema
-- change at that point.
--
-- This is NOT required by the adjacent-zone merge feature itself. Under the
-- single-rule merge contract (design.md, 2026-07-04), computeZoneMerges
-- always returns a single, continuous Polygon — the exact union where
-- sources already touch/overlap, or a bounded 12.5 m-radius morphological
-- closing where a real sub-25 m gap exists. There is no MultiPolygon output
-- path in the current algorithm; a MultiPolygon value would only ever be a
-- legacy row or a defensive fallback, never something this feature writes
-- as its normal outcome.
--
-- This migration was originally drafted in runwar_database (migration 0030)
-- but that repo's migration history is not the one actually deployed against
-- the live project (glwsmxjptgmxaiyvdqzp) — runwar_app/supabase/migrations
-- is. Moved here so it is deployable.
--
-- Resilience: the live column may already be a generic Geometry type via
-- out-of-band DDL applied directly against the project, independent of
-- either repo's migration history. Re-running an unconditional ALTER in
-- that case is unnecessary and, depending on the exact starting type, can
-- error. This migration checks geometry_columns first and only ALTERs when
-- the column is still constrained to Polygon.
--
-- The USING clause is a plain cast (geom::geometry), not ST_Multi(geom):
-- ST_Multi() would rewrite every existing Polygon row's value into a
-- MultiPolygon-of-one, which changes stored data, not just the column's
-- declared type. A widen that also silently mutates every existing row's
-- geometry subtype is not "harmless", so the cast here only relaxes the
-- column's type constraint and leaves every existing value exactly as
-- stored.

DO $$
DECLARE
  v_type TEXT;
BEGIN
  SELECT type INTO v_type
    FROM geometry_columns
   WHERE f_table_schema = 'public'
     AND f_table_name = 'zones'
     AND f_geometry_column = 'geom';

  IF v_type IS NOT NULL AND v_type NOT IN ('GEOMETRY', 'GEOMETRYCOLLECTION') THEN
    ALTER TABLE zones
      ALTER COLUMN geom TYPE GEOMETRY(Geometry, 4326)
      USING geom::geometry;
  END IF;
END $$;

COMMENT ON COLUMN zones.geom IS
  'Zone boundary. Always a single Polygon under the current single-rule '
  'adjacent-zone merge contract (design.md, 2026-07-04). The column type '
  'is a generic Geometry (widened from Polygon) purely as a harmless safety '
  'margin; MultiPolygon is a legacy/fallback shape only, never the merge '
  'algorithm''s normal output.';
