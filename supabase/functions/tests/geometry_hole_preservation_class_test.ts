// supabase/functions/tests/geometry_hole_preservation_class_test.ts
//
// Behavioural table test for the hole-preservation class of defect: every
// in-scope server converter (claim_territory's write/read helpers, and
// merge_geometry's union input and split dissolve mapping) is driven for
// real, against one shared donut fixture, and the interior ring's survival
// is asserted from actual computed output - never from scanning source
// text for a token. This is the primary mechanism; the source-scan guard
// in shield_claim_enforcement_test.ts is the secondary backstop only, per
// the governing design.
//
// Run: /home/algif/.deno/bin/deno test --allow-all supabase/functions/tests/geometry_hole_preservation_class_test.ts

import { assert, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { toWkt, outlinesOf } from '../claim_territory/handler.ts';
import { toTurfPolygon, computeZoneMerges, computeZoneSplit, type ZoneInput } from '../claim_territory/merge_geometry.ts';

const LAT0 = 39.470000;
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

function mLng(m: number): number {
  return m / LNG_M;
}
function mLat(m: number): number {
  return m / LAT_M;
}

function rect(lng0: number, lat0: number, widthM: number, heightM: number): number[][] {
  const dLng = mLng(widthM);
  const dLat = mLat(heightM);
  return [
    [lng0, lat0],
    [lng0 + dLng, lat0],
    [lng0 + dLng, lat0 + dLat],
    [lng0, lat0 + dLat],
    [lng0, lat0],
  ];
}

function pointInRing(pt: [number, number], ring: number[][]): boolean {
  let inside = false;
  const [px, py] = pt;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    const hit = yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi;
    if (hit) inside = !inside;
  }
  return inside;
}

// Shared donut fixture: a 40x40 exterior with a 5x5 hole carved 10m/10m
// from its corner, and a marker point known to sit inside the hole.
const EXTERIOR = rect(33.000000, LAT0, 40, 40);
const HOLE = rect(33.000000 + mLng(10), LAT0 + mLat(10), 5, 5);
const HOLE_CENTER: [number, number] = [33.000000 + mLng(12.5), LAT0 + mLat(12.5)];

// ---------------------------------------------------------------------------
// Row 1 - claim_territory/handler.ts toWkt (write path)
// ---------------------------------------------------------------------------

Deno.test('table: claim_territory toWkt writes the interior ring, not just the exterior', () => {
  const wkt = toWkt({ type: 'Polygon', coordinates: [EXTERIOR, HOLE] });
  const holeVertexStr = `${HOLE[0][0]} ${HOLE[0][1]}`;
  assert(
    wkt.includes(holeVertexStr),
    `toWkt output must contain a hole vertex ("${holeVertexStr}") when the input Polygon carries an ` +
      `interior ring - got: ${wkt.slice(0, 120)}... Reverting the fix makes this fail: today's toWkt ` +
      'writes only coordinates[0], dropping every ring beyond the exterior.',
  );
});

// ---------------------------------------------------------------------------
// Row 2 - claim_territory/handler.ts outlinesOf (server re-read)
// ---------------------------------------------------------------------------

Deno.test('table: claim_territory outlinesOf returns the interior ring alongside the exterior', () => {
  const result = outlinesOf({ type: 'Polygon', coordinates: [EXTERIOR, HOLE] });
  assert(
    result.length >= 2,
    `outlinesOf must return at least 2 rings (exterior + hole) for a Polygon with an interior ring, ` +
      `got ${result.length}. Reverting the fix makes this fail: today's outlinesOf returns only ` +
      'coords[0] for a Polygon, so a later overlap test would see a filled shape where a hole should ' +
      'have excluded it.',
  );
});

// ---------------------------------------------------------------------------
// Row 5 - merge_geometry.ts toTurfPolygon, driven via computeZoneMerges'
// union of a holed ZoneInput with a touching neighbour (toTurfPolygon has
// no holes parameter of its own to call directly - it is exercised through
// its real call site).
// ---------------------------------------------------------------------------

