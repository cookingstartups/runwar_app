// supabase/functions/tests/claim_territory_ordinary_merge_hole_preservation_test.ts
//
// Tests for: preserve carved holes on ordinary-claim merges in
// claim_territory (handler.ts's merge-candidate construction, two call
// sites: the initial merge-candidate build at :765 and the
// split-reconciliation rebuild at :1025). Unlike
// geometry_hole_preservation_class_test.ts (which drives computeZoneMerges
// directly with a hand-built ZoneInput{holes}, proving the downstream
// union/turf machinery is already hole-aware), these tests drive the
// merge-candidate CONSTRUCTION itself.
//
// Wiring note (this file's real-vs-mirror discipline): the two real call
// sites (:765, :1025) live inside handleClaimTerritoryRequest/
// runSplitAndMerge's own private loop bodies with no injectable client for
// their own initial SELECT (matching this repo's own established boundary,
// see claim_territory_merge_wiring_test.ts's header comment), so neither is
// directly callable end to end from a test. Rather than hand-copying that
// construction logic into a test-local mirror (which could silently drift
// from the real code), buildCandidateInputsFixed/buildReconciledInputsFixed
// below call the REAL, exported `ringSetsOf` directly - the exact function
// GREEN inserted at both real call sites - and apply only the same trivial
// arity glue (filter + map) that sits at those call sites, taken verbatim
// from design.md section 6.3's own "Change" column. The only thing that
// could silently drift is that trivial glue itself, which
// ANCHOR_RING_SETS_OF_USAGE below independently guards by asserting the
// real handler.ts source literally invokes `ringSetsOf(` at both real call
// sites (and no longer invokes the old flat `outlinesOf(geom)` /
// `outlinesOf(remainderGeom)` shape there) - a landmark-anchored
// source-inspection check, fails loudly if the landmark is missing, mirroring
// claim_territory_merge_wiring_test.ts's own established convention for
// this exact class of non-injectable boundary.
//
// Run: ~/.deno/bin/deno test --allow-all supabase/functions/tests/claim_territory_ordinary_merge_hole_preservation_test.ts

import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { outlinesOf, ringSetsOf, runSplitAndMerge, type SplitMergeDbClient, type SplitMergeSuccess } from '../claim_territory/handler.ts';
import { computeNextInfluenceLevel, computeZoneMerges, computeZoneSplit } from '../claim_territory/merge_geometry.ts';
import type { MergeGroup, ZoneInput } from '../claim_territory/merge_geometry.ts';

const HANDLER_SRC_PATH = new URL('../claim_territory/handler.ts', import.meta.url);

function readHandlerSrc(): string {
  return Deno.readTextFileSync(HANDLER_SRC_PATH);
}

const LAT0 = 39.470000; // Valencia, matching every other claim_territory test file
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

function lngAt(offsetM: number): number {
  return 33.0 + offsetM / LNG_M;
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

// ---------------------------------------------------------------------------
// Thin wrappers around the REAL, exported `ringSetsOf` - the exact function
// GREEN inserted at handler.ts's two real call sites (:765, :1025). The only
// local code here is the trivial arity glue (filter + map) taken verbatim
// from design.md section 6.3's "Change" column; all hole-preservation logic
// itself lives in the real, imported `ringSetsOf`. See file header for the
// accompanying source-inspection anchor that independently confirms the real
// call sites actually use this same function.
// ---------------------------------------------------------------------------

interface CandidateRow {
  id: string;
  geomJson: { type?: string; coordinates?: unknown };
  createdAt: string;
  influenceLevel: number;
}

// Mirrors handler.ts:765's fixed mapping verbatim (design.md 6.3, "Change"
// column): `ringSetsOf(geom).filter(...).map((rs) => ({ id, ring: rs[0],
// holes: rs.length > 1 ? rs.slice(1) : undefined, createdAt, influenceLevel }))`.
function buildCandidateInputsFixed(row: CandidateRow): ZoneInput[] {
  return ringSetsOf(row.geomJson)
    .filter((rs) => rs[0] && rs[0].length >= 3)
    .map((rs) => ({
      id: row.id,
      ring: rs[0],
      holes: rs.length > 1 ? rs.slice(1) : undefined,
      createdAt: row.createdAt,
      influenceLevel: row.influenceLevel,
    }));
}

// Mirrors handler.ts:1025's fixed reconciliation-loop mapping verbatim
// (design.md 6.3, "Change" column): same exterior/holes split, applied to a
// split remainder rather than an initial candidate read.
function buildReconciledInputsFixed(
  id: string,
  remainderGeom: { type?: string; coordinates?: unknown },
  createdAt: string,
  influenceLevel: number,
): ZoneInput[] {
  return ringSetsOf(remainderGeom)
    .filter((rs) => rs[0] && rs[0].length >= 3)
    .map((rs) => ({
      id,
      ring: rs[0],
      holes: rs.length > 1 ? rs.slice(1) : undefined,
      createdAt,
      influenceLevel,
    }));
}

class RecordingDbClient implements SplitMergeDbClient {
  deletedIds: string[] = [];
  rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];

  from(_table: 'zones') {
    return {
      delete: () => ({
        eq: (_column: 'id', value: string) => {
          this.deletedIds.push(value);
          return Promise.resolve({ error: null });
        },
      }),
    };
  }

  rpc(fn: string, args: Record<string, unknown>) {
    this.rpcCalls.push({ fn, args });
    return Promise.resolve({ error: null });
  }
}

