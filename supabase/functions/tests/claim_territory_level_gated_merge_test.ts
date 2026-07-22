// supabase/functions/tests/claim_territory_level_gated_merge_test.ts
//
// RED phase - same-owner adjacent zones only merge into one geometric row
// when their influence_level also matches, in addition to the existing
// 25m proximity test. Targets the pure-utility module
// ../claim_territory/merge_geometry.ts. ZoneInput does not yet declare an
// influenceLevel field, so every test below fails to compile until the
// implementation lands (excess-property check on the literal returned from
// the zone() helper, typed as ZoneInput).
//
// Kept mock-free per the project's >5-mocks-escalate rule, mirroring
// claim_territory_merge_test.ts's existing geometry-only test style.
//
// Run: npx deno test supabase/functions/tests/claim_territory_level_gated_merge_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeZoneMerges, type ZoneInput } from '../claim_territory/merge_geometry.ts';

const LAT0 = 39.470000; // Valencia
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

const THRESHOLD_M = 25;
const D_LAT_40M = 40 / LAT_M;
const D_LNG_40M = 40 / LNG_M;

function squareRing(lng0: number, lat0: number): [number, number][] {
  const a: [number, number] = [lng0, lat0];
  const b: [number, number] = [lng0 + D_LNG_40M, lat0];
  const c: [number, number] = [lng0 + D_LNG_40M, lat0 + D_LAT_40M];
  const d: [number, number] = [lng0, lat0 + D_LAT_40M];
  return [a, b, c, d, a];
}

// Typed as ZoneInput explicitly so the returned object literal is subject to
// excess-property checking against the CURRENT (pre-implementation)
// interface, which does not declare influenceLevel yet.
function zone(
  id: string,
  lng0: number,
  lat0: number,
  createdAt: string,
  influenceLevel: number,
): ZoneInput {
  return { id, ring: squareRing(lng0, lat0), createdAt, influenceLevel };
}

Deno.test('two touching same-owner zones at the SAME influence level merge into one row', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z', 2);
  const z2 = zone('z2', 33.000000 + D_LNG_40M, LAT0, '2026-01-02T00:00:00Z', 2);

  const groups = computeZoneMerges([z1, z2], THRESHOLD_M);

  assertEquals(groups.length, 1,
    'Two touching, equal-level zones must still form exactly one merge group');
  assertEquals(groups[0].survivorId, 'z1');
  assertEquals(groups[0].absorbedIds, ['z2']);
});

Deno.test('two touching same-owner zones at DIFFERENT influence levels do not merge', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z', 2);
  const z2 = zone('z2', 33.000000 + D_LNG_40M, LAT0, '2026-01-02T00:00:00Z', 1);

  const groups = computeZoneMerges([z1, z2], THRESHOLD_M);

  assertEquals(groups.length, 0,
    'An unequal-level pair within the proximity threshold must never be reported as a merge group, '
      + 'even though they are close enough to merge under the pre-existing distance-only rule');
});

Deno.test(
  'a three-zone chain merges the equal-level pair transitively and excludes the different-level outlier',
  () => {
    // z1-z2 touch and share level 1; z2-z3 touch but z3 is level 3. The
    // level gate must be applied per-link inside union-find (not as a
    // post-hoc filter on the whole connected component), so z1+z2 merge
    // while z3 stays out entirely - even though z1-z2-z3 would all be one
    // connected component under distance alone.
    const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z', 1);
    const z2 = zone('z2', 33.000000 + D_LNG_40M, LAT0, '2026-01-02T00:00:00Z', 1);
    const z3 = zone('z3', 33.000000 + 2 * D_LNG_40M, LAT0, '2026-01-03T00:00:00Z', 3);

    const groups = computeZoneMerges([z1, z2, z3], THRESHOLD_M);

    assertEquals(groups.length, 1,
      'Only the equal-level z1/z2 pair may form a merge group');
    assertEquals(groups[0].survivorId, 'z1');
    assertEquals(groups[0].absorbedIds, ['z2']);
    const mergedIds = new Set([groups[0].survivorId, ...groups[0].absorbedIds]);
    assertEquals(mergedIds.has('z3'), false,
      'The different-level zone must never appear in any merge group, including transitively');
  },
);
