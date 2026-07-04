// supabase/functions/tests/claim_territory_merge_wiring_test.ts
//
// RED phase - R2-AC1 invariant (never merge across owners/cities), R2's
// disputed-exclusion edge case, and Q2's oldest-survivor ordering. These are
// source-inspection checks against index.ts's call-site wiring (query scope,
// guard conditions) rather than the pure geometry algorithm covered by
// claim_territory_merge_test.ts - the DB query filters themselves are only
// meaningfully verifiable by reading the actual Supabase query construction,
// not by a mocked client (which would just echo back whatever the test
// asserts). This mirrors the Dart source-inspection precedent in
// test/connectivity_gate_outbox_test.dart.
//
// Run: npx deno test supabase/functions/tests/claim_territory_merge_wiring_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC_PATH = new URL('../claim_territory/index.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

Deno.test('R2-AC1 invariant: the merge candidate query scopes to owner_id AND city', () => {
  const src = readSrc();
  assert(src.includes("eq('owner_id'"),
    "The merge query must filter .eq('owner_id', playerId) so merges never cross owners");
  assert(src.includes("eq('city'"),
    "The merge query must filter .eq('city', city) so merges never cross cities");
});

Deno.test('Q2: merge candidates are ordered oldest-first so the surviving id is well-defined', () => {
  const src = readSrc();
  assert(src.includes("order('created_at'"),
    'The merge query must order by created_at so "oldest survives" is well-defined, not query-order-dependent');
});

Deno.test('R2 edge case: merge never runs for a disputed outcome', () => {
  const src = readSrc();
  assert(src.includes('mergeAdjacentZones') || src.includes('computeZoneMerges'),
    'index.ts must call the merge routine for claimed/conquered outcomes');
  const mergeCallIdx = src.search(/mergeAdjacentZones|computeZoneMerges/);
  assert(mergeCallIdx >= 0);
  const disputedGuardIdx = src.lastIndexOf('disputedId', mergeCallIdx);
  assert(disputedGuardIdx >= 0 && disputedGuardIdx < mergeCallIdx,
    'The merge call must be guarded so it never runs when this claim resolved to disputed (e.g. `if (!disputedId)`)');
});

Deno.test('R2 response contract: claimed/conquered responses expose merged, absorbed_zone_ids, zone_geom_json', () => {
  const src = readSrc();
  assert(src.includes('merged'), 'Response must include the new `merged` boolean field');
  assert(src.includes('absorbed_zone_ids'), 'Response must include the new `absorbed_zone_ids` field');
  assert(src.includes('zone_geom_json'), 'Response must include the new `zone_geom_json` field');
});
