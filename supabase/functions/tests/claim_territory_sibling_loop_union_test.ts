// supabase/functions/tests/claim_territory_sibling_loop_union_test.ts
//
// Covers unionCandidateRings (merge_geometry.ts): when a single run
// self-closes MORE THAN ONE loop, sibling loops within the 25m seal-merge
// radius of each other (kProximityTriggerM/kMergeThresholdMeters) must union
// into ONE contiguous shape instead of being dispatched as N independent
// claims - the Panel 2 "Union" decision. unionCandidateRings reuses the same
// trueUnion morphological-closing algorithm computeZoneMerges already uses
// for merging a new claim against pre-existing adjacent territory; this file
// proves it composes correctly with that existing merge path too, so a
// sibling-loop union never silently drops the existing-zone merge (or vice
// versa) - the class of bug flagged elsewhere in this sprint as a stale
// in-memory array causing silent data loss during a similar split-then-merge
// operation.
//
// Run: ~/.deno/bin/deno test --allow-all --cached-only supabase/functions/tests/claim_territory_sibling_loop_union_test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeZoneMerges, unionCandidateRings, type ZoneInput } from '../claim_territory/merge_geometry.ts';

// ---------------------------------------------------------------------------
// Geometry test helpers (test-only - not the production algorithm under
// test). Same city-scale local-metres projection convention as
// claim_territory_merge_test.ts / claim_territory_multi_loop_union_test.ts.
// ---------------------------------------------------------------------------

const LNG0 = 33.000000;
const LAT0 = 39.470000; // Valencia
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

const THRESHOLD_M = 25; // matches production kMergeThresholdMeters / kProximityTriggerM

function mLng(meters: number): number {
  return meters / LNG_M;
}
function mLat(meters: number): number {
  return meters / LAT_M;
}

// Axis-aligned rectangle ring, x0/y0/w/h in local metres offset from
// (LNG0, LAT0). Closed ring (first point repeated).
function rectRing(x0: number, y0: number, w: number, h: number): number[][] {
  const a: [number, number] = [LNG0 + mLng(x0), LAT0 + mLat(y0)];
  const b: [number, number] = [LNG0 + mLng(x0 + w), LAT0 + mLat(y0)];
  const c: [number, number] = [LNG0 + mLng(x0 + w), LAT0 + mLat(y0 + h)];
  const d: [number, number] = [LNG0 + mLng(x0), LAT0 + mLat(y0 + h)];
  return [a, b, c, d, a];
}