function flatMaps(ids: string[]) {
  return {
    influenceById: new Map(ids.map((id) => [id, 1])),
    influenceLevelById: new Map(ids.map((id) => [id, 1])),
    creditsEarnedById: new Map(ids.map((id) => [id, 0])),
    lastActiveAtById: new Map<string, string | null>(ids.map((id) => [id, null])),
    shieldActiveById: new Map(ids.map((id) => [id, false])),
    shieldExpiresAtById: new Map<string, string | null>(ids.map((id) => [id, null])),
  };
}

// ---------------------------------------------------------------------------
// AC-1 (primary wiring test): the initial merge-candidate build (:765).
// ---------------------------------------------------------------------------

Deno.test('AC-1 (wiring): a claimant\'s own next ordinary claim merging with their shield-carved donut zone must not silently refill the hole', async () => {
  // A large exterior with a large interior hole (40m, bigger than the
  // merge's own kMergeThresholdMeters=25 closing-buffer diameter) and a
  // genuine 5m gap to the new claim - both deliberately sized so this test
  // isolates the fix's own scope (candidate CONSTRUCTION populating
  // `holes`) from two adjacent, already-correct, unrelated properties of
  // the existing merge machinery: (1) computeZoneSplit's own overlap
  // classification (a zero-gap/touching pair gets classified as a
  // reversible-split re-run, not an ordinary merge - that classification is
  // pre-existing and out of scope), and (2) computeZoneMerges' trueUnion
  // dilate/erode closing-bridge step (already proven correct by
  // geometry_hole_preservation_class_test.ts), which - like any
  // morphological closing operation - can only ever fill a hole SMALLER
  // than its own closing diameter (2 * halfThresholdKm = 25m here); a
  // hole at or above that diameter is unaffected by the bridge regardless
  // of gap size, so this fixture exercises the real bridging code path
  // (needed for a genuine nonzero-gap proximity trigger) while keeping the
  // hole-preservation assertion decoupled from that unrelated diameter
  // limitation.
  const EXTERIOR = rect(33.000000, LAT0, 100, 100);
  const HOLE = rect(33.000000 + mLng(30), LAT0 + mLat(30), 40, 40);

  // The candidate row is built the same way handleClaimTerritoryRequest's
  // own :765 builds it, from a real SELECT-shaped donut geom_json - via the
  // real, exported, hole-aware ringSetsOf.
  const zoneInputs = buildCandidateInputsFixed({
    id: 'donut-zone',
    geomJson: { type: 'Polygon', coordinates: [EXTERIOR, HOLE] },
    createdAt: '2020-01-01T00:00:00.000Z',
    influenceLevel: 1,
  });
  assertEquals(zoneInputs.length, 1, 'sanity: a donut geom must construct exactly 1 candidate whose exterior carries the hole as `holes`, not 2 flat rings');
  assert(zoneInputs[0].holes && zoneInputs[0].holes.length === 1, 'sanity: the donut candidate must carry exactly one interior ring in `holes`');

  const newId = 'new-claim-zone';
  const newRing = rect(lngAt(105), LAT0, 100, 100); // 5m gap east of the donut's exterior, well inside the 25m merge threshold
  const newInput: ZoneInput = { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 1 };

  const inputs: ZoneInput[] = [...zoneInputs, newInput];

  const db = new RecordingDbClient();
  const result = await runSplitAndMerge({
    supabase: db,
    inputs,
    newId,
    newRing,
    now: '2026-07-21T12:00:00.000Z',
    kMergeThresholdMeters: 25,
    kMinSplitFragmentAreaSqm: 375,
    computeZoneSplit,
    computeZoneMerges,
    computeNextInfluenceLevel,
    ...flatMaps(['donut-zone', newId]),
  });

  assertFalse(result instanceof Response, 'runSplitAndMerge must not return an error response for this scenario');
  const mergeCall = db.rpcCalls.find((c) => c.fn === 'apply_zone_merge');
  assert(mergeCall, 'the donut zone and the new adjacent claim must merge, producing an apply_zone_merge RPC call');

  const writtenGeom = JSON.parse(mergeCall!.args.p_geom_json as string) as { type: string; coordinates: unknown };
  const members: number[][][][] = writtenGeom.type === 'MultiPolygon'
    ? (writtenGeom.coordinates as number[][][][])
    : [writtenGeom.coordinates as number[][][]];

  // The hole's center must still be excluded from the written geometry:
  // find whichever member contains the donut's original footprint and
  // check it has >= 2 rings (exterior + hole), per AC-1's literal wording.
  const holeCenter: [number, number] = [33.000000 + mLng(50), LAT0 + mLat(50)];
  const containingMember = members.find((rings) => pointInRing(holeCenter, rings[0]));
  assert(containingMember, 'expected the merged geometry to have a member whose exterior covers the donut zone\'s original footprint (including where its hole used to be)');
  assert(
    containingMember!.length >= 2,
    `AC-1: the merged zone's geom_json member covering the donut's original footprint must still carry the ` +
      `carved interior ring (coordinates.length >= 2), got ${containingMember!.length}. Reverting the fix ` +
      `(ringSetsOf's two call-site changes) makes this fail: the old merge-candidate construction ` +
      `(outlinesOf(geom).map(...)) promoted the hole ring to its own independent, non-holed candidate at the ` +
      `same row id, so the real union computed by runSplitAndMerge/computeZoneMerges silently filled the hole ` +
      `back in.`,
  );
});

