// supabase/functions/tests/claim_territory_split_geometry_test.ts
//
// RED phase - real per-scenario geometry tests for the reversible split on
// a partial re-run of a fused zone. Targets a NEW pure export,
// computeZoneSplit(existingRing, newRing, minFragmentAreaSqm), which does
// not exist yet in ../claim_territory/merge_geometry.ts.
//
// Note for implementation: the design doc frames the split algorithm as
// logic embedded inline in index.ts's request handler, alongside the
// difference() call and the apply_zone_split RPC write. That framing is
// correct for the DB-write half (detecting the target row, issuing the
// RPC), which genuinely cannot be exercised without a live Supabase
// instance and stays covered by source-inspection wiring checks in
// claim_territory_split_wiring_test.ts. The classification and
// remainder-area math themselves, however, are ordinary pure geometry with
// no I/O, exactly like computeZoneMerges already is in this same file - so
// this test file specifies that math as a new exported function in
// merge_geometry.ts, mirroring the existing pure-utility pattern, rather
// than accepting symbol-presence checks as adequate coverage for it. This
// is a recommended interface addition, not something already promised by
// the design doc's file-by-file plan - flagged for confirmation before the
// implementation branch lands, otherwise this file stays red even after a
// behaviourally-correct inline implementation.
//
// Run: npx deno test supabase/functions/tests/claim_territory_split_geometry_test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeZoneSplit } from '../claim_territory/merge_geometry.ts';

const LAT0 = 39.470000; // Valencia
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

const MIN_FRAGMENT_AREA_SQM = 375.0;

function metresRing(lng0: number, lat0: number, widthM: number, heightM: number): number[][] {
  const dLng = widthM / LNG_M;
  const dLat = heightM / LAT_M;
  const a = [lng0, lat0];
  const b = [lng0 + dLng, lat0];
  const c = [lng0 + dLng, lat0 + dLat];
  const d = [lng0, lat0 + dLat];
  return [a, b, c, d, a];
}

Deno.test('a re-run covering roughly half of a fused zone splits off a remainder well above the sliver floor', () => {
  // Existing fused zone: 40x40m square (1600 sqm).
  const existingRing = metresRing(33.0, LAT0, 40, 40);
  // Re-run covers the left half only (20x40m = 800 sqm), a genuine partial
  // overlap - not a full re-enclosure of the whole existing zone.
  const reRunRing = metresRing(33.0, LAT0, 20, 40);

  const result = computeZoneSplit(existingRing, reRunRing, MIN_FRAGMENT_AREA_SQM);

  assertEquals(result.case, 'partialOverlap',
    'A re-run covering only part of the existing zone must be classified as a split, not a containment');
  assertEquals(result.remainderDiscarded, false,
    'The remaining half is well above the 375 sqm sliver floor and must be kept, not discarded');
  assert(result.remainder !== null, 'A kept remainder must carry actual geometry to write back');
});

Deno.test('a re-run that fully encloses the existing zone from outside is excluded from the split path', () => {
  const existingRing = metresRing(33.0, LAT0, 40, 40);
  // Re-run is a much larger ring that fully contains the existing zone -
  // this is the pre-existing ownedOverlapIds containment path (AC-14's
  // note), never the AC-7 split path.
  const reRunRing = metresRing(32.999, LAT0 - 0.0003, 200, 200);

  const result = computeZoneSplit(existingRing, reRunRing, MIN_FRAGMENT_AREA_SQM);

  assertEquals(result.case, 'fullContainment',
    'A re-run that fully encloses the existing zone must never be classified as a split case');
  assertEquals(result.remainder, null,
    'A full-containment case has no split remainder to write back at all');
});

Deno.test('a remainder below the sliver-tolerance floor is discarded, absorbing the whole prior area into the re-run', () => {
  const existingRing = metresRing(33.0, LAT0, 40, 40); // 1600 sqm
  // Re-run covers all but a thin 1m-wide strip of the existing zone -
  // remainder area is 1 x 40 = 40 sqm, far below the 375 sqm floor.
  const reRunRing = metresRing(33.0, LAT0, 39, 40);

  const result = computeZoneSplit(existingRing, reRunRing, MIN_FRAGMENT_AREA_SQM);

  assertEquals(result.case, 'partialOverlap');
  assertEquals(result.remainderDiscarded, true,
    'A remainder under 375 sqm must be discarded as geometric noise, not persisted as a near-zero row');
  assertEquals(result.remainder, null,
    'A discarded remainder carries no geometry to write back - the re-run absorbs the whole prior area');
});

Deno.test('a re-run that does not touch the existing zone at all is neither a split nor a containment', () => {
  const existingRing = metresRing(33.0, LAT0, 40, 40);
  const reRunRing = metresRing(33.01, LAT0, 40, 40); // far away, no overlap

  const result = computeZoneSplit(existingRing, reRunRing, MIN_FRAGMENT_AREA_SQM);

  assertEquals(result.case, 'noOverlap');
  assertEquals(result.remainder, null);
  assertEquals(result.remainderDiscarded, false);
});
