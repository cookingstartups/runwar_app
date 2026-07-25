-- =============================================================================
-- 0058_dispute_overlap_column.sql
-- New zones.dispute_overlap_m2 column (spec R2-AC2, pvp-dispute-e2e/design.md
-- section 4.1). Snapshotted once, at dispute-open, by claim_territory's
-- disputed branch (see supabase/functions/claim_territory/handler.ts /
-- merge_geometry.ts's computeDisputeOverlapAreaSqm) - the true intersection
-- area between the attacker's new ring and the zone's geometry at that
-- instant, in square metres. Read later by the resolve_zone_disputes()
-- pg_cron resolver (migration 0059) as the win-condition numerator.
--
-- zones.dispute_at already exists (0030_zones_fixup.sql) - only this column
-- is new.
-- =============================================================================

ALTER TABLE zones
  ADD COLUMN IF NOT EXISTS dispute_overlap_m2 DOUBLE PRECISION;
