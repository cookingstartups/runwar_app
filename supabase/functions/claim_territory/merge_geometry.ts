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
import {
  bboxCenterLat,
  cellSetDifference,
  coveredCellSet,
  dissolveCells,
  kHexCellCircumradiusM,
} from './hex_quantize.ts';

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
// unionCandidateRings - unions two or more freshly-closed loops FROM THE SAME
// claim request (a single run that self-closed more than one loop) into ONE
// sealed shape, reusing the exact same trueUnion morphological-closing
// algorithm computeZoneMerges above already uses for merging a new claim
// with pre-existing adjacent territory. No new geometry algorithm is
// introduced here - this is the same dilate/union/erode contract at the same
// thresholdM, applied to sibling rings instead of database rows.
//
// Grouping (WHICH rings belong together) is decided by the caller BEFORE
// this function is called - handler.ts only calls this once per already-
// formed group, on rings the client (or an equivalent server-side pass) has
// already established are mutually within thresholdM. This function only
// computes the union geometry for a group that is already fixed; it never
// re-decides membership and never drops a member silently.
// ---------------------------------------------------------------------------

export function unionCandidateRings(
  rings: number[][][],
  thresholdM: number,
):
  | { type: 'Polygon'; coordinates: number[][][] }
  | { type: 'MultiPolygon'; coordinates: number[][][][] } {
  if (rings.length === 0) {
    throw new Error('unionCandidateRings: at least one ring is required');
  }
  if (rings.length === 1) {
    return { type: 'Polygon', coordinates: [closedRing(rings[0])] };
  }
  const halfThresholdKm = (thresholdM / 2) / 1000;
  const features = rings.map((r) => toTurfPolygon(r)) as TurfFeature<PolygonGeom>[];
  const sealed = trueUnion(features, halfThresholdKm) ?? unionAll(features)!;
  return sealed.geometry as
    | { type: 'Polygon'; coordinates: number[][][] }
    | { type: 'MultiPolygon'; coordinates: number[][][][] };
}

// ---------------------------------------------------------------------------
// computeZoneSplit - reversible split on re-run of part of a same-level-fused
// zone (AC-7, later superseded by app-T0587's snap-to-boundary behaviour
// below). Pure, no I/O: takes the existing zone's stored ring and the
// re-run's own newly-captured ring, classifies the relationship, and (for a
// genuine partial overlap) computes the remainder geometry. The caller
// (handler.ts) owns row selection and the apply_zone_split RPC write; this
// function never touches the database.
//
// app-T0587 - snap the cut to the nearest existing hex-grid boundary instead
// of discarding a below-floor fragment:
//   Both the existing zone's stored ring and the incoming re-run ring are
//   quantised to the SAME shared hex grid (hex_quantize.ts, ported 1:1 from
//   lib/geo/hex_quantize.dart - kHexCellCircumradiusM must stay numerically
//   identical between the two). The remainder is then the set of existing
//   grid cells NOT covered by the incoming ring, dissolved back into ring
//   geometry - i.e. the split cut is nudged onto the nearest cell edge
//   rather than left wherever the raw GPS traces happened to cross. This
//   bounds the snap's displacement to at most one cell's extent
//   (kHexCellCircumradiusM, currently 10 m) from the true cut, per the task's
//   worked-example comparison, and - because the grid is a fixed shared
//   reference rather than derived from either trace - repeated re-runs of
//   the same ground converge onto the same cell boundaries instead of
//   drifting or shredding the zone into more rows with each pass.
//
//   The old kMinSplitFragmentAreaSqm area floor is superseded, not layered
//   alongside this: a hex-quantised remainder is either empty (no cell
//   survives the difference - the re-run's own polygon absorbed every cell
//   of the old zone at grid resolution, so the old row is fully discarded
//   exactly as an above-floor-but-now-covered fragment always should be) or
//   it is a real, non-degenerate set of whole grid cells - there is no
//   floating-point-noise sliver left for an area floor to catch, because
//   quantisation already collapsed anything smaller than a single cell to
//   nothing before the floor would ever run. Running both mechanisms would
//   leave two conflicting sources of truth for "was this fragment kept or
//   discarded"; only the grid-emptiness check decides now.
//
//   Fallback: if the existing zone's ring is too small for the hex grid to
//   cover ANY cell center at all (coveredCellSet returns empty - see
//   hex_quantize.ts's own documented degenerate-input contract), quantised
//   snapping has nothing to work from. In that case this function falls
//   back to the pre-T0587 raw-geometry Turf `difference` + area-floor path
//   so a legitimately tiny existing zone is not spuriously wiped: the floor
//   check on raw geometry is a *fallback safety net* for this one degenerate
//   case, not a live rule that runs in the ordinary quantised path above.
// ---------------------------------------------------------------------------

export type SplitCase = 'partialOverlap' | 'fullContainment' | 'noOverlap';

export interface ZoneSplitResult {
  case: SplitCase;
  remainder: { type: 'Polygon' | 'MultiPolygon'; coordinates: unknown } | null;
  remainderDiscarded: boolean;
}

