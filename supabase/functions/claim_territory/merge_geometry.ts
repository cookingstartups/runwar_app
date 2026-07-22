// supabase/functions/claim_territory/merge_geometry.ts
//
// Pure, mock-free adjacent-zone merge algorithm. No Supabase import, no I/O.
// Exported computeZoneMerges(zones, thresholdM) is called by index.ts's thin
// orchestration layer after loading a single owner's same-city zones.
//
// Single-rule contiguity contract:
//   Same-owner zones whose boundaries come within thresholdM (25 m in
//   production, matching kProximityTriggerM) of each other merge into ONE
//   zones row with ONE continuous Polygon. The identity test (which zones
//   become one row, including transitively across a chain) and the closing
//   radius (how far the seal reaches) are both governed by thresholdM: every
//   member of a merge group is dilated by thresholdM / 2, the dilated shapes
//   are unioned, and the union is eroded back by the same thresholdM / 2 -
//   a morphological closing that seals gaps up to thresholdM between
//   boundaries that are actually that close, while leaving wider notches
//   uncaptured (no convex hull, no unconditional bridging).
//   Beyond thresholdM: no merge, zones stay separate rows.
//
// Buffers (turf.buffer) are used for BOTH the isWithin distance/adjacency
// test that decides group membership AND the closing operation itself
// (dilate -> union -> erode, all at the thresholdM scale). The dilated
// shapes are NEVER what gets stored - only the eroded-back result (or the
// original ring, for a zone with no merge partner) is written into a
// MergeGroup's geometry field.

import { union } from 'https://esm.sh/@turf/union@7';
import { buffer } from 'https://esm.sh/@turf/buffer@7';
import { area as turfArea } from 'https://esm.sh/@turf/area@7';
import { booleanIntersects } from 'https://esm.sh/@turf/boolean-intersects@7';
import { booleanContains } from 'https://esm.sh/@turf/boolean-contains@7';
import { booleanPointInPolygon } from 'https://esm.sh/@turf/boolean-point-in-polygon@7';
import { pointOnFeature } from 'https://esm.sh/@turf/point-on-feature@7';
import { difference } from 'https://esm.sh/@turf/difference@7';
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
  // Optional, defaults to 1 when omitted - the same "unknown level treated as
  // 1" fallback already used at this module's own call site in index.ts
  // (`influenceLevelById.get(r.id) ?? 1`). Kept optional rather than required
  // so claim_territory_merge_test.ts's pre-existing zone() fixture (which
  // predates the level-equality gate and never sets this field) keeps
  // compiling unchanged; every zone in a real merge candidate query always
  // supplies it explicitly.
  influenceLevel?: number;
}

export interface MergeGroup {
  survivorId: string;
  absorbedIds: string[];
  geometry:
    | { type: 'Polygon'; coordinates: number[][][] }
    | { type: 'MultiPolygon'; coordinates: number[][][][] };
}

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
// are NEVER what gets stored. Called with thresholdM both to build the
// merge groups and, via halfThresholdKm below, to size the closing radius.
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

// Largest-area ring inside a MultiPolygon feature, wrapped back into a
// standalone Polygon feature.
function largestRing(multi: TurfFeature<MultiPolygonGeom>): TurfFeature<PolygonGeom> {
  let best = multi.geometry.coordinates[0];
  let bestArea = -1;
  for (const coords of multi.geometry.coordinates) {
    const candidate = turfPolygon(coords);
    const a = turfArea(candidate);
    if (a > bestArea) {
      bestArea = a;
      best = coords;
    }
  }
  return turfPolygon(best);
}

// Numeric-noise fallback for when the erode step returns a MultiPolygon
// instead of one continuous ring (can happen when the union of dilated
// shapes has a neck exactly at the closing radius, so floating-point noise
// pinches it during erosion). Never silently drop a real member's geometry:
// pick the fragment that contains every member's own representative point
// first; only fall back to the largest-area fragment (which still contains
// the bulk of the merged group) if no single fragment contains them all.
function pickContainingFragment(
  multi: TurfFeature<MultiPolygonGeom>,
  members: TurfFeature<PolygonGeom>[],
): TurfFeature<PolygonGeom> {
  const fragments = multi.geometry.coordinates.map((coords) => turfPolygon(coords));
  const representativePoints = members.map((m) => pointOnFeature(m));

  const containingAll = fragments.find((frag) =>
    representativePoints.every((pt) => booleanPointInPolygon(pt, frag))
  );
  if (containingAll) return containingAll;

  return largestRing(multi);
}

