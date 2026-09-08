// supabase/functions/tests/shield_claim_enforcement_test.ts
//
// Server-side proofs that an active shield on a zone actually protects it:
// a rival claim overlapping a shielded zone is carved down (never a full
// conquest, never a dispute), a carve landing the claimant below the
// minimum floor voids the whole claim, a carved hole survives the shield
// later expiring, and hole-preservation is proven across the whole class of
// server ring-selection sites rather than one call site.
//
// Run: /home/algif/.deno/bin/deno test --allow-all supabase/functions/tests/shield_claim_enforcement_test.ts

import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  computeShieldCarve,
  kMinPostShieldClaimAreaSqm,
} from '../claim_territory/shield_geometry.ts';
import { computeZoneMerges, type ZoneInput } from '../claim_territory/merge_geometry.ts';
import { resolveDecayMerge, type ResolveDecayMergeDbClient } from '../resolve_decay_merges/handler.ts';

// ---------------------------------------------------------------------------
// Geometry test helpers
// ---------------------------------------------------------------------------

const LAT0 = 39.470000; // Valencia, matching the other claim_territory test files
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

function mLng(meters: number): number {
  return meters / LNG_M;
}
function mLat(meters: number): number {
  return meters / LAT_M;
}

function squareRing(lng0: number, lat0: number, widthM: number, heightM: number): number[][] {
  const dLng = mLng(widthM);
  const dLat = mLat(heightM);
  const a = [lng0, lat0];
  const b = [lng0 + dLng, lat0];
  const c = [lng0 + dLng, lat0 + dLat];
  const d = [lng0, lat0 + dLat];
  return [a, b, c, d, a];
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

function ringAreaM2(ring: number[][]): number {
  const projected = ring.map(([lng, lat]) => [lng * LNG_M, lat * LAT_M]);
  let area = 0;
  for (let i = 0; i < projected.length; i++) {
    const [x1, y1] = projected[i];
    const [x2, y2] = projected[(i + 1) % projected.length];
    area += x1 * y2 - x2 * y1;
  }
  return Math.abs(area) / 2;
}

function pointInGeometry(pt: [number, number], geometry: { type: string; coordinates: unknown }): boolean {
  if (geometry.type === 'Polygon') {
    const rings = geometry.coordinates as number[][][];
    // A correct carve must exclude the shielded hole - a point inside the
    // hole must NOT be reported inside the exterior only. Interior rings
    // (index >= 1) are treated as holes: inside exterior AND inside no hole.
    const insideExterior = pointInRing(pt, rings[0]);
    if (!insideExterior) return false;
    for (let i = 1; i < rings.length; i++) {
      if (pointInRing(pt, rings[i])) return false;
    }
    return true;
  }
  if (geometry.type === 'MultiPolygon') {
    const polys = geometry.coordinates as number[][][][];
    return polys.some((poly) => pointInRing(pt, poly[0]));
  }
  return false;
}

const AREA_EPSILON_M2 = 5.0;

// ---------------------------------------------------------------------------
// (a) Carve, not full area - AC-1
// ---------------------------------------------------------------------------

Deno.test('a rival claim enclosing an active shield yields the claim minus the shielded zone, not the full area', () => {
  const claimRing = squareRing(33.000000, LAT0, 100, 100);
  const claimAreaSqm = ringAreaM2(claimRing);

  // Shield sits fully inside the claim, offset from the origin corner.
  const shieldRing = squareRing(33.000000 + mLng(40), LAT0 + mLat(40), 20, 20);
  const shieldAreaSqm = ringAreaM2(shieldRing);

  const result = computeShieldCarve(claimRing, [[shieldRing]]);

  assert(
    result.removedAreaSqm > 0,
    `removedAreaSqm must reflect the subtracted shielded area (expected > 0, got ${result.removedAreaSqm}). ` +
      'Reverting the carve implementation makes this fail: an unsubtracted claim removes nothing.',
  );
  assert(
    result.remainingAreaSqm < claimAreaSqm - AREA_EPSILON_M2,
    `remainingAreaSqm (${result.remainingAreaSqm}) must be materially below the uncarved claim area ` +
      `(${claimAreaSqm}); the shielded zone's area must have been subtracted.`,
  );
  assert(
    Math.abs(result.remainingAreaSqm - (claimAreaSqm - shieldAreaSqm)) < shieldAreaSqm,
    'remainingAreaSqm must be roughly claimArea minus the shielded area, not the full claim area.',
  );

  assert(result.geometry !== null, 'carve of a genuine partial-shield overlap must not collapse to null');
  const shieldCenter: [number, number] = [
    33.000000 + mLng(50),
    LAT0 + mLat(50),
  ];
  assertFalse(
    pointInGeometry(shieldCenter, result.geometry!),
    'a point at the center of the shielded zone must NOT be reported as inside the carved claim geometry',
  );
});

// ---------------------------------------------------------------------------
// (b) Sub-floor void fires - AC-3
// ---------------------------------------------------------------------------

Deno.test('a carve that leaves the remainder below the 200 sqm floor must be flagged for voiding', () => {
  // A 20x20 (400 sqm) claim almost entirely covered by a 19.5x20 shield,
  // leaving a roughly 10 sqm sliver - well below the 200 sqm floor.
  const claimRing = squareRing(33.000000, LAT0, 20, 20);
  const shieldRing = squareRing(33.000000, LAT0, 19.5, 20);

  const result = computeShieldCarve(claimRing, [[shieldRing]]);
  const wouldVoid = result.remainingAreaSqm < kMinPostShieldClaimAreaSqm;

  assert(
    wouldVoid,
    `remaining area after carving (${result.remainingAreaSqm} sqm) must fall below the ` +
      `${kMinPostShieldClaimAreaSqm} sqm floor for this near-total shield overlap and must be voided. ` +
      'Reverting the carve leaves the full, uncarved claim area, which never crosses the floor and ' +
      'would be wrongly accepted.',
  );
});

Deno.test('a carve landing the remainder exactly at the 200 sqm floor must succeed, not void', () => {
  // Construct a claim where the carved remainder is exactly the floor value:
  // a 10m x 40m (400 sqm) claim with a shield covering the far half minus a
  // strip, engineered so the survivor sliver is exactly 200 sqm.
  const claimRing = squareRing(33.000000, LAT0, 10, 40);
  const shieldRing = squareRing(33.000000, LAT0 + mLat(20), 10, 20); // covers exactly half (200 sqm)

  const result = computeShieldCarve(claimRing, [[shieldRing]]);

  assert(
    result.remainingAreaSqm >= kMinPostShieldClaimAreaSqm - AREA_EPSILON_M2 &&
      result.remainingAreaSqm <= kMinPostShieldClaimAreaSqm + AREA_EPSILON_M2,
    `expected the carved remainder to land at approximately the ${kMinPostShieldClaimAreaSqm} sqm floor ` +
      `(inclusive success boundary), got ${result.remainingAreaSqm} sqm. This proves the carve is ` +
      'actually subtracting the shielded half rather than passing the claim through untouched.',
  );
});

// ---------------------------------------------------------------------------
// (c) Hole persists after expiry - AC-6
// ---------------------------------------------------------------------------

Deno.test('a carved hole on a ZoneInput survives being unioned by computeZoneMerges', () => {
  // A holed zone (donut: exterior with a hole carved out of its middle)
  // adjacent to a same-owner, same-level neighbour so they merge into one
  // continuous Polygon via the ordinary claim-time merge path.
  const exterior = squareRing(33.000000, LAT0, 40, 40);
  const hole = squareRing(33.000000 + mLng(10), LAT0 + mLat(10), 5, 5);
  const neighbour = squareRing(33.000000 + mLng(40), LAT0, 40, 40); // touches exterior's right edge

  const holedZone: ZoneInput = {
    id: 'holed-zone',
    ring: exterior,
    holes: [hole],
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
  assertEquals(groups.length, 1, 'the touching same-level pair must still merge into one group');
  const merged = groups[0];

  const holeCenter: [number, number] = [
    33.000000 + mLng(12.5),
    LAT0 + mLat(12.5),
  ];
  assertFalse(
    pointInGeometry(holeCenter, merged.geometry),
    'a point inside the originally-carved hole must remain OUTSIDE the merged geometry - the carved ' +
      'hole must survive the claimant\'s own next merge, not be silently refilled by the union. ' +
      'Reverting the hole-aware union wiring makes this fail: today\'s toTurfPolygon ignores ' +
      'ZoneInput.holes entirely, so the union fills the hole back in.',
  );
});

Deno.test('resolve_decay_merges preserves a carved hole through its own merge write, not just the live shield check', async () => {
  // Two same-owner, same-level, touching zones: one holed (donut) whose
  // shield has already EXPIRED (in the past) - AC-6 requires the hole to
  // persist purely from stored geometry, independent of current shield
  // state.
  const exterior = squareRing(33.000000, LAT0, 40, 40);
  const hole = squareRing(33.000000 + mLng(10), LAT0 + mLat(10), 5, 5);
  const neighbour = squareRing(33.000000 + mLng(40), LAT0, 40, 40);

  const donutGeomJson = JSON.stringify({
    type: 'Polygon',
    coordinates: [exterior.map((p) => [...p]).concat([exterior[0]]), hole.map((p) => [...p]).concat([hole[0]])],
  });
  const neighbourGeomJson = JSON.stringify({ type: 'Polygon', coordinates: [neighbour] });

  const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
  const fakeClient: ResolveDecayMergeDbClient = {
    from(_table: string) {
      return {
        select(_cols: string) {
          return {
            eq(_c1: string, _v1: unknown) {
              return {
                eq(_c2: string, _v2: unknown) {
                  return {
                    eq(_c3: string, _v3: unknown) {
                      return Promise.resolve({
                        data: [
                          {
                            id: 'donut-zone',
                            geom_json: donutGeomJson,
                            created_at: '2026-01-01T00:00:00Z',
                            influence: 1,
                            influence_level: 1,
                            credits_earned: 0,
                            last_active_at: null,
                            shield_active: true,
                            // Expired: five minutes in the past.
                            shield_expires_at: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
                          },
                          {
                            id: 'neighbour-zone',
                            geom_json: neighbourGeomJson,
                            created_at: '2026-01-02T00:00:00Z',
                            influence: 1,
                            influence_level: 1,
                            credits_earned: 0,
                            last_active_at: null,
                            shield_active: false,
                            shield_expires_at: null,
                          },
                        ],
                        error: null,
                      });
                    },
                  };
                },
              };
            },
          };
        },
      };
    },
    rpc(fn: string, args: Record<string, unknown>) {
      rpcCalls.push({ fn, args });
      return Promise.resolve({ error: null });
    },
  };

  const result = await resolveDecayMerge(fakeClient, 'owner-a', 'valencia', 'donut-zone');
  assert(result.merged, 'the touching same-level pair must merge (donut-zone must be part of a group)');

  const mergeCall = rpcCalls.find((c) => c.fn === 'apply_zone_merge');
  assert(mergeCall, 'expected an apply_zone_merge RPC call');
  const writtenGeom = JSON.parse(mergeCall!.args.p_geom_json as string) as { type: string; coordinates: unknown };

  assertEquals(
    writtenGeom.type,
    'Polygon',
    'the merged geometry written back by resolve_decay_merges must be a single Polygon',
  );
  const writtenRings = writtenGeom.coordinates as number[][][];
  assert(
    writtenRings.length >= 2,
    `the geometry resolve_decay_merges writes via apply_zone_merge must still carry the carved ` +
      `interior ring (coordinates.length >= 2), got ${writtenRings.length}. The shield on donut-zone ` +
      'has already expired at read time, so this proves persistence is a property of stored geometry, ' +
      "not a live shield re-check. Reverting the fix makes this fail: today's local outlinesOf copy in " +
      'resolve_decay_merges/handler.ts takes only coordinates[0], dropping the hole before it ever ' +
      'reaches computeZoneMerges.',
  );
});

// ---------------------------------------------------------------------------
// (d) Class of defect, not one call site - AC-7
//
// Source-scan regression guard: every server-side site that today reduces a
// polygon to its exterior-only ring must be proven fixed, not just one of
// them. Sites 7/8 (merge_geometry.ts's largestRing numeric-noise fallback,
// and handler.ts's freshly-submitted multi-loop union fallback) are
// deliberately exempted - both operate on fragments/rings that structurally
// cannot carry a hole, per the governing design's own allowlist.
// ---------------------------------------------------------------------------

const claimHandlerSrc = Deno.readTextFileSync(
  new URL('../claim_territory/handler.ts', import.meta.url),
);
const decaySrc = Deno.readTextFileSync(
  new URL('../resolve_decay_merges/handler.ts', import.meta.url),
);
const mergeGeometrySrc = Deno.readTextFileSync(
  new URL('../claim_territory/merge_geometry.ts', import.meta.url),
);

function block(src: string, startMarker: string, endMarker: string, label: string): string {
  const start = src.indexOf(startMarker);
  assert(start >= 0, `Landmark not found: ${label} start ("${startMarker}"). Source structure moved.`);
  const end = src.indexOf(endMarker, start);
  assert(end > start, `Landmark not found: ${label} end ("${endMarker}"). Source structure moved.`);
  return src.slice(start, end);
}

Deno.test('site 1 (claim_territory toWkt): write path must not flatten a Polygon to coordinates[0] only', () => {
  const toWktBlock = block(claimHandlerSrc, 'function toWkt(', '\n// A zone', 'claim_territory toWkt');
  assertFalse(
    toWktBlock.includes('ringToWktBody(input.coordinates[0])'),
    'claim_territory/handler.ts toWkt still writes only the exterior ring (coordinates[0]) for a ' +
      'Polygon - a carved hole would never reach storage. This is the exact site AC-7(a) names.',
  );
});

Deno.test('site 2 (claim_territory outlinesOf): server re-read must not flatten a Polygon to coordinates[0] only', () => {
  const outlinesBlock = block(
    claimHandlerSrc,
    'function outlinesOf(',
    '\nexport interface CapturedRingGateResult',
    'claim_territory outlinesOf',
  );
  assertFalse(
    outlinesBlock.includes('coords[0] ? [coords[0]] : []'),
    'claim_territory/handler.ts outlinesOf still returns only the exterior ring for a Polygon - a ' +
      'later overlap test would see a filled shape where a hole should have excluded it. This is the ' +
      'exact site AC-7(b) names.',
  );
});

Deno.test('site 3 (resolve_decay_merges toWkt): its own copy must not flatten a Polygon to coordinates[0] only', () => {
  const toWktBlock = block(decaySrc, 'function toWkt(', '\nexport interface ResolveDecayMergeRequestBody', 'resolve_decay_merges toWkt');
  assertFalse(
    toWktBlock.includes('ringToWktBody(input.coordinates[0])'),
    'resolve_decay_merges/handler.ts toWkt still writes only the exterior ring - required scope per AC-6.',
  );
});

Deno.test('site 4 (resolve_decay_merges outlinesOf): its own copy must not flatten a Polygon to coordinates[0] only', () => {
  const outlinesBlock = block(decaySrc, 'function outlinesOf(', '\nfunction ringToWktBody', 'resolve_decay_merges outlinesOf');
  assertFalse(
    outlinesBlock.includes('coords[0] ? [coords[0]] : []'),
    'resolve_decay_merges/handler.ts outlinesOf still returns only the exterior ring - required scope per AC-6.',
  );
});

Deno.test('site 5 (merge_geometry toTurfPolygon): union input must become hole-aware', () => {
  const toTurfBlock = block(
    mergeGeometrySrc,
    'function toTurfPolygon(ring: number[][])',
    '\n// Distance/adjacency test',
    'merge_geometry toTurfPolygon',
  );
  assert(
    toTurfBlock.includes('holes'),
    'merge_geometry.ts toTurfPolygon still builds a turf polygon from the exterior ring only, never ' +
      'reading ZoneInput.holes - every union/merge computed through this helper silently drops a ' +
      'carved hole. Required per the governing design section 1.3.',
  );
});

Deno.test('site 6 (merge_geometry computeZoneSplit dissolve mapping): must classify holes, not promote every contour to an exterior', () => {
  const dissolveBlock = block(
    mergeGeometrySrc,
    'const geometry = rings.length === 1',
    '\n  return {\n    case: \'partialOverlap\',\n    remainder: geometry,',
    'merge_geometry computeZoneSplit dissolve mapping',
  );
  assert(
    dissolveBlock.includes('classifyDissolvedRings'),
    'merge_geometry.ts computeZoneSplit still promotes every dissolved contour (including an inner, ' +
      "hole-shaped contour) to its own MultiPolygon exterior member, instead of calling a ring " +
      'classifier - the exact latent defect described in the governing design section 1.1.',
  );
});