// ---------------------------------------------------------------------------
// AC-2: the split-reconciliation rebuild (:1025).
// ---------------------------------------------------------------------------

Deno.test('AC-2: a split-reconciliation rebuild of an annular remainder must carry its interior ring(s) into the reconciled candidate, not lose them to a flat re-union', () => {
  // Same class of annular-remainder fixture already proven correct at the
  // computeZoneSplit level by geometry_hole_preservation_class_test.ts's
  // "computeZoneSplit annular remainder excludes the re-run footprint"
  // test: a strictly-interior re-run carves a genuine donut remainder. The
  // hole (40m) is sized above the merge threshold's own 25m closing-buffer
  // diameter for the same reason AC-1's fixture is - see AC-1's own comment
  // for the full rationale (decoupling this fix's scope from an unrelated,
  // already-correct property of trueUnion's dilate/erode bridge).
  const existingRing = rect(33.000000, LAT0, 100, 100);
  const reRunRing = rect(33.000000 + mLng(30), LAT0 + mLat(30), 40, 40);

  const splitResult = computeZoneSplit(existingRing, reRunRing, 1);
  assert(splitResult.case === 'partialOverlap', `expected a partial overlap (annular) case, got ${splitResult.case}`);
  assert(splitResult.remainder, 'expected a real annular remainder geometry to reconcile');

  // Reconcile the remainder the same way runSplitAndMerge's own :1025
  // reconciliation loop does it - via the real, exported, hole-aware
  // ringSetsOf.
  const reconciledInputs = buildReconciledInputsFixed(
    'zoneC-split-target',
    splitResult.remainder!,
    '2020-01-01T00:00:00.000Z',
    1,
  );
  assertEquals(reconciledInputs.length, 1, 'sanity: an annular remainder must reconcile to exactly 1 candidate whose exterior carries the annulus\'s hole as `holes`, not 2 flat rings');
  assert(reconciledInputs[0].holes && reconciledInputs[0].holes.length === 1, 'sanity: the reconciled candidate must carry exactly one interior ring in `holes`');

  // AC-2's own literal wording allows either outcome ("either merged with
  // another zone or left standing alone as its own single-member group").
  // Once the fix lands, a truly-alone reconciled candidate (nothing else to
  // merge with) correctly yields ZERO computeZoneMerges groups - nothing to
  // union, so no rewrite risk at all (computeZoneMerges drops any
  // connected component smaller than 2 members outright, by design; the
  // remainder's own already-correct apply_zone_split write, requirements.md
  // H2/H3, is what a truly-standalone row keeps). The behavioral case that
  // actually exercises this fix end to end is the "merged with another
  // zone" branch: feed the reconciled candidate into computeZoneMerges
  // alongside a second, genuinely distinct candidate within threshold, and
  // confirm the union that runSplitAndMerge would write still carries the
  // interior ring.
  const otherId = 'other-zone';
  const otherRing = rect(lngAt(105), LAT0, 100, 100); // 5m gap east of the annulus's exterior, well inside the 25m merge threshold
  const otherInput: ZoneInput = { id: otherId, ring: otherRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 1 };

  const groups: MergeGroup[] = computeZoneMerges([...reconciledInputs, otherInput], 25);
  assertEquals(groups.length, 1, 'expected the reconciled donut candidate and the other zone to resolve to exactly one merge group');

  const reRunCenter: [number, number] = [33.000000 + mLng(50), LAT0 + mLat(50)];
  const merged = groups[0].geometry as { type: string; coordinates: unknown };
  const members: number[][][][] = merged.type === 'MultiPolygon'
    ? (merged.coordinates as number[][][][])
    : [merged.coordinates as number[][][]];
  const containingMember = members.find((rings) => pointInRing(reRunCenter, rings[0]));
  assert(containingMember, 'expected the merged group\'s geometry to have a member covering the annulus\'s original footprint');
  assert(
    containingMember!.length >= 2,
    `AC-2: the merged candidate's geometry must still carry the annular remainder's interior ring ` +
      `(coordinates.length >= 2 for the member covering it), got ${containingMember!.length}. Reverting the ` +
      `fix makes this fail: the old split-reconciliation rebuild (outlinesOf(remainderGeom).map(...)) ` +
      `promoted the remainder's hole ring to its own independent, non-holed candidate at the same row id, so ` +
      `the real computeZoneMerges union silently filled the annulus back in before it was ever written.`,
  );
});

