// supabase/functions/tests/claim_territory_merge_test.ts
//
// Single-rule merge-geometry contract (supersedes the earlier three-tier
// jitter-epsilon / no-bridging-below-25m design):
//
//   1. Adjacency = 25 METERS edge-to-edge proximity. Same-owner zones whose
//      boundaries are within 25m (touching OR gap < 25m) merge into ONE
//      zone; zones with a gap > 25m do not merge.
//   2. Merged geometry is always ONE continuous Polygon, sealed via a
//      morphological closing at the 25m scale (dilate 12.5m -> union ->
//      erode 12.5m):
//      - when sources physically touch/overlap: one Polygon respecting both
//        boundaries (the exact union, no buffer artifacts).
//      - when sources are within 25m but disjoint: the gap between them is
//        sealed shut, so a probe point in the mid-gap notch IS inside the
//        merged geometry (no MultiPolygon, no bridging left open).
//      - a notch wider than 25m (even between zones that end up in the same
//        transitive merge group via a third zone) is NOT captured - a probe
//        point placed there stays outside the merged geometry.
//      - probe points inside each source polygon must be inside the result.
//      - merged area is never LESS than the sum of source areas (nothing
//        lost) and never blows up past a loose upper bound of sum-of-areas
//        plus a 25m-deep seal along the shared frontier (no convex-hull
//        style inflation).
//   3. Oldest zone (by created_at) survives; absorbed ids are reported;
//      adjacency is transitive across the owner's whole zone set in the city.
//
// Targets the pure-utility module `../claim_territory/merge_geometry.ts`,
// exporting `computeZoneMerges`. Kept mock-free per the project's
// >5-mocks-escalate rule.
//
// Run: npx deno test supabase/functions/tests/claim_territory_merge_test.ts

import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeZoneMerges, type ZoneInput } from '../claim_territory/merge_geometry.ts';

// ---------------------------------------------------------------------------
// Geometry test helpers (test-only - not the production algorithm under test)
// ---------------------------------------------------------------------------

const LAT0 = 39.470000; // Valencia
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180); // ~85908

const THRESHOLD_M = 25; // matches production kMergeThresholdMeters / kProximityTriggerM

function mLng(meters: number): number {
  return meters / LNG_M;
}

function mLat(meters: number): number {
  return meters / LAT_M;
}

const D_LAT_40M = mLat(40);
const D_LNG_40M = mLng(40);
const GAP_20M_LNG = mLng(20);
const GAP_200M_LNG = mLng(200);

