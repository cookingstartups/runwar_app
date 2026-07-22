// supabase/functions/tests/claim_territory_multi_loop_union_test.ts
//
// Covers the server-side guarantee behind the client change that dispatches
// one claim_territory call per closed loop when a single run closes MULTIPLE
// loops (union-of-all-loops behavior): the server does not compute captures
// from raw trails - it gates one ring per claim (evaluateCapturedRingGates:
// area floor 1500 sqm always, diagonal/compactness only behind
// kEnforceShapeGates, which defaults to false) and merges same-owner
// adjacent/overlapping zones (computeZoneMerges). This file proves:
//
//   1. Three overlapping/adjacent rings from one run - a small loop, a mid
//      loop, and a big excursion loop that overlaps both - each individually
//      clear the capture gate on their own.
//   2. A thin, elongated ring (the kind a multi-loop run can produce) clears
//      the same gate by area alone while kEnforceShapeGates is false, and is
//      rejected once the flag is forced on - the flag boundary, same pattern
//      as claim_territory_shape_gate_flag_test.ts.
//   3. Feeding the three loops from (1) into computeZoneMerges as same-owner
//      ZoneInput rows, at the production merge threshold (25 m, matching
//      handler.ts's kMergeThresholdMeters), unions all three into ONE
//      merge group - one held zone, not three.
//
// Run: ~/.deno/bin/deno test --allow-all --cached-only supabase/functions/tests/claim_territory_multi_loop_union_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { evaluateCapturedRingGates } from '../claim_territory/handler.ts';
import { computeZoneMerges, type ZoneInput } from '../claim_territory/merge_geometry.ts';

// ---------------------------------------------------------------------------
// Geometry test helpers (test-only - not the production algorithm under
// test). Same city-scale local-metres projection convention as
// claim_territory_merge_test.ts, kept self-contained rather than imported.
// ---------------------------------------------------------------------------

const LNG0 = 33.000000;
const LAT0 = 39.470000; // Valencia
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

function mLng(meters: number): number {
  return meters / LNG_M;
}
function mLat(meters: number): number {
  return meters / LAT_M;
}

// Axis-aligned rectangle ring, x0/y0/w/h in local metres offset from
// (LNG0, LAT0). Closed ring (first point repeated), same winding order as
// claim_territory_merge_test.ts's squareRing.
function rectRing(x0: number, y0: number, w: number, h: number): number[][] {
  const a: [number, number] = [LNG0 + mLng(x0), LAT0 + mLat(y0)];
  const b: [number, number] = [LNG0 + mLng(x0 + w), LAT0 + mLat(y0)];
  const c: [number, number] = [LNG0 + mLng(x0 + w), LAT0 + mLat(y0 + h)];
  const d: [number, number] = [LNG0 + mLng(x0), LAT0 + mLat(y0 + h)];
  return [a, b, c, d, a];
}

// The merge threshold constant handler.ts passes into computeZoneMerges
// (kMergeThresholdMeters), duplicated here as a literal - this file has no
// import of handler.ts's private module-level constants.
const MERGE_THRESHOLD_M = 25;

// ---------------------------------------------------------------------------
// One run, three closed loops: a small loop, a mid loop, and a big
// excursion loop that overlaps both smaller ones. Each is well over the
// 1500 sqm area floor. The big ring overlaps each smaller ring; the small
// and mid rings do not touch each other directly, so they only end up in
// the same merge group transitively through the big ring - same pattern as
// the L-shaped transitive-merge fixture in claim_territory_merge_test.ts.
// ---------------------------------------------------------------------------

// 50m x 50m -> 2500 sqm.
const SMALL_LOOP_RING = rectRing(0, 0, 50, 50);
// 100m x 100m -> 10000 sqm. x:[150,250] y:[80,180] - does not touch the
// small loop (x:[0,50] y:[0,50]) but does overlap the big loop below.
const MID_LOOP_RING = rectRing(150, 80, 100, 100);
// 200m x 200m -> 40000 sqm. x:[40,240] y:[-60,140] - overlaps the small
// loop at x:[40,50] y:[0,50] and the mid loop at x:[150,240] y:[80,140].
const BIG_LOOP_RING = rectRing(40, -60, 200, 200);