// True union for a merge group. Two-attempt strategy:
//   1. Exact union of the ORIGINAL, un-buffered polygons - the ideal path
//      whenever the zones already truly touch or overlap (no dilation, no
//      corner rounding, byte-exact boundary union).
//   2. If (1) is not a single Polygon (a genuine gap exists somewhere in
//      this group, up to thresholdM since that is what put them in the same
//      group), fall back to a morphological closing: dilate every member by
//      halfThresholdKm (thresholdM / 2), union the dilated shapes, then
//      erode back by the same halfThresholdKm. Gaps up to thresholdM between
//      boundaries that are actually that close get sealed; nothing wider
//      does, since the dilation on each side only reaches thresholdM / 2.
// Returns null only if Turf's union call itself fails outright.
function trueUnion(polys: TurfFeature<PolygonGeom>[], halfThresholdKm: number): TurfFeature | null {
  const exact = unionAll(polys);
  if (exact && exact.geometry.type === 'Polygon') return exact;

  const dilated = polys
    .map((p) => buffer(p, halfThresholdKm, { units: 'kilometers' }))
    .filter((f): f is TurfFeature<Geom> => f !== undefined);
  if (dilated.length !== polys.length) return exact; // a dilation failed outright - surface whatever (1) produced
  const closedRaw = unionAll(dilated);
  if (!closedRaw) return exact; // no bridging possible either - surface whatever (1) produced

  const eroded = buffer(closedRaw, -halfThresholdKm, { units: 'kilometers' });
  if (!eroded) return exact;
  if (eroded.geometry.type === 'Polygon') return eroded;

  return pickContainingFragment(eroded as TurfFeature<MultiPolygonGeom>, polys);
}

// Plain union-find (no distance test baked in).
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
  const halfThresholdKm = (thresholdM / 2) / 1000;

  // Which zones become ONE row, including transitively across a chain -
  // governed by the single `thresholdM` parameter (25 m in production,
  // matching kProximityTriggerM), AND now gated on influence_level equality
  // (Q3D). This is a group-FORMATION gate folded directly into the isLinked
  // predicate, not a post-hoc filter on the union-find result: a level-
  // unequal pair is never linked in the first place and can never become
  // part of the same connected component, even transitively through a third
  // zone. Zones with no influenceLevel supplied default to 1 (see ZoneInput).
  const groups = unionFindGroups(
    sorted.length,
    (i, j) =>
      (sorted[i].influenceLevel ?? 1) === (sorted[j].influenceLevel ?? 1) &&
      isWithin(features[i], features[j], thresholdM),
  );

  const result: MergeGroup[] = [];
  for (const idxs of groups) {
    if (idxs.length < 2) continue; // gap beyond thresholdM: nothing to merge, group dropped entirely

    // idxs are indices into `sorted` (already oldest-first), so idxs[0] is
    // the oldest member of this connected component - the survivor, even
    // if it is not the zone that triggered this claim.
    const groupIdxsAsc = [...idxs].sort((a, b) => a - b);
    const survivorIdx = groupIdxsAsc[0];
    const absorbedIds = groupIdxsAsc.slice(1).map((i) => sorted[i].id);
    const members = groupIdxsAsc.map((i) => features[i]) as TurfFeature<PolygonGeom>[];

    // trueUnion() only returns null on a hard Turf failure; unionAll(members)
    // is the same-shape fallback in that case.
    const sealed = trueUnion(members, halfThresholdKm) ?? unionAll(members)!;
    const geometry = sealed.geometry as { type: 'Polygon'; coordinates: number[][][] };

    result.push({ survivorId: sorted[survivorIdx].id, absorbedIds, geometry });
  }
  return result;
}