function squareRing(lng0: number, lat0: number): [number, number][] {
  const a: [number, number] = [lng0, lat0];
  const b: [number, number] = [lng0 + D_LNG_40M, lat0];
  const c: [number, number] = [lng0 + D_LNG_40M, lat0 + D_LAT_40M];
  const d: [number, number] = [lng0, lat0 + D_LAT_40M];
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

function pointInGeometry(
  pt: [number, number],
  geometry: { type: string; coordinates: unknown },
): boolean {
  if (geometry.type === 'Polygon') {
    const rings = geometry.coordinates as number[][][];
    return pointInRing(pt, rings[0]);
  }
  if (geometry.type === 'MultiPolygon') {
    const polys = geometry.coordinates as number[][][][];
    return polys.some((poly) => pointInRing(pt, poly[0]));
  }
  return false;
}

function ringAreaM2(ring: number[][]): number {
  // Shoelace on locally-projected metres (consistent with the codebase's
  // equirectangular approximation elsewhere, e.g. run_recorder_service.dart).
  const projected = ring.map(([lng, lat]) => [
    lng * LNG_M,
    lat * LAT_M,
  ]);
  let area = 0;
  for (let i = 0; i < projected.length; i++) {
    const [x1, y1] = projected[i];
    const [x2, y2] = projected[(i + 1) % projected.length];
    area += x1 * y2 - x2 * y1;
  }
  return Math.abs(area) / 2;
}

function geometryAreaM2(geometry: { type: string; coordinates: unknown }): number {
  if (geometry.type === 'Polygon') {
    const rings = geometry.coordinates as number[][][];
    return ringAreaM2(rings[0]);
  }
  const polys = geometry.coordinates as number[][][][];
  return polys.reduce((sum, poly) => sum + ringAreaM2(poly[0]), 0);
}

function zone(id: string, lng0: number, lat0: number, createdAt: string): ZoneInput {
  return { id, ring: squareRing(lng0, lat0), createdAt };
}

const AREA_EPSILON_M2 = 5.0;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test('touching zones merge into one true-union Polygon', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  // z2 starts exactly where z1's right edge ends -> shared edge, gap == 0.
  const z2 = zone('z2', 33.000000 + D_LNG_40M, LAT0, '2026-01-02T00:00:00Z');

  const groups = computeZoneMerges([z1, z2], THRESHOLD_M);

  assertEquals(groups.length, 1, 'Two touching zones must form exactly one merge group');
  const group = groups[0];
  assertEquals(group.survivorId, 'z1', 'The OLDEST zone (by created_at) must survive the merge');
  assertEquals(group.absorbedIds, ['z2']);
  assertEquals(group.geometry.type, 'Polygon',
    'Touching sources must resolve to a single true-union Polygon, not a MultiPolygon or hull');

  const area1 = ringAreaM2(z1.ring);
  const area2 = ringAreaM2(z2.ring);
  const mergedArea = geometryAreaM2(group.geometry);
  assert(mergedArea <= area1 + area2 + AREA_EPSILON_M2,
    'Merged area must not exceed the sum of source areas (no hull inflation)');
  assert(Math.abs(mergedArea - (area1 + area2)) < AREA_EPSILON_M2,
    'Disjoint-but-touching sources must merge to exactly the sum of their areas');

  const insideZ1: [number, number] = [33.000000 + D_LNG_40M / 2, LAT0 + D_LAT_40M / 2];
  const insideZ2: [number, number] = [
    33.000000 + D_LNG_40M + D_LNG_40M / 2,
    LAT0 + D_LAT_40M / 2,
  ];
  assert(pointInGeometry(insideZ1, group.geometry), 'A point inside source zone 1 must be inside the merged geometry');
  assert(pointInGeometry(insideZ2, group.geometry), 'A point inside source zone 2 must be inside the merged geometry');
});

Deno.test('zones within 25m but disjoint seal shut into one continuous Polygon, no MultiPolygon left', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  const z2Lng = 33.000000 + D_LNG_40M + GAP_20M_LNG;
  const z2 = zone('z2', z2Lng, LAT0, '2026-01-02T00:00:00Z');

  const groups = computeZoneMerges([z1, z2], THRESHOLD_M);

  assertEquals(groups.length, 1, 'Zones with a 20m gap (< 25m threshold) must merge');
  const group = groups[0];
  assertEquals(group.survivorId, 'z1');
  assertEquals(group.geometry.type, 'Polygon',
    'A gap within the closing radius must be sealed into a single continuous Polygon, never left as a MultiPolygon');

  const area1 = ringAreaM2(z1.ring);
  const area2 = ringAreaM2(z2.ring);
  const mergedArea = geometryAreaM2(group.geometry);
  const sharedFrontierM = 40; // both squares share the full 40m edge facing each other
  assert(mergedArea >= area1 + area2 - AREA_EPSILON_M2,
    'Sealing a gap must never lose area relative to the sum of the source zones');
  assert(mergedArea <= area1 + area2 + THRESHOLD_M * sharedFrontierM,
    'Sealing must stay a loose, bounded fill of the shared frontier at the closing scale, not a convex-hull-style inflation');

  // The gap midpoint must now be INSIDE the sealed geometry - the whole
  // point of the single-rule closing is that this notch is no longer open.
  const midGapLng = 33.000000 + D_LNG_40M + GAP_20M_LNG / 2;
  const midGapProbe: [number, number] = [midGapLng, LAT0 + D_LAT_40M / 2];
  assert(pointInGeometry(midGapProbe, group.geometry),
    'A probe point in the middle of a sealed (<25m) gap must be INSIDE the merged geometry');

  const insideZ1: [number, number] = [33.000000 + D_LNG_40M / 2, LAT0 + D_LAT_40M / 2];
  const insideZ2: [number, number] = [z2Lng + D_LNG_40M / 2, LAT0 + D_LAT_40M / 2];
  assert(pointInGeometry(insideZ1, group.geometry));
  assert(pointInGeometry(insideZ2, group.geometry));
});