// ---------------------------------------------------------------------------
// AC-3 (non-regression, unwanted-behaviour): a genuinely disjoint legacy
// MultiPolygon row (two separate exteriors, no holes) must still surface as
// two independent merge candidates - this fix must not collapse them or
// attach one member's ring to another as a spurious "hole". Expected to
// PASS both before and after the fix (confirm-only).
// ---------------------------------------------------------------------------

Deno.test('AC-3 (non-regression): a legacy multi-outline row with two disjoint, non-holed exteriors still constructs two independent, hole-free merge candidates', () => {
  const memberA = rect(33.000000, LAT0, 40, 40);
  const memberB = rect(33.000000 + mLng(500), LAT0, 40, 40); // far apart, genuinely disjoint

  const zoneInputs = buildCandidateInputsFixed({
    id: 'legacy-multi-outline',
    geomJson: { type: 'MultiPolygon', coordinates: [[memberA], [memberB]] },
    createdAt: '2020-01-01T00:00:00.000Z',
    influenceLevel: 1,
  });
  // The scope of this AC is candidate CONSTRUCTION (design.md 6.3's own
  // note: "each member still becomes its own ZoneInput... two genuinely
  // disjoint same-owner exteriors still surface as two independent
  // candidates exactly as today"), not computeZoneMerges' own downstream
  // same-id grouping semantics (already-existing, out-of-scope behavior per
  // handler.ts's own :760-764 comment, "computeZoneMerges naturally dedupes
  // them back into one group since they were never actually apart" - that
  // dedup is deliberate today and unrelated to holes).
  assertEquals(zoneInputs.length, 2, 'a genuinely disjoint 2-member MultiPolygon must still construct 2 flat candidates, not collapse into 1');
  assertFalse(zoneInputs[0].ring === zoneInputs[1].ring, 'the two members must keep their own distinct rings, never merged into one at construction time');
  for (const z of zoneInputs) {
    assertFalse('holes' in z && Boolean(z.holes), 'neither disjoint member may have the OTHER member\'s ring spuriously attached as its own `holes` entry - each member has no interior rings of its own');
  }
});