function rawDifferenceFallback(
  existing: TurfFeature<PolygonGeom>,
  incoming: TurfFeature<PolygonGeom>,
  minFragmentAreaSqm: number,
): ZoneSplitResult {
  const diff = difference(featureCollection([existing, incoming]));
  if (!diff) {
    return { case: 'partialOverlap', remainder: null, remainderDiscarded: true };
  }
  const remainderAreaSqm = turfArea(diff);
  if (remainderAreaSqm < minFragmentAreaSqm) {
    return { case: 'partialOverlap', remainder: null, remainderDiscarded: true };
  }
  return {
    case: 'partialOverlap',
    remainder: diff.geometry as { type: 'Polygon' | 'MultiPolygon'; coordinates: unknown },
    remainderDiscarded: false,
  };
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
  // own edge. Snap the cut to the shared hex grid (see the module-level
  // comment above) using the EXISTING zone's own bbox-center latitude as the
  // reference latitude for both quantisations - fixed per zone, so repeated
  // re-splits of the same row always project onto the identical grid rather
  // than drifting with each re-run's own bbox.
  const refLatDeg = bboxCenterLat(existingRing);
  const existingCells = coveredCellSet(existingRing, kHexCellCircumradiusM, refLatDeg);
  if (existingCells.size === 0) {
    // Degenerate case: the existing zone is too small for the grid to cover
    // even one cell center. Fall back to raw-geometry difference with the
    // pre-T0587 area floor rather than spuriously wiping a real (if tiny)
    // zone. See the module-level comment above.
    return rawDifferenceFallback(existing, incoming, minFragmentAreaSqm);
  }

  const newCells = coveredCellSet(newRing, kHexCellCircumradiusM, refLatDeg);
  const remainderCells = cellSetDifference(existingCells, newCells);
  if (remainderCells.length === 0) {
    // Nothing of the existing zone survives at grid resolution - the re-run
    // absorbs the whole prior area, exactly as a full raw-geometry
    // consumption always did.
    return { case: 'partialOverlap', remainder: null, remainderDiscarded: true };
  }

  const rings = dissolveCells(remainderCells, kHexCellCircumradiusM, refLatDeg);
  if (rings.length === 0) {
    // Should not happen given a non-empty cell set, but mirrors the
    // degenerate-output contract documented in hex_quantize.ts - treat as
    // nothing usable survived rather than crash.
    return { case: 'partialOverlap', remainder: null, remainderDiscarded: true };
  }

  const geometry = rings.length === 1
    ? { type: 'Polygon' as const, coordinates: [closedRing(rings[0])] }
    : {
      type: 'MultiPolygon' as const,
      coordinates: rings.map((r) => [closedRing(r)]),
    };

  return {
    case: 'partialOverlap',
    remainder: geometry,
    remainderDiscarded: false,
  };
}

// ---------------------------------------------------------------------------
// computeNextInfluenceLevel - repeat-run damping.
// Pure, no I/O: every re-claim of the same ground levels the zone up by one,
// with no time-based gate of any kind. The only limit is the level-15 cap,
// which mirrors the zones.influence_level CHECK constraint (1 <= level <=
// 15) so this function's own ceiling can never disagree with the database's.
// ---------------------------------------------------------------------------

export function computeNextInfluenceLevel(currentLevel: number): number {
  return Math.min(15, currentLevel + 1);
}

// ---------------------------------------------------------------------------
// computeClaimInfluence - sublinear, area-scaled claim reward.
//
// Replaces a flat `influence: 1` previously assigned to every new zone,
// every conquest, and every merge survivor regardless of captured size. A
// flat award made the cheapest claim that only just clears the server's
// area floor (evaluateCapturedRingGates's minCapturedAreaSqm, 1500 sqm)
// exactly as valuable as a claim covering ten times more ground - the
// dominant strategy became spamming minimum-size loops up to the daily
// claim cap rather than running a genuinely larger one, and no floor value
// can fix that on its own (raising the floor only raises the price of the
// cheapest spammable claim, it does not stop spamming from being optimal).
//
// Square-root scaling ties the award to real captured area while damping
// runaway growth: doubling area does not double the award, so a merge
// survivor's influence must be recomputed straight from its OWN final
// area (this function, fed the merged geometry's true area) rather than
// summed from the pre-merge members' influence values - the same
// never-sum-source-areas discipline handler.ts's survivorAreaM2 already
// applies to area itself (turfArea on the merge result, area double-counts
// otherwise). Summing sqrt-scaled per-member values instead of
// recomputing from the total would still reward splitting a claim into
// many small pieces and merging them, because sqrt is concave: the sum of
// several sqrts of a total exceeds the sqrt of that total.
//
// kInfluenceAreaNormSqm is anchored to the same 1500 sqm the server's own
// area floor enforces (evaluateCapturedRingGates's minCapturedAreaSqm), so
// a claim that only just clears the floor keeps the pre-existing baseline
// influence of 1 - only a claim larger than the floor is ever worth more
// than the old flat award, never less. Clamped to [1, 15] to match
// INFLUENCE_MAX (see zones.influence's application-level range, mirrored
// in TerritoryService.computeDecayStep's own 1..15 clamp) so this new
// formula can never produce a value decay and display code doesn't
// already expect.
const kInfluenceAreaNormSqm = 1500;

export function computeClaimInfluence(areaM2: number): number {
  const raw = Math.sqrt(Math.max(0, areaM2) / kInfluenceAreaNormSqm);
  return Math.min(15, Math.max(1, raw));
}
