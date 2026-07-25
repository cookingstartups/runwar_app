-- =============================================================================
-- 0061_retire_mechanic_a.sql
-- Mechanic A retirement (spec R1; pvp-dispute-e2e/design.md sections 2.5,
-- 3.4). Drops the disputes table, its apply_dispute_outcome trigger and
-- function - dead scaffolding once mechanic B (the zones-table
-- status/dispute_at/dispute_overlap_m2 flow this feature completes, plus the
-- resolve_zone_disputes() pg_cron resolver in migration 0059) is the only
-- live dispute-resolution path.
--
-- ORDER: must run after 0060 (zones_geojson_status_from_zone_row), which
-- removes the view's LEFT JOIN LATERAL dependency on `disputes` - dropping
-- the table before that migration would break the view outright.
--
-- pg_cron schedule check (spec R1-AC1's Pre, design.md section 4.3's
-- "not found in either repo's migrations during this session, flag for the
-- implementer to locate and unschedule" note): queried the live project's
-- cron.job table directly via the Supabase Management API during
-- implementation. Only two jobs are scheduled - ctf-pre-announce and
-- ctf-activate (runwar_database/supabase/migrations/0012_ctf_scheduled_events.sql)
-- - neither references resolve_dispute or the disputes table in any way.
-- Confirmed, not assumed: resolve_dispute was never actually scheduled via
-- pg_cron in this project, so there is nothing live to unschedule here. The
-- resolve_dispute Edge Function itself lives in runwar_database
-- (supabase/functions/resolve_dispute/), a separate repo this feature does
-- not modify - its removal, if wanted, is a runwar_database-scoped follow-up,
-- not part of this migration.
-- =============================================================================

DROP TRIGGER IF EXISTS dispute_outcome ON disputes;
DROP FUNCTION IF EXISTS apply_dispute_outcome();
DROP TABLE IF EXISTS disputes;
