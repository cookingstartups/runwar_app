// supabase/functions/claim_territory/shield_geometry.ts
//
// Placeholder scaffold ONLY. computeShieldCarve and classifyDissolvedRings
// are pure geometry entry points a rival-claim carve feature needs; neither
// performs the real subtraction/classification yet. This file exists so a
// test suite written ahead of that work can import real symbols and reach
// its own assertions, instead of failing on an unresolved import. Every
// function here is intentionally a no-op / naive pass-through.

import { area as turfArea } from 'https://esm.sh/@turf/area@7';
import { polygon as turfPolygon } from 'https://esm.sh/@turf/helpers@7';

type PolygonGeom = { type: 'Polygon'; coordinates: number[][][] };
type MultiPolygonGeom = { type: 'MultiPolygon'; coordinates: number[][][][] };

// A polygon that may carry holes: [exterior, ...interiorRings].
export type RingSet = number[][][];
export type RingSetList = RingSet[];

// Minimum post-carve remaining area (sqm) a claim must clear to be stored,
// inclusive (remaining >= floor succeeds). Value fixed by the governing
// design; exported so a test can assert the boundary against the real
// constant rather than a duplicated literal.
export const kMinPostShieldClaimAreaSqm = 200.0;

export interface ShieldCarveResult {
  geometry: PolygonGeom | MultiPolygonGeom | null;
  remainingAreaSqm: number;
  removedAreaSqm: number;
}

function closedRing(ring: number[][]): number[][] {
  if (ring.length === 0) return ring;
  const [fx, fy] = ring[0];
  const [lx, ly] = ring[ring.length - 1];
  return fx === lx && fy === ly ? ring : [...ring, [fx, fy]];
}

// PLACEHOLDER: does not subtract anything. Returns the claim ring untouched
// with removedAreaSqm always 0, regardless of the shielded overlaps
// supplied. Any caller relying on real subtraction output must not depend
// on this scaffold's numeric result.
export function computeShieldCarve(
  claimRing: number[][],
  _shieldedRingSets: RingSet[],
): ShieldCarveResult {
  const closed = closedRing(claimRing);
  const areaSqm = turfArea(turfPolygon([closed]));
  return {
    geometry: { type: 'Polygon', coordinates: [closed] },
    remainingAreaSqm: areaSqm,
    removedAreaSqm: 0,
  };
}

// PLACEHOLDER: promotes every dissolved contour to its own exterior ring
// rather than classifying holes vs exteriors by winding/containment. Same
// shape as today's real defect in computeZoneSplit's dissolve mapping, not
// a fix for it.
export function classifyDissolvedRings(rings: number[][][]): RingSetList {
  return rings.map((r) => [r]);
}
