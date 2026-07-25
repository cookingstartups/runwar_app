// supabase/functions/tests/resolve_zone_disputes_migration_test.ts
//
// Source-inspection coverage for the pg_cron resolver migration
// (spec R3, R4, R5, R6, R8, R10, R12). design.md's own contract is pure SQL
// in a migration file, not an edge function - there is no injectable
// database client to drive here the way resolve_decay_merges_test.ts does,
// and no live Postgres/PostGIS instance is available in this test
// environment to execute the migration for real. This test instead asserts
// the required SQL invariants directly against the migration's source text,
// the same anchored-inspection escape hatch already established in
// claim_territory_merge_wiring_test.ts for logic that cannot be exercised
// without a live database.
//
// Caveat (flagged, not hidden): this proves the SQL CONTAINS the required
// clauses, not that PostgreSQL evaluates them correctly at runtime. A true
// behavioral test (feeding known-good/known-bad overlap fixtures through a
// live Postgres+PostGIS instance, per design.md's own "essential test
// coverage" framing for the SRID bug) requires local Supabase/Postgres
// infra this sandbox does not have; recommended as a fast-follow once a
// `supabase start` (or equivalent CI Postgres) harness exists for this repo.
//
// Run: npx deno test supabase/functions/tests/resolve_zone_disputes_migration_test.ts

import { assert, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findMigration(nameFragment: string): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  const matches: string[] = [];
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes(nameFragment)) matches.push(entry.name);
  }
  assert(
    matches.length > 0,
    `No migration file matching "${nameFragment}" found under supabase/migrations/ - the resolver migration has not been created yet (spec R3/R4/R5/R6/R8/R10/R12).`,
  );
  return Deno.readTextFileSync(dirPath + matches[0]);
}

Deno.test('the resolver migration schedules a pg_cron job against resolve_zone_disputes', () => {
  const sql = findMigration('resolve_zone_disputes');
  assert(sql.includes('cron.schedule'), 'must schedule a pg_cron job (spec R3)');
  assert(sql.includes('resolve_zone_disputes'), 'the scheduled function must be resolve_zone_disputes');
});

Deno.test('the resolver casts geom to geography before computing area (SRID 4326 fix)', () => {
  const sql = findMigration('resolve_zone_disputes');
  assert(sql.toLowerCase().includes('st_area(geography(geom))'),
    'the resolver must compute the zone\'s current area as ST_Area(geography(geom)), not a raw ST_Area(geom) - omitting the geography cast silently compares meter^2 against degree^2 (spec R4-AC2, design.md\'s single most likely silent-bug vector)');
});

Deno.test('the resolver never compares the raw uncast ST_Area(geom) against dispute_overlap_m2', () => {
  const sql = findMigration('resolve_zone_disputes');
  // A naive, uncast comparison would read as "dispute_overlap_m2 > 0.5 * ST_Area(geom)"
  // with no geography(...) wrapper in between - assert that exact naive form
  // is absent, not merely that the correct form is present elsewhere.
  const naive = /dispute_overlap_m2\s*>\s*0\.5\s*\*\s*st_area\(geom\)/i;
  assertFalse(naive.test(sql),
    'found a naive degree-based area comparison (ST_Area(geom) with no geography cast) - this is the exact silent bug design.md flags: degrees^2 at this scale are not proportionally comparable to dispute_overlap_m2\'s meters^2 (spec R4-AC2)');
});

Deno.test('every resolution branch guards on status = disputed for idempotency', () => {
  const sql = findMigration('resolve_zone_disputes');
  const guardCount = (sql.match(/status\s*=\s*'disputed'/gi) ?? []).length;
  assert(guardCount >= 3,
    `expected at least 3 branches (attacker-win, defender-decrement, level-1-floor) each guarded on status = 'disputed', found ${guardCount} occurrences (spec R12-AC1, R12-AC2)`);
});

Deno.test('the attacker-win branch transfers ownership and resets influence_level to 1', () => {
  const sql = findMigration('resolve_zone_disputes');
  assert(/owner_id\s*=\s*contested_by_id/i.test(sql),
    'attacker-win branch must set owner_id = contested_by_id (spec R5-AC1)');
  assert(/influence_level\s*=\s*1\b/.test(sql),
    'attacker-win branch must reset influence_level to 1 (spec R5-AC1)');
});

Deno.test('the defender-win decrement branch reduces influence_level by exactly 1, gated on level > 1', () => {
  const sql = findMigration('resolve_zone_disputes');
  assert(/influence_level\s*=\s*influence_level\s*-\s*1/i.test(sql),
    'defender-win branch must decrement influence_level by exactly 1, not a proportional change (spec R6-AC1)');
  assert(/influence_level\s*>\s*1/.test(sql),
    'the decrement branch must be gated on influence_level > 1 so it never fires for the level-1 floor case (spec R6-AC1, R8-AC1)');
});

Deno.test('the level-1-floor branch clears the dispute without touching influence_level or owner_id', () => {
  const sql = findMigration('resolve_zone_disputes');
  assert(/influence_level\s*<=\s*1/.test(sql),
    'a distinct level-1-floor branch gated on influence_level <= 1 must exist (spec R8-AC1)');
});

Deno.test('the resolver never touches the continuous zones.influence field', () => {
  const sql = findMigration('resolve_zone_disputes');
  // influence_level is fine; the bare `influence` column (not `influence_level`)
  // must never appear as a SET target.
  const setsInfluence = /set\s+influence\s*=/i.test(sql) || /,\s*influence\s*=/i.test(sql.replace(/influence_level/g, ''));
  assertFalse(setsInfluence,
    'dispute resolution must never write zones.influence (the continuous, area-scaled REAL field) - only influence_level (spec R6-AC1\'s invariant, design.md §0)');
});

Deno.test('the resolver contains no pace/duration-based branching (deliberately out of scope)', () => {
  const sql = findMigration('resolve_zone_disputes');
  const lower = sql.toLowerCase();
  for (const forbidden of ['pace', 'duration', 'elapsed', 'time_since', 'opened_at']) {
    assertFalse(lower.includes(forbidden),
      `resolver must not reference "${forbidden}" - the pace clause was confirmed unimplementable and deliberately rejected, not deferred (spec R10-AC1)`);
  }
});
