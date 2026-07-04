// supabase/functions/claim_territory/merge_geometry.ts
//
// Pure, mock-free adjacent-zone merge algorithm. No Supabase import, no I/O.
// Exported computeZoneMerges(zones, thresholdM) is called by index.ts's thin
// orchestration layer after loading a single owner's same-city zones.
//
// Three-tier contiguity contract:
//   Tier 1 - touching/overlap, or a hairline gap <= 5 m (jitter epsilon):
//            one zones row, geometry = true boundary-respecting polygon
//            union, morphological closing permitted only at the 5 m scale.
//   Tier 2 - edge-to-edge gap strictly between 5 m and the configured merge
//            threshold (thresholdM; 25 m in production, kProximityTriggerM):
//            still one zones row (same identity, oldest id survives), but
//            geometry is a MultiPolygon of both original outlines, with no
//            bridging/closing at this scale.
//   Tier 3 - gap beyond thresholdM: no merge, zones stay separate rows.
//
// Buffers (turf.buffer) are used ONLY for the isWithin distance/adjacency
// tests at both budgets. The geometry that gets stored is always built from
// the original, un-buffered rings, or from a bounded dilate-union-erode
// closing that ends up back at the same scale it started from. No buffered
// shape is ever the value written into a MergeGroup's geometry field.

import { union } from 'https://esm.sh/@turf/union@7';
import { buffer } from 'https://esm.sh/@turf/buffer@7';
import { booleanIntersects } from 'https://esm.sh/@turf/boolean-intersects@7';
import { polygon as turfPolygon, featureCollection } from 'https://esm.sh/@turf/helpers@7';

// Turf's own d.ts generics vary in arity across published versions of the
// `geojson` type package it depends on, so a plain `Feature<Polygon>` import
// pin has broken cross-version before. A local, structural feature type
// (matching exactly what turf's helpers/union/buffer produce and consume) is
// used instead - it is what the runtime objects actually look like.
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

// Pure input/output types, matching claim_territory_merge_test.ts's import.
export interface ZoneInput {
  id: string;
  ring: number[][]; // [lng, lat] pairs, one outer ring, NOT necessarily closed
  createdAt: string; // ISO timestamp; oldest survives a merge
}

export interface MergeGroup {
  survivorId: string;
  absorbedIds: string[];
  geometry:
    | { type: 'Polygon'; coordinates: number[][][] }
    | { type: 'MultiPolygon'; coordinates: number[][][][] };
}

// Tier 1 jitter epsilon: 5 meters total, an INTERNAL constant, not a second
// parameter to computeZoneMerges. Split across both polygons (2.5 m dilation
// each via turf.buffer) so the total closing distance covered is the full
// 5 m budget, not 5 m applied to one side only.
const kJitterEpsilonMeters = 5;
const kHalfJitterKm = (kJitterEpsilonMeters / 2) / 1000;

// Return the ring with its first point appended if it is not already closed.
function closedRing(ring: number[][]): number[][] {
  if (ring.length === 0) return ring;
  const [fx, fy] = ring[0];
  const [lx, ly] = ring[ring.length - 1];
  return fx === lx && fy === ly ? ring : [...ring, [fx, fy]];
}

function toTurfPolygon(ring: number[][]): TurfFeature<PolygonGeom> {
  return turfPolygon([closedRing(ring)]);
}

// Distance/adjacency test ONLY - buffers here decide whether two polygons
// are "within budgetMeters" of each other; the buffered shapes themselves
// are NEVER what gets stored. Used at TWO different budgets:
// kJitterEpsilonMeters (5 m, Tier 1 vs Tier 2 boundary, internal) and
// thresholdM (the outer merge/no-merge boundary, a parameter; 25 m in
// production, matching kProximityTriggerM).
function isWithin(a: TurfFeature<PolygonGeom>, b: TurfFeature<PolygonGeom>, budgetMeters: number): boolean {
  const halfKm = (budgetMeters / 2) / 1000;
  const bufferedA = buffer(a, halfKm, { units: 'kilometers' });
  const bufferedB = buffer(b, halfKm, { units: 'kilometers' });
  if (!bufferedA || !bufferedB) return false;
  return booleanIntersects(bufferedA, bufferedB);
}

function unionAll(polys: TurfFeature[]): TurfFeature | null {
  if (polys.length === 1) return polys[0];
  return union(featureCollection(polys));
}