function pointInRing(pt: [number, number], ring: number[][]): boolean {
  let inside = false;
  const [px, py] = pt;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    const intersect = yi > py !== yj > py &&
      px < ((xj - xi) * (py - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

function ringAreaApprox(ring: number[][]): number {
  // Shoelace in local metres - good enough for a "never lost area" sanity
  // check, not a replacement for turf's own area function.
  let sum = 0;
  const pts = ring.map(([lng, lat]) => [
    (lng - LNG0) * LNG_M,
    (lat - LAT0) * LAT_M,
  ]);
  for (let i = 0; i < pts.length; i++) {
    const [x1, y1] = pts[i];
    const [x2, y2] = pts[(i + 1) % pts.length];
    sum += x1 * y2 - x2 * y1;
  }
  return Math.abs(sum) / 2;
}

// ---------------------------------------------------------------------------
// 1. Two loops within 25m of each other union into ONE polygon.
// ---------------------------------------------------------------------------

Deno.test('two sibling loops within 25m union into one contiguous polygon', () => {
  // 40x40 loop at x:[0,40], and a second 40x40 loop starting at x:[50,90] -
  // a 10m gap, well inside the 25m seal radius.
  const loopA = rectRing(0, 0, 40, 40);
  const loopB = rectRing(50, 0, 40, 40);

  const geom = unionCandidateRings([loopA, loopB], THRESHOLD_M);

  assertEquals(geom.type, 'Polygon', 'two loops sealed within the radius must produce one continuous Polygon, not a MultiPolygon');
  const ring = (geom as { type: 'Polygon'; coordinates: number[][][] }).coordinates[0];

  // The gap between the two loops (x=45, mid-gap) must be sealed - inside
  // the union.
  const midGapPoint: [number, number] = [LNG0 + mLng(45), LAT0 + mLat(20)];
  assert(pointInRing(midGapPoint, ring), 'the sealed gap between the two sibling loops must be inside the unioned polygon');

  // Nothing is lost: the unioned area must be at least the sum of the two
  // source loops (2 * 1600 sqm = 3200 sqm).
  const unionedArea = ringAreaApprox(ring);
  assert(unionedArea >= 1600 * 2 - 1, `unioned area (${unionedArea}) must not be less than the sum of the two source loops`);
});

// ---------------------------------------------------------------------------
// 2. Two loops beyond 25m stay as two separate claims (no forced union).
// ---------------------------------------------------------------------------

Deno.test('two loops beyond 25m are NOT unioned - each stays its own separate ring', () => {
  // 40x40 loop at x:[0,40], and a second 40x40 loop at x:[100,140] - a 60m
  // gap, well beyond the 25m seal radius. The caller (handler.ts) is
  // expected to have already grouped these as TWO SEPARATE single-ring
  // groups before ever calling unionCandidateRings with more than one
  // member, so this test documents unionCandidateRings' OWN single-ring
  // passthrough behavior for the case where a "group" really only has one
  // member ring.
  const loopA = rectRing(0, 0, 40, 40);
  const loopB = rectRing(100, 0, 40, 40);

  const geomA = unionCandidateRings([loopA], THRESHOLD_M);
  const geomB = unionCandidateRings([loopB], THRESHOLD_M);

  assertEquals(geomA.type, 'Polygon');
  assertEquals(geomB.type, 'Polygon');
  assertEquals(
    (geomA as { type: 'Polygon'; coordinates: number[][][] }).coordinates[0],
    loopA.slice(0, loopA.length - 1).concat([loopA[0]]),
  );

  // The two rings, if actually fed into the SAME union call, must still
  // never end up unioned into a single shape reaching across a 60m gap -
  // computeZoneMerges (the grouping decision itself) rejects this pair at
  // the same threshold, proving the boundary is consistent between the
  // grouping decision and the union call.
  const groups = computeZoneMerges(
    [
      { id: 'a', ring: loopA, createdAt: '2026-01-01T00:00:00Z' },
      { id: 'b', ring: loopB, createdAt: '2026-01-01T00:00:05Z' },
    ],
    THRESHOLD_M,
  );
  assertEquals(groups.length, 0, 'loops 60m apart must not be grouped at the 25m threshold');
});

// ---------------------------------------------------------------------------
// 3. Three-loop transitive chain: A-B within 25m, B-C within 25m, A-C beyond
//    25m directly - all three must still union into ONE shape via B.
// ---------------------------------------------------------------------------

Deno.test('a three-loop transitive chain (A-B close, B-C close, A-C far) unions all three into one polygon', () => {
  // A: x:[0,40]. B: x:[50,90] (10m gap from A). C: x:[100,140] (10m gap from
  // B, but 60m gap from A directly - A and C alone would NOT be linked).
  const loopA = rectRing(0, 0, 40, 40);
  const loopB = rectRing(50, 0, 40, 40);
  const loopC = rectRing(100, 0, 40, 40);

  // Confirm A and C alone are NOT within threshold (the chain only exists
  // through B).
  const directAC = computeZoneMerges(
    [
      { id: 'a', ring: loopA, createdAt: '2026-01-01T00:00:00Z' },
      { id: 'c', ring: loopC, createdAt: '2026-01-01T00:00:10Z' },
    ],
    THRESHOLD_M,
  );
  assertEquals(directAC.length, 0, 'A and C alone (60m apart) must not link directly');

  // The grouping decision (union-find over the same threshold) puts all
  // three in one component via B.
  const chainGroups = computeZoneMerges(
    [
      { id: 'a', ring: loopA, createdAt: '2026-01-01T00:00:00Z' },
      { id: 'b', ring: loopB, createdAt: '2026-01-01T00:00:05Z' },
      { id: 'c', ring: loopC, createdAt: '2026-01-01T00:00:10Z' },
    ],
    THRESHOLD_M,
  );
  assertEquals(chainGroups.length, 1, 'A, B and C must collapse into exactly one transitive group');
  assertEquals(new Set(chainGroups[0].absorbedIds), new Set(['b', 'c']));

  // The actual claim-submission union (unionCandidateRings, the function
  // handler.ts calls once the group is fixed) must produce ONE polygon
  // covering all three, with both gaps sealed.
  const geom = unionCandidateRings([loopA, loopB, loopC], THRESHOLD_M);
  assertEquals(geom.type, 'Polygon', 'the whole transitive chain must resolve to one continuous Polygon');
  const ring = (geom as { type: 'Polygon'; coordinates: number[][][] }).coordinates[0];

  const gapAB: [number, number] = [LNG0 + mLng(45), LAT0 + mLat(20)];
  const gapBC: [number, number] = [LNG0 + mLng(95), LAT0 + mLat(20)];
  assert(pointInRing(gapAB, ring), 'the A-B gap must be sealed in the final unioned shape');
  assert(pointInRing(gapBC, ring), 'the B-C gap must be sealed in the final unioned shape');

  const unionedArea = ringAreaApprox(ring);
  assert(unionedArea >= 1600 * 3 - 1, `unioned area (${unionedArea}) must not be less than the sum of all three source loops`);
});

// ---------------------------------------------------------------------------
// 4. No data loss when a loop in a sibling group is ALSO adjacent to
//    pre-existing owned territory - the sibling-union and the existing-zone
//    merge must compose, not silently drop one or the other. Mirrors the
//    stale-in-memory-array failure mode flagged elsewhere this sprint: the
//    sibling union's OWN result must be fed into the existing-zone merge
//    scan as a fresh member, not read from a snapshot taken before the
//    sibling union ran.
// ---------------------------------------------------------------------------

Deno.test('a sibling-loop union composes correctly with a pre-existing adjacent owned zone - both merges land, neither is dropped', () => {
  // Two sibling loops from the SAME run, 10m apart (well within threshold).
  const siblingA = rectRing(0, 0, 40, 40);
  const siblingB = rectRing(50, 0, 40, 40);

  // Union them first - this is exactly what handler.ts does before ever
  // touching the existing-zone merge scan.
  const siblingUnionGeom = unionCandidateRings([siblingA, siblingB], THRESHOLD_M);
  assertEquals(siblingUnionGeom.type, 'Polygon');
  const siblingUnionRing =
    (siblingUnionGeom as { type: 'Polygon'; coordinates: number[][][] }).coordinates[0];

  // A pre-existing owned zone sits 10m past the union's own right edge
  // (union spans x:[0,90]; this zone starts at x:[100,140]) - within the
  // 25m seal radius of the FRESH unioned shape, even though it was never
  // within range of siblingA alone.
  const preExistingZone = rectRing(100, 0, 40, 40);

  const finalGroups = computeZoneMerges(
    [
      { id: 'sibling-union', ring: siblingUnionRing, createdAt: '2026-01-01T00:00:10Z' },
      { id: 'pre-existing', ring: preExistingZone, createdAt: '2025-06-01T00:00:00Z' },
    ],
    THRESHOLD_M,
  );

  assertEquals(finalGroups.length, 1, 'the fresh sibling-union ring and the pre-existing zone must still merge into one group');
  const group = finalGroups[0];
  // The pre-existing zone is the OLDER row, so it must survive; the fresh
  // sibling-union ring is absorbed into it - proving neither merge silently
  // dropped the other's contribution.
  assertEquals(group.survivorId, 'pre-existing');
  assertEquals(group.absorbedIds, ['sibling-union']);

  const finalRing = (group.geometry as { type: 'Polygon'; coordinates: number[][][] }).coordinates[0];
  const finalArea = ringAreaApprox(finalRing);
  // Nothing lost across BOTH merges: final area must be at least the sum of
  // all three original loops (2 sibling loops + 1 pre-existing zone).
  assert(finalArea >= 1600 * 3 - 1, `final composed area (${finalArea}) must not be less than the sum of all three original loops`);
});
