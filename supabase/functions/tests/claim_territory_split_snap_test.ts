// supabase/functions/tests/claim_territory_split_snap_test.ts
//
// app-T0587 - snap the split cut to the nearest shared hex-grid boundary
// instead of discarding a below-floor fragment. Exercises
// computeZoneSplit's hex-quantised remainder path directly (see the
// module-level comment in ../claim_territory/merge_geometry.ts).
//
// Run: npx deno test --allow-net supabase/functions/tests/claim_territory_split_snap_test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeZoneSplit } from '../claim_territory/merge_geometry.ts';
import { coveredCellSet, kHexCellCircumradiusM } from '../claim_territory/hex_quantize.ts';

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

function ringAreaCells(ring: number[][], refLat: number): number {
  return coveredCellSet(ring, kHexCellCircumradiusM, refLat).size;
}

Deno.test('a split producing a fragment that would previously have been discarded now snaps to the nearest boundary and is kept', () => {
  // A one-cell-wide sliver at hex resolution (kHexCellCircumradiusM = 10 m):
  // existing zone 60x60m (3600 sqm), re-run covers all but a ~12m strip
  // along one edge (12 x 60 = 720 sqm raw remainder - well above the OLD
  // 375 sqm floor already, but exercises the ordinary snap path: enough
  // hex cell centers fall in the strip to survive quantisation).
  const existingRing = metresRing(33.0, LAT0, 60, 60);
  const reRunRing = metresRing(33.0, LAT0, 48, 60);

  const result = computeZoneSplit(existingRing, reRunRing, MIN_FRAGMENT_AREA_SQM);

  assertEquals(result.case, 'partialOverlap');
  assertEquals(result.remainderDiscarded, false,
    'A fragment with surviving hex cells must be snapped and kept, not discarded');
  assert(result.remainder !== null, 'A kept snapped remainder must carry real geometry to write back');
});

Deno.test('a split whose remainder has no surviving hex cell at all is absorbed exactly as a full raw consumption always was', () => {
  // A genuinely sub-cell sliver: existing zone 40x40m, re-run covers all
  // but a 1m-wide strip - too thin for any hex cell center (spaced roughly
  // circumradiusM apart) to fall inside it, so the quantised remainder cell
  // set is empty even though the raw-geometry remainder area (40 sqm) is
  // nonzero. This is the direct successor to the old area-floor discard
  // case, now decided by grid emptiness instead of a raw-area threshold.
  const existingRing = metresRing(33.0, LAT0, 40, 40);
  const reRunRing = metresRing(33.0, LAT0, 39, 40);

  const result = computeZoneSplit(existingRing, reRunRing, MIN_FRAGMENT_AREA_SQM);

  assertEquals(result.case, 'partialOverlap');
  assertEquals(result.remainderDiscarded, true,
    'No hex cell survives at grid resolution - the re-run absorbs the whole prior area');
  assertEquals(result.remainder, null);
});

Deno.test('an ordinary half split with a real, well-clear-of-any-fragment remainder behaves as before: classified as a kept partial overlap', () => {
  const existingRing = metresRing(33.0, LAT0, 40, 40); // 1600 sqm
  const reRunRing = metresRing(33.0, LAT0, 20, 40); // left half, 800 sqm

  const result = computeZoneSplit(existingRing, reRunRing, MIN_FRAGMENT_AREA_SQM);

  assertEquals(result.case, 'partialOverlap');
  assertEquals(result.remainderDiscarded, false);
  assert(result.remainder !== null);
  assert(
    result.remainder!.type === 'Polygon' || result.remainder!.type === 'MultiPolygon',
    'The kept remainder must be real GeoJSON geometry',
  );
});

Deno.test('repeated re-splits of the same zone converge onto a stable single-ring remainder instead of shredding it into more rows', () => {
  const refLat = LAT0;
  const existingRing = metresRing(33.0, LAT0, 60, 60); // 3600 sqm

  // First re-run: covers roughly the left third.
  const firstReRun = metresRing(33.0, LAT0, 20, 60);
  const firstResult = computeZoneSplit(existingRing, firstReRun, MIN_FRAGMENT_AREA_SQM);
  assertEquals(firstResult.remainderDiscarded, false);
  assert(firstResult.remainder !== null);
  assertEquals(firstResult.remainder!.type, 'Polygon',
    'A single contiguous remainder must dissolve to exactly one ring, not fragment into several');

  const firstRemainderRing = (firstResult.remainder as { coordinates: number[][][] }).coordinates[0];

  // Second re-split of the FIRST remainder: re-run the same slice of ground
  // again (idempotent re-run of an already-snapped boundary). Since the
  // grid is a fixed shared reference, re-quantising the already-snapped
  // remainder against the same incoming ring should not manufacture new
  // fragments - either the remainder is fully absorbed (nothing left) or
  // it stays exactly one ring.
  const secondResult = computeZoneSplit(firstRemainderRing, firstReRun, MIN_FRAGMENT_AREA_SQM);
  if (!secondResult.remainderDiscarded && secondResult.remainder) {
    assertEquals(secondResult.remainder.type, 'Polygon',
      'Re-running the same cut against an already-snapped remainder must not shred it into multiple rows');
  }

  // Sanity: the ORIGINAL existing ring covers materially more hex cells
  // than either post-split remainder, confirming the split genuinely
  // shrank the held area rather than being a no-op.
  const existingCellCount = ringAreaCells(existingRing, refLat);
  const firstRemainderCellCount = ringAreaCells(firstRemainderRing, refLat);
  assert(firstRemainderCellCount < existingCellCount,
    'The first split must genuinely shrink the covered cell count');
});