// True union for a Tier-1 sub-cluster. Two-attempt strategy:
//   1. Exact union of the ORIGINAL, un-buffered polygons - the ideal path
//      whenever the zones already truly touch or overlap (no dilation, no
//      corner rounding, byte-exact boundary union).
//   2. If (1) is not a single Polygon (a genuine sub-5m gap exists within
//      this Tier-1 sub-cluster), fall back to a morphological closing:
//      dilate every member by the SAME half-epsilon isWithin() uses at the
//      5 m budget, union the dilated shapes, then erode back by the same
//      half-epsilon. It never runs across a Tier-2 (beyond the 5 m jitter
//      epsilon but within thresholdM) gap; those pairs
//      are never in the same Tier-1 sub-cluster to begin with.
// Returns null only if Turf's union call itself fails outright.
function trueUnion(polys: TurfFeature<PolygonGeom>[]): TurfFeature | null {
  const exact = unionAll(polys);
  if (exact && exact.geometry.type === 'Polygon') return exact;

  const dilated = polys.map((p) => buffer(p, kHalfJitterKm, { units: 'kilometers' }));
  const closedRaw = unionAll(dilated);
  if (!closedRaw) return exact; // no bridging possible either - surface whatever (1) produced
  const closed = buffer(closedRaw, -kHalfJitterKm, { units: 'kilometers' });
  return closed && closed.geometry.type === 'Polygon' ? closed : exact;
}

// Plain union-find (no distance test baked in - reused at both budgets).
function unionFindGroups(n: number, isLinked: (i: number, j: number) => boolean): number[][] {
  const parent = Array.from({ length: n }, (_, i) => i);
  function find(i: number): number {
    while (parent[i] !== i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }
  function link(a: number, b: number) {
    const ra = find(a), rb = find(b);
    if (ra !== rb) parent[ra] = rb;
  }
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      if (isLinked(i, j)) link(i, j);
    }
  }
  const groups = new Map<number, number[]>();
  for (let i = 0; i < n; i++) {
    const r = find(i);
    (groups.get(r) ?? groups.set(r, []).get(r)!).push(i);
  }
  return [...groups.values()];
}

// Pure merge computation. No I/O - callers pass in exactly one owner's
// zones in one city (the cross-owner/cross-city invariant is enforced by
// the CALLER's query filter, not by this function).
// `zones` need not be pre-sorted by createdAt - sorted internally.
export function computeZoneMerges(zones: ZoneInput[], thresholdM: number): MergeGroup[] {
  const sorted = [...zones].sort((a, b) => a.createdAt.localeCompare(b.createdAt)); // oldest first survives
  const features = sorted.map((z) => toTurfPolygon(z.ring));

  // OUTER pass: identity. Which zones become ONE row? Governed by the
  // `thresholdM` parameter (25 m in production, matching kProximityTriggerM).
  const outerGroups = unionFindGroups(sorted.length, (i, j) => isWithin(features[i], features[j], thresholdM));

  const result: MergeGroup[] = [];
  for (const idxs of outerGroups) {
    if (idxs.length < 2) continue; // Tier 3: nothing to merge, group dropped entirely

    // idxs are indices into `sorted` (already oldest-first), so idxs[0] is
    // the oldest member of this connected component - the survivor, even
    // if it is not the zone that triggered this claim.
    const groupIdxsAsc = [...idxs].sort((a, b) => a - b);
    const survivorIdx = groupIdxsAsc[0];
    const absorbedIds = groupIdxsAsc.slice(1).map((i) => sorted[i].id);

    // INNER pass, restricted to this group only: geometry shape. The fixed
    // 5 m jitter epsilon, NOT the thresholdM parameter - Tier 1 vs Tier 2.
    const innerGroups = unionFindGroups(
      groupIdxsAsc.length,
      (a, b) => isWithin(features[groupIdxsAsc[a]], features[groupIdxsAsc[b]], kJitterEpsilonMeters),
    );

    const pieces: TurfFeature[] = [];
    for (const innerIdxs of innerGroups) {
      const members = innerIdxs.map((k) => features[groupIdxsAsc[k]]);
      if (members.length === 1) {
        pieces.push(members[0]); // untouched original outline - no closing applied to a lone member
      } else {
        const closed = trueUnion(members as TurfFeature<PolygonGeom>[]);
        pieces.push(closed ?? unionAll(members)!); // trueUnion() only returns null on a hard Turf failure
      }
    }

    const geometry = pieces.length === 1
      ? (pieces[0].geometry as { type: 'Polygon'; coordinates: number[][][] })
      : {
        type: 'MultiPolygon' as const,
        // Tier 2: concatenate each piece's ORIGINAL outer ring
        // unchanged. No union, no closing, no buffer geometry ever appears
        // here - this is the "no bridging" requirement, structurally.
        coordinates: pieces.flatMap((p) =>
          p.geometry.type === 'Polygon' ? [p.geometry.coordinates] : p.geometry.coordinates
        ),
      };

    result.push({ survivorId: sorted[survivorIdx].id, absorbedIds, geometry });
  }
  return result;
}