Deno.test('zones with an edge-to-edge gap > 25m do not merge', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  const z2 = zone('z2', 33.000000 + D_LNG_40M + GAP_200M_LNG, LAT0, '2026-01-02T00:00:00Z');

  const groups = computeZoneMerges([z1, z2], THRESHOLD_M);

  assertEquals(groups.length, 0,
    'Zones ~200m apart (> 25m threshold) must never be reported as a merge group');
});

Deno.test('adjacency is transitive across the full owner/city zone set', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  const z2 = zone('z2', 33.000000 + D_LNG_40M, LAT0, '2026-01-02T00:00:00Z');
  const z3 = zone('z3', 33.000000 + 2 * D_LNG_40M, LAT0, '2026-01-03T00:00:00Z');

  const groups = computeZoneMerges([z1, z2, z3], THRESHOLD_M);

  assertEquals(groups.length, 1, 'A chain of pairwise-adjacent zones must collapse into one group');
  assertEquals(groups[0].survivorId, 'z1', 'The oldest zone in the connected group must survive');
  assertEquals(new Set(groups[0].absorbedIds), new Set(['z2', 'z3']));
});

Deno.test('a notch wider than 25m inside a transitively-merged L-shaped group stays uncaptured', () => {
  // z1 and z3 sit diagonally across from each other, each individually
  // linked to z2 (22m gaps, under the 25m threshold) but ~31m apart from
  // each other at the nearest corners - so they land in the same merge
  // group only transitively, through z2. The concave pocket between z1 and
  // z3 must NOT be sealed by the closing, since no pairwise boundary
  // distance across that notch is within 25m.
  const GAP_22M = 22;
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  const z2 = zone(
    'z2',
    33.000000,
    LAT0 + D_LAT_40M + mLat(GAP_22M),
    '2026-01-02T00:00:00Z',
  );
  const z3 = zone(
    'z3',
    33.000000 + D_LNG_40M + mLng(GAP_22M),
    LAT0 + D_LAT_40M + mLat(GAP_22M),
    '2026-01-03T00:00:00Z',
  );

  const groups = computeZoneMerges([z1, z2, z3], THRESHOLD_M);

  assertEquals(groups.length, 1, 'z1-z2-z3 must collapse into one transitively-merged group');
  const group = groups[0];
  assertEquals(group.survivorId, 'z1');
  assertEquals(new Set(group.absorbedIds), new Set(['z2', 'z3']));
  assertEquals(group.geometry.type, 'Polygon',
    'The merged L-shape must still be one continuous Polygon (connected through z2), even with an open notch');

  // Pocket center: ~11m diagonally out from z1's top-right corner, ~15.6m
  // from the nearest boundary of each of z1, z2 and z3 - outside all three
  // 12.5m dilations, so it must stay outside the sealed result.
  const notchProbe: [number, number] = [
    33.000000 + D_LNG_40M + mLng(11),
    LAT0 + D_LAT_40M + mLat(11),
  ];
  assert(!pointInGeometry(notchProbe, group.geometry),
    'A probe point in a >25m-wide notch must stay OUTSIDE the merged geometry, even inside a transitively-merged group');

  const insideZ1: [number, number] = [33.000000 + D_LNG_40M / 2, LAT0 + D_LAT_40M / 2];
  const insideZ2: [number, number] = [
    33.000000 + D_LNG_40M / 2,
    LAT0 + D_LAT_40M + mLat(GAP_22M) + D_LAT_40M / 2,
  ];
  const insideZ3: [number, number] = [
    33.000000 + D_LNG_40M + mLng(GAP_22M) + D_LNG_40M / 2,
    LAT0 + D_LAT_40M + mLat(GAP_22M) + D_LAT_40M / 2,
  ];
  assert(pointInGeometry(insideZ1, group.geometry), 'A point inside source zone 1 must be inside the merged geometry');
  assert(pointInGeometry(insideZ2, group.geometry), 'A point inside source zone 2 must be inside the merged geometry');
  assert(pointInGeometry(insideZ3, group.geometry), 'A point inside source zone 3 must be inside the merged geometry');
});