Deno.test('table: merge_geometry union (toTurfPolygon call site) preserves a holed ZoneInput through the merge', () => {
  const neighbour = rect(33.000000 + mLng(40), LAT0, 40, 40);
  const holedZone: ZoneInput = {
    id: 'holed-zone',
    ring: EXTERIOR,
    holes: [HOLE],
    createdAt: '2026-01-01T00:00:00Z',
    influenceLevel: 1,
  };
  const neighbourZone: ZoneInput = {
    id: 'neighbour-zone',
    ring: neighbour,
    createdAt: '2026-01-02T00:00:00Z',
    influenceLevel: 1,
  };

  const groups = computeZoneMerges([holedZone, neighbourZone], 25);
  assert(groups.length === 1, 'the touching same-level pair must merge into one group');
  const merged = groups[0];
  const rings = merged.geometry.type === 'Polygon'
    ? (merged.geometry.coordinates as number[][][])
    : (merged.geometry.coordinates as number[][][][]).flat();

  const insideAnyRing = rings.some((r) => pointInRing(HOLE_CENTER, r));
  assertFalse(
    insideAnyRing,
    'the hole center must not fall inside any ring of the merged geometry\'s member polygons in a way ' +
      "that means the union filled the hole back in. Reverting the fix makes this fail: today's " +
      'toTurfPolygon ignores ZoneInput.holes entirely, so the union computes the zone as a solid square.',
  );
  // Also directly executes toTurfPolygon's real, unmodified single-ring
  // contract, confirming it still has no holes parameter to exploit.
  const exteriorOnlyFeature = toTurfPolygon(EXTERIOR);
  assert(exteriorOnlyFeature.geometry.coordinates.length === 1,
    'toTurfPolygon(ring) must still take a single ring with no way to pass holes - proving the union ' +
      'path above is the real, only call site that would need to change to fix this row');
});

// ---------------------------------------------------------------------------
// Row 6 - merge_geometry.ts computeZoneSplit's dissolve mapping: an
// annular remainder (existing zone minus a strictly-interior re-run) must
// exclude the re-run's own footprint, not promote it to a second filled
// exterior member.
// ---------------------------------------------------------------------------

Deno.test('table: computeZoneSplit annular remainder excludes the re-run footprint from every member', () => {
  const existingRing = rect(33.000000, LAT0, 100, 100);
  // Strictly interior re-run, away from every edge, forcing a genuine
  // annulus (never touches booleanContains/noOverlap branches).
  const reRunRing = rect(33.000000 + mLng(40), LAT0 + mLat(40), 20, 20);
  const reRunCenter: [number, number] = [
    33.000000 + mLng(50),
    LAT0 + mLat(50),
  ];

  const result = computeZoneSplit(existingRing, reRunRing, 1);
  assert(result.case === 'partialOverlap', `expected a partial overlap (annular) case, got ${result.case}`);
  assert(result.remainder, 'expected a real remainder geometry for an annular split');

  const memberRings = result.remainder!.type === 'Polygon'
    ? [(result.remainder!.coordinates as number[][][])[0]]
    : (result.remainder!.coordinates as number[][][][]).map((poly) => poly[0]);

  const reRunAreaIsFilledSomewhere = memberRings.some((r) => pointInRing(reRunCenter, r));
  assertFalse(
    reRunAreaIsFilledSomewhere,
    'the re-run\'s own interior footprint must not be reported as filled territory by any member ring ' +
      'of the split remainder - it is a hole in the surviving donut, not a second exterior polygon. ' +
      "Reverting the fix makes this fail: today's dissolve mapping promotes every dissolved contour " +
      '(including the inner, hole-shaped one) to its own MultiPolygon exterior member, so a naive ' +
      'per-member point-in-ring test (the same pattern outlinesOf/pointInRing already use downstream) ' +
      'wrongly reports the hole as owned territory.',
  );
});