// A thin, elongated ring in the shape a multi-loop run's excursion leg can
// leave behind: 20m x 160m (about 1:8), area 3200 sqm (clears the 1500 sqm
// area floor), diagonal ~161.2m (clears the 30m diagonal floor), compactness
// (area / diagonal^2) ~0.123 - below the 0.15 compactness floor, so this
// ring is accepted with shape gates off and rejected with them forced on.
// A 1:6 rectangle keeps a constant compactness of 6/37 ~ 0.162 regardless of
// size (compactness of a w x r*w rectangle is r/(1+r^2), scale-invariant),
// which stays above the 0.15 floor even with shape gates enforced - the
// ratio here is picked steeper so the enforced-flag branch is actually
// exercised, not so it merely resembles the 1:6 case.
const ELONGATED_MULTI_LOOP_RING = rectRing(500, 500, 20, 160);

Deno.test('a run closing a small loop, a mid loop, and a big overlapping excursion loop clears the capture gate on every loop', () => {
  const small = evaluateCapturedRingGates(SMALL_LOOP_RING);
  const mid = evaluateCapturedRingGates(MID_LOOP_RING);
  const big = evaluateCapturedRingGates(BIG_LOOP_RING);

  assertEquals(small.passed, true, 'the small loop must individually clear the capture gate');
  assertEquals(mid.passed, true, 'the mid loop must individually clear the capture gate');
  assertEquals(big.passed, true, 'the big overlapping loop must individually clear the capture gate');

  assertEquals(small.areaSqm > 1500, true);
  assertEquals(mid.areaSqm > 1500, true);
  assertEquals(big.areaSqm > 1500, true);
});

Deno.test('default (shape gates OFF): a thin elongated multi-loop-style ring clears the gate on area alone', () => {
  const result = evaluateCapturedRingGates(ELONGATED_MULTI_LOOP_RING);
  assertEquals(result.passed, true,
    'with shape gates off, no shape floor can drop a loop that clears the area floor');
  assertEquals((result.areaSqm ?? 0) > 1500, true);
});

Deno.test('shape gates ON: the same elongated multi-loop-style ring is REJECTED (too_short)', () => {
  const result = evaluateCapturedRingGates(ELONGATED_MULTI_LOOP_RING, true);
  assertEquals(result.passed, false,
    'forcing the flag on documents the boundary: this ring only survives while the flag is off');
  assertEquals(result.reason, 'too_short');
  // Area and diagonal both clear their own floors; compactness is what
  // actually fails, proving this rejects for the right reason.
  assertEquals((result.areaSqm ?? 0) > 1500, true);
  assertEquals((result.diagonalM ?? 0) > 30, true);
  assertEquals((result.compactness ?? 1) < 0.15, true);
});

Deno.test('the three loops from one run union into a single held zone via computeZoneMerges', () => {
  const inputs: ZoneInput[] = [
    { id: 'small', ring: SMALL_LOOP_RING, createdAt: '2026-01-01T00:00:00Z' },
    { id: 'mid', ring: MID_LOOP_RING, createdAt: '2026-01-01T00:00:05Z' },
    { id: 'big', ring: BIG_LOOP_RING, createdAt: '2026-01-01T00:00:10Z' },
  ];

  const groups = computeZoneMerges(inputs, MERGE_THRESHOLD_M);

  assertEquals(groups.length, 1,
    'three same-owner loops from one run, chained through the overlapping big loop, must collapse into exactly one merge group');
  const group = groups[0];
  assertEquals(group.survivorId, 'small', 'the oldest loop (claimed first) must survive the merge');
  assertEquals(new Set(group.absorbedIds), new Set(['mid', 'big']),
    'the mid and big loops must both be absorbed into the one surviving holding');
});
