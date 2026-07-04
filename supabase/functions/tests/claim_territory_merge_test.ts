// supabase/functions/tests/claim_territory_merge_test.ts
//
// RED phase - R2-AC1, R2-AC2, R2-AC3 (adjacent-zone expansion), plus the
// corrected merge-geometry contract (operator correction, supersedes the
// bbox-proximity / convex-hull wording in the current design.md draft):
//
//   1. Adjacency = 50 METERS edge-to-edge proximity (not the old 166m bbox
//      tolerance, not a 5m epsilon). Zones whose boundaries are within 50m
//      (touching OR gap < 50m) merge; zones with a gap > 50m do not.
//   2. Merged geometry is a TRUE union, never a convex hull:
//      - when sources physically touch/overlap: one Polygon respecting both
//        boundaries.
//      - when sources are within 50m but disjoint: the surviving zone id
//        stores BOTH outlines as a MultiPolygon - no bridging geometry.
//      - a probe point in the notch/gap between two disjoint-but-near
//        sources (which a convex hull would incorrectly swallow) must NOT
//        be inside the merged geometry.
//      - probe points inside each source polygon must be inside the result.
//      - merged area <= sum of source areas + a small epsilon (equality
//        when sources are disjoint/touching, since no true overlap exists
//        in these fixtures).
//   3. Oldest zone (by created_at) survives; absorbed ids are reported;
//      adjacency is transitive across the owner's whole zone set in the city.
//
// This test targets a NEW pure-utility module,
// `../claim_territory/merge_geometry.ts`, exporting `computeZoneMerges`.
// It does not exist yet (the merge logic in design.md's draft is currently
// entangled with live Supabase reads/writes inside index.ts) - extracting it
// as a pure function keeps this suite mock-free, per the project's
// >5-mocks-escalate rule. Every test below fails at import resolution
// ("Module not found") until that module is created.
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

const D_LAT_40M = 40 / LAT_M; // ~0.0003618
const D_LNG_40M = 40 / LNG_M; // ~0.0004657
const GAP_20M_LNG = 20 / LNG_M; // ~0.0002328
const GAP_200M_LNG = 200 / LNG_M; // ~0.0023277

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

Deno.test('R2 corrected contract: touching zones merge into one true-union Polygon', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  // z2 starts exactly where z1's right edge ends -> shared edge, gap == 0.
  const z2 = zone('z2', 33.000000 + D_LNG_40M, LAT0, '2026-01-02T00:00:00Z');

  const groups = computeZoneMerges([z1, z2], 50);

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

Deno.test('R2 corrected contract: zones within 50m but disjoint merge as a MultiPolygon, no bridging geometry', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  const z2Lng = 33.000000 + D_LNG_40M + GAP_20M_LNG;
  const z2 = zone('z2', z2Lng, LAT0, '2026-01-02T00:00:00Z');

  const groups = computeZoneMerges([z1, z2], 50);

  assertEquals(groups.length, 1, 'Zones with a 20m gap (< 50m threshold) must still merge');
  const group = groups[0];
  assertEquals(group.survivorId, 'z1');
  assertEquals(group.geometry.type, 'MultiPolygon',
    'Disjoint sources within the threshold must be stored as a MultiPolygon (both outlines), never bridged into one ring');

  const area1 = ringAreaM2(z1.ring);
  const area2 = ringAreaM2(z2.ring);
  const mergedArea = geometryAreaM2(group.geometry);
  assert(Math.abs(mergedArea - (area1 + area2)) < AREA_EPSILON_M2,
    'A MultiPolygon merge must total exactly the sum of the disjoint source areas (no bridging fill)');

  // The notch between the two squares - inside the gap, and inside what a
  // convex hull would have swallowed, but must NOT be inside the true
  // MultiPolygon union.
  const notchLng = 33.000000 + D_LNG_40M + GAP_20M_LNG / 2;
  const notchProbe: [number, number] = [notchLng, LAT0 + D_LAT_40M / 2];
  assert(!pointInGeometry(notchProbe, group.geometry),
    'A probe point in the gap/notch between two disjoint sources must NOT be inside the merged geometry');

  const insideZ1: [number, number] = [33.000000 + D_LNG_40M / 2, LAT0 + D_LAT_40M / 2];
  const insideZ2: [number, number] = [z2Lng + D_LNG_40M / 2, LAT0 + D_LAT_40M / 2];
  assert(pointInGeometry(insideZ1, group.geometry));
  assert(pointInGeometry(insideZ2, group.geometry));
});

Deno.test('R2-AC2 corrected: zones with an edge-to-edge gap > 50m do not merge', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  const z2 = zone('z2', 33.000000 + D_LNG_40M + GAP_200M_LNG, LAT0, '2026-01-02T00:00:00Z');

  const groups = computeZoneMerges([z1, z2], 50);

  assertEquals(groups.length, 0,
    'Zones ~200m apart (> 50m threshold) must never be reported as a merge group');
});

Deno.test('R2-AC3: adjacency is transitive across the full owner/city zone set', () => {
  const z1 = zone('z1', 33.000000, LAT0, '2026-01-01T00:00:00Z');
  const z2 = zone('z2', 33.000000 + D_LNG_40M, LAT0, '2026-01-02T00:00:00Z');
  const z3 = zone('z3', 33.000000 + 2 * D_LNG_40M, LAT0, '2026-01-03T00:00:00Z');

  const groups = computeZoneMerges([z1, z2, z3], 50);

  assertEquals(groups.length, 1, 'A chain of pairwise-adjacent zones must collapse into one group');
  assertEquals(groups[0].survivorId, 'z1', 'The oldest zone in the connected group must survive');
  assertEquals(new Set(groups[0].absorbedIds), new Set(['z2', 'z3']));
});
