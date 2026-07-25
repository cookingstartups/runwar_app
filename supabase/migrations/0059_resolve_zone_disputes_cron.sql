-- =============================================================================
-- 0059_resolve_zone_disputes_cron.sql
-- pg_cron resolver for mechanic B (zones-table) disputes (spec R3, R4, R5,
-- R6, R8, R10, R12; pvp-dispute-e2e/design.md section 3.2).
--
-- Modeled on the existing, live pg_cron.schedule(...) pattern
-- (runwar_database/supabase/migrations/0012_ctf_scheduled_events.sql) - a
-- per-minute, pure-SQL resolver, no edge function and no pg_net required for
-- the win/lose decision itself, since the overlap numerator
-- (dispute_overlap_m2) was already snapshotted at dispute-open (migration
-- 0058 / claim_territory's disputed branch) and the denominator (the zone's
-- CURRENT live area) is native PostGIS.
--
-- CRITICAL correctness detail: zones.geom is SRID 4326 (degree-based), so a
-- raw ST_Area(geom) call returns square DEGREES, not square metres. Casting
-- to geography first - ST_Area(geography(geom)) - is what makes the result
-- comparable to dispute_overlap_m2 (computed in real metres by turf at
-- dispute-open). Omitting the cast is a silent bug: the comparison still
-- evaluates to *something*, it is just meaningless at this scale. Every
-- branch below uses the cast form.
--
-- Win condition: attacker's snapshotted overlap area exceeds 50% of the
-- zone's CURRENT live area - evaluated regardless of influence_level. This
-- is a deliberate, operator-confirmed departure from game-mechanics.md's
-- level-based win rule (design.md section 1) - influence_level only governs
-- the consequence of a LOSS below, never who wins.
--
-- Idempotency / race safety: every branch's WHERE status = 'disputed' guard
-- means a second invocation against an already-resolved zone (an
-- overlapping cron run, or a defender's own re-run that already flipped the
-- zone back to 'owned' via claim_territory's existing "defending resolves
-- it" branch) matches zero rows - no double-transfer, no double-decrement,
-- no clobbering a defender's successful re-run. This mirrors
-- apply_dispute_outcome's own OLD.resolved_at IS NOT NULL idempotency guard
-- (0016_dispute_resolution_inversion.sql, runwar_database - the mechanic
-- being retired by a later migration in this same feature).
--
-- Deliberately absent: no how-fast-the-attack-was-mounted signal of any
-- kind. Confirmed unimplementable (no per-zone or per-claim timing data
-- exists or is reconstructable in the live schema) and deliberately
-- rejected, not deferred (spec R10).
-- =============================================================================

CREATE OR REPLACE FUNCTION resolve_zone_disputes() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  -- Attacker wins: the snapshotted overlap exceeds 50% of the zone's
  -- current live area (ST_Area(geography(geom)), the geodesic-area cast -
  -- NOT the raw, degree-based ST_Area(geom)). Whole-zone transfer at
  -- level 1 - not a computed intersection sub-polygon (design.md section 1,
  -- an accepted, documented departure from game-mechanics.md's
  -- intersection-only model).
  UPDATE zones
     SET owner_id           = contested_by_id,
         influence_level    = 1,
         status             = 'owned',
         contested_by_id    = NULL,
         dispute_at         = NULL,
         dispute_overlap_m2 = NULL,
         shield_active      = FALSE,
         shield_expires_at  = NULL,
         updated_at         = now()
   WHERE status = 'disputed'
     AND dispute_at <= now()
     AND dispute_overlap_m2 > 0.5 * ST_Area(geography(geom));

  -- Defender wins, level > 1: decrement by exactly 1 (an integer step, never
  -- a proportional change, and never touching the continuous
  -- zones.influence field) - dispute clears, ownership is untouched.
  UPDATE zones
     SET influence_level    = influence_level - 1,
         status             = 'owned',
         contested_by_id    = NULL,
         dispute_at         = NULL,
         dispute_overlap_m2 = NULL,
         updated_at         = now()
   WHERE status = 'disputed'
     AND dispute_at <= now()
     AND influence_level > 1
     AND NOT (dispute_overlap_m2 > 0.5 * ST_Area(geography(geom)));

  -- Level-1 floor: an explicit third branch, never folded into the
  -- decrement branch above (which would otherwise floor the level below 1).
  -- A losing attack against an already-level-1 zone is a pure no-op: the
  -- dispute clears, level and ownership are both untouched, no cost either
  -- side.
  UPDATE zones
     SET status             = 'owned',
         contested_by_id    = NULL,
         dispute_at         = NULL,
         dispute_overlap_m2 = NULL,
         updated_at         = now()
   WHERE status = 'disputed'
     AND dispute_at <= now()
     AND influence_level <= 1
     AND NOT (dispute_overlap_m2 > 0.5 * ST_Area(geography(geom)));
END;
$$;

COMMENT ON FUNCTION resolve_zone_disputes() IS
  'Per-minute pg_cron resolver for mechanic B (zones-table) disputes. '
  'Win condition is snapshotted overlap area vs the zone''s CURRENT live '
  'area (geography-cast, never the raw degree-based form) - never '
  'influence_level. Every branch guards on status = ''disputed'' for '
  'idempotency and race safety against a concurrent defend/claim.';

SELECT cron.schedule('resolve-zone-disputes', '* * * * *',
  'SELECT resolve_zone_disputes();');
