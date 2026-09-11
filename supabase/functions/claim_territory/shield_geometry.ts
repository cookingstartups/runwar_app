// supabase/functions/claim_territory/shield_geometry.ts
//
// Pure geometry: subtracts every active shielded overlap from a fresh claim
// ring, one turf `difference` call per shielded zone over an accumulator,
// mirroring merge_geometry.ts's own rawDifferenceFallback pattern. No I/O,
// no Supabase import - callers (claim_territory/handler.ts) decide which
// rival zones are actively shielded and pass in only their ring sets.

import { difference } from 'https://esm.sh/@turf/difference@7';
import { area as turfArea } from 'https://esm.sh/@turf/area@7';
import { polygon as turfPolygon, featureCollection } from 'https://esm.sh/@turf/helpers@7';

type PolygonGeom = { type: 'Polygon'; coordinates: number[][][] };
type MultiPolygonGeom = { type: 'MultiPolygon'; coordinates: number[][][][] };
type Geom = PolygonGeom | MultiPolygonGeom;
interface TurfFeature<G extends Geom = Geom> {
  type: 'Feature';
  geometry: G;
  properties: Record<string, unknown> | null;
  // deno-lint-ignore no-explicit-any
  [key: string]: any;
}

// A polygon that may carry holes: [exterior, ...interiorRings].
export type RingSet = number[][][];
export type RingSetList = RingSet[];

// Minimum post-carve remaining area (sqm) a claim must clear to be stored,
// inclusive (remaining >= floor succeeds). Value fixed by the governing
// design; exported so a test can assert the boundary against the real
// constant rather than a duplicated literal.
export const kMinPostShieldClaimAreaSqm = 200.0;

// A dropped sliver (a fragment or hole under this area) is discarded before
// validity checks run, rather than voiding the whole claim over
// floating-point noise. Matches the governing design's "degenerate slivers
// below 1 sqm are dropped before validation" rule.
const kSliverAreaSqm = 1.0;

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

function toTurfPolygon(ringSet: RingSet): TurfFeature<PolygonGeom> {
  return turfPolygon(ringSet.map((r) => closedRing(r)));
}

// A ring with fewer than 4 points (closed: 3 distinct vertices minimum)
// cannot describe a real polygon.
function ringHasMinimumPoints(ring: number[][]): boolean {
  return closedRing(ring).length >= 4;
}

// Drop sub-floor slivers (fragments or holes) and reject anything left that
// fails basic validity. Returns null when nothing survives validation - the
// caller treats that identically to "nothing survived the subtraction".
function sanitizeGeometry(geom: Geom): Geom | null {
  if (geom.type === 'Polygon') {
    const rings = geom.coordinates;
    if (rings.length === 0) return null;
    const exterior = rings[0];
    if (!ringHasMinimumPoints(exterior)) return null;
    const exteriorAreaSqm = turfArea(turfPolygon([closedRing(exterior)]));
    if (exteriorAreaSqm < kSliverAreaSqm) return null;

    const holes: number[][][] = [];
    for (let i = 1; i < rings.length; i++) {
      const hole = rings[i];
      if (!ringHasMinimumPoints(hole)) continue; // drop degenerate hole ring
      const holeAreaSqm = turfArea(turfPolygon([closedRing(hole)]));
      if (holeAreaSqm < kSliverAreaSqm) continue; // drop sliver hole
      holes.push(hole);
    }
    return { type: 'Polygon', coordinates: [exterior, ...holes] };
  }

  // MultiPolygon: sanitize each member independently, drop sub-floor
  // members outright, never silently promote a hole to a member.
  const members: number[][][][] = [];
  for (const member of geom.coordinates) {
    const sanitizedMember = sanitizeGeometry({ type: 'Polygon', coordinates: member });
    if (sanitizedMember && sanitizedMember.type === 'Polygon') {
      members.push(sanitizedMember.coordinates);
    }
  }
  if (members.length === 0) return null;
  if (members.length === 1) return { type: 'Polygon', coordinates: members[0] };
  return { type: 'MultiPolygon', coordinates: members };
}

function totalAreaSqm(geom: Geom): number {
  if (geom.type === 'Polygon') {
    return turfArea(turfPolygon(geom.coordinates.map((r) => closedRing(r))));
  }
  return geom.coordinates.reduce(
    (sum, member) => sum + turfArea(turfPolygon(member.map((r) => closedRing(r)))),
    0,
  );
}

// Subtracts every shielded overlap from claimRing, one turf `difference`
// call per shielded zone over an accumulator - the same shape as
// merge_geometry.ts's rawDifferenceFallback. Interior rings on both the
// claim side and the shielded side are preserved end to end: turf's
// `difference` natively produces interior rings for an enclosed subtrahend,
// which is exactly the AC-1 annulus shape this feature requires.
//
// Fail-closed contract: a thrown `difference` call, or a result that fails
// basic validity after sliver-dropping, is treated as "nothing survived"
// (geometry: null, remainingAreaSqm: 0) rather than silently falling back to
// the uncarved claim - the caller's floor check then voids the claim, never
// storing an uncarved or invalid shape.
export function computeShieldCarve(
  claimRing: number[][],
  shieldedRingSets: RingSet[],
): ShieldCarveResult {
  const claimClosed = closedRing(claimRing);
  const claimAreaSqm = turfArea(turfPolygon([claimClosed]));

  if (shieldedRingSets.length === 0) {
    return { geometry: { type: 'Polygon', coordinates: [claimClosed] }, remainingAreaSqm: claimAreaSqm, removedAreaSqm: 0 };
  }

  let accumulator: TurfFeature<Geom> = turfPolygon([claimClosed]);

  try {
    for (const shielded of shieldedRingSets) {
      const shieldFeature = toTurfPolygon(shielded);
      const diff = difference(featureCollection([accumulator, shieldFeature]));
      if (!diff) {
        // Nothing survives - the claim is entirely inside the shielded set
        // subtracted so far. Not an error: a legitimate "nothing left"
        // outcome, distinguishable from a failure by the return shape.
        return { geometry: null, remainingAreaSqm: 0, removedAreaSqm: claimAreaSqm };
      }
      accumulator = diff as TurfFeature<Geom>;
    }
  } catch (_e) {
    // Never silence: the caller's fail-closed void path is the equivalent
    // of surfacing this failure - remainingAreaSqm 0 always fails the
    // floor, so the claim voids rather than storing an uncarved shape.
    return { geometry: null, remainingAreaSqm: 0, removedAreaSqm: claimAreaSqm };
  }

  const sanitized = sanitizeGeometry(accumulator.geometry);
  if (!sanitized) {
    return { geometry: null, remainingAreaSqm: 0, removedAreaSqm: claimAreaSqm };
  }

  const remainingAreaSqm = totalAreaSqm(sanitized);
  const removedAreaSqm = Math.max(0, claimAreaSqm - remainingAreaSqm);
  return { geometry: sanitized, remainingAreaSqm, removedAreaSqm };
}

// Classifies a flat list of dissolved boundary contours into a RingSetList,
// delegating to merge_geometry.ts's real implementation so there is exactly
// one classification algorithm rather than two independently-maintained
// copies of the same signed-area/containment logic.
export { classifyDissolvedRings } from './merge_geometry.ts';