// ---------------------------------------------------------------------------
// AC-4 (non-regression): a plain non-holed same-owner ordinary merge must
// produce a `holes`-free ZoneInput (undefined, never populated) through the
// exact same construction path used by AC-1/AC-2 above. Expected to PASS
// both before and after the fix (confirm-only).
// ---------------------------------------------------------------------------

Deno.test('AC-4 (non-regression): a plain simple-Polygon candidate (no interior rings) produces no `holes` key via the fixed construction path', () => {
  const plainRing = rect(33.000000, LAT0, 40, 40);
  const zoneInputs = buildCandidateInputsFixed({
    id: 'plain-zone',
    geomJson: { type: 'Polygon', coordinates: [plainRing] },
    createdAt: '2020-01-01T00:00:00.000Z',
    influenceLevel: 1,
  });
  assertEquals(zoneInputs.length, 1, 'a plain simple Polygon must construct exactly one candidate');
  assertFalse('holes' in zoneInputs[0] && Boolean(zoneInputs[0].holes), 'a non-holed candidate must never carry a populated `holes` key - this fix must not regress the overwhelmingly common non-holed case');
});

// ---------------------------------------------------------------------------
// Wiring anchor (landmark-anchored source inspection, matching
// claim_territory_merge_wiring_test.ts's own established convention for this
// exact non-injectable-boundary case): confirms the REAL handler.ts source
// actually calls the real, exported `ringSetsOf` at both real call sites
// (:765, :1025), and no longer builds candidates from the old flat,
// hole-blind `outlinesOf(geom)` / `outlinesOf(remainderGeom)` shape there -
// so buildCandidateInputsFixed/buildReconciledInputsFixed above (which
// import and call that same real function) cannot silently drift from what
// production actually does at those two sites. Fails loudly if the landmark
// is missing, rather than silently passing against stale wiring.
// ---------------------------------------------------------------------------

Deno.test('wiring anchor: handler.ts\'s two merge-candidate construction sites (:765, :1025) call the real ringSetsOf, not the flat hole-blind outlinesOf', () => {
  const src = readHandlerSrc();

  assert(
    src.includes('return ringSetsOf(geom)'),
    'Landmark not found: the initial merge-candidate build must call `ringSetsOf(geom)` directly. ' +
      'handler.ts\'s structure moved or the fix was reverted - update this anchor or restore the fix, do not delete this check.',
  );
  assertFalse(
    src.includes('return outlinesOf(geom).map((r2)'),
    'The initial merge-candidate build still uses the old flat, hole-blind outlinesOf(geom).map((r2) => ...) shape - the fix was reverted or never applied at this call site.',
  );

  assert(
    src.includes('ringSetsOf(remainderGeom)'),
    'Landmark not found: the split-reconciliation rebuild must call `ringSetsOf(remainderGeom)` directly. ' +
      'handler.ts\'s structure moved or the fix was reverted - update this anchor or restore the fix, do not delete this check.',
  );
  assertFalse(
    src.includes('for (const outlineRing of outlinesOf(remainderGeom))'),
    'The split-reconciliation rebuild still uses the old flat, hole-blind outlinesOf(remainderGeom) shape - the fix was reverted or never applied at this call site.',
  );

  // AC-5: outlinesOf's own three point-in-ring-test callers must remain
  // untouched (unchanged count/shape), confirming this fix did not widen its
  // blast radius beyond the two named merge-candidate-construction sites.
  const flatOutlinesCallCount = (src.match(/outlinesOf\(geom\)\.filter\(\(r\) => r\.length >= 3\)/g) ?? []).length;
  assertEquals(
    flatOutlinesCallCount,
    3,
    'AC-5: expected exactly 3 remaining point-in-ring-test call sites still using the flat outlinesOf(geom).filter(...) shape unchanged - a different count means this fix touched outlinesOf\'s other callers, which is out of scope.',
  );
});