// ---------------------------------------------------------------------------
// computeZoneSplit - reversible split on re-run of part of a same-level-fused
// zone (AC-7). Pure, no I/O: takes the existing zone's stored ring and the
// re-run's own newly-captured ring, classifies the relationship, and (for a
// genuine partial overlap) computes the remainder geometry via Turf
// `difference`, subject to a sliver-tolerance floor. The caller (handler.ts)
// owns row selection and the apply_zone_split RPC write; this function never
// touches the database.
// ---------------------------------------------------------------------------

export type SplitCase = 'partialOverlap' | 'fullContainment' | 'noOverlap';

export interface ZoneSplitResult {
  case: SplitCase;
  remainder: { type: 'Polygon' | 'MultiPolygon'; coordinates: unknown } | null;
  remainderDiscarded: boolean;
}

export function computeZoneSplit(
  existingRing: number[][],
  newRing: number[][],
  minFragmentAreaSqm: number,
): ZoneSplitResult {
  const existing = toTurfPolygon(existingRing);
  const incoming = toTurfPolygon(newRing);

  // Full containment: the re-run's own polygon fully encloses the existing
  // zone from outside. This is the pre-existing ownedOverlapIds containment
  // path (AC-14's note), never the AC-7 split path - excluded here before
  // the intersection test below so it is never misclassified as a partial
  // overlap.
  if (booleanContains(incoming, existing)) {
    return { case: 'fullContainment', remainder: null, remainderDiscarded: false };
  }

  if (!booleanIntersects(existing, incoming)) {
    return { case: 'noOverlap', remainder: null, remainderDiscarded: false };
  }

  // Genuine partial overlap: the re-run retraces PART of the existing zone's
  // own edge. Subtract the re-run's polygon from the existing zone's stored
  // geometry - this is the ONE new boolean-geometry operation this feature
  // adds server-side (AC-1's sliver needs none, see the client-side capture
  // logic in lasso.dart).
  const diff = difference(featureCollection([existing, incoming]));
  if (!diff) {
    // Turf's difference returns null when the subtraction leaves nothing -
    // the re-run's polygon fully consumed the existing zone's area even
    // though it did not geometrically CONTAIN it (e.g. an irregular re-run
    // that still covers every remaining scrap). Treat identically to a
    // below-floor remainder: nothing meaningful survives of the old
    // boundary, so the re-run absorbs the whole prior area.
    return { case: 'partialOverlap', remainder: null, remainderDiscarded: true };
  }

  const remainderAreaSqm = turfArea(diff);
  if (remainderAreaSqm < minFragmentAreaSqm) {
    // Sliver tolerance (AC-7's unwanted-behaviour clause): discard geometric
    // noise rather than persisting a near-zero-area row. The re-run's own
    // polygon absorbs that ground instead - handled by the caller's ordinary
    // claim/insert path, not by this function.
    return { case: 'partialOverlap', remainder: null, remainderDiscarded: true };
  }

  return {
    case: 'partialOverlap',
    remainder: diff.geometry as { type: 'Polygon' | 'MultiPolygon'; coordinates: unknown },
    remainderDiscarded: false,
  };
}

// ---------------------------------------------------------------------------
// computeLevelUpOutcome - repeat-run damping / level-up cooldown (AC-8).
// Pure, no I/O: given a zone's prior last_active_at, the current time, the
// cooldown window and the zone's current influence_level, decides whether
// the cooldown is still active and what the zone's next level should be
// (clamped at 15). The caller (handler.ts) owns reading last_active_at before
// it is overwritten and writing the outcome back via the merge/level-up RPC.
// ---------------------------------------------------------------------------

export interface LevelUpOutcome {
  cooldownActive: boolean;
  nextLevel: number;
}

export function computeLevelUpOutcome(
  priorLastActiveAt: string | null,
  nowMs: number,
  cooldownMs: number,
  currentLevel: number,
): LevelUpOutcome {
  // A zone with no recorded prior activity (first-ever claim) has nothing to
  // damp against - never cooldown-active.
  const cooldownActive = priorLastActiveAt != null &&
    (nowMs - Date.parse(priorLastActiveAt)) < cooldownMs;

  const nextLevel = cooldownActive ? currentLevel : Math.min(15, currentLevel + 1);

  return { cooldownActive, nextLevel };
}
