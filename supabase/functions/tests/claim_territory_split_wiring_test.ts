// supabase/functions/tests/claim_territory_split_wiring_test.ts
//
// The level-gated merge (AC-5, AC-13), the reversible split on re-run
// (AC-7), and the no-retroactive-fuse invariant (AC-9).
//
// The row selection, the RPC call shape, and the unconditional
// last_active_at write are covered wherever they are reachable through
// runSplitAndMerge (the split-then-merge orchestration extracted from
// handler.ts's request handler, which takes an injectable database client -
// see claim_territory_split_merge_reconciliation_test.ts for the original
// worked example). Assertions below that can be driven that way are run
// against a real fake client and checked against the actual call it
// recorded, not against source text.
//
// What remains genuinely wiring-only lives in handleClaimTerritoryRequest
// itself, above runSplitAndMerge's injection boundary: the merge-candidate
// query's own filters (which genuinely need a live Supabase instance to
// verify), and whether influenceLevel is actually threaded from the
// candidate-row SELECT into the ZoneInput objects handed to
// runSplitAndMerge (a fact about the SELECT-to-ZoneInput mapping, not about
// anything runSplitAndMerge itself does once it receives those objects).
// Those stay as source inspection, anchored to a specific structural
// landmark rather than a positional offset, and they fail loudly if the
// landmark itself is missing.
//
// The decision MATH behind the split (does this count as a partial overlap
// or a full containment, is the remainder above the sliver floor) has no
// I/O in it and is covered behaviourally instead, in
// claim_territory_split_geometry_test.ts. Repeat-run damping is now a
// level cap only - covered behaviourally by
// claim_territory_level_up_cap_test.ts against computeNextInfluenceLevel.
//
// Run: npx deno test supabase/functions/tests/claim_territory_split_wiring_test.ts

import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { runSplitAndMerge, type SplitMergeDbClient, type SplitMergeSuccess } from '../claim_territory/handler.ts';
import { computeNextInfluenceLevel, computeZoneMerges, computeZoneSplit } from '../claim_territory/merge_geometry.ts';
import type { ZoneInput } from '../claim_territory/merge_geometry.ts';

const SRC_PATH = new URL('../claim_territory/handler.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

// ---------------------------------------------------------------------------
// Anchored source-inspection helpers, shared shape with
// claim_territory_merge_wiring_test.ts: each locates a structural landmark
// unique in the file and fails immediately if it is missing, instead of
// silently reading whatever text happens to sit at some offset.
// ---------------------------------------------------------------------------

function findAnchor(src: string, marker: string, label: string): number {
  const idx = src.indexOf(marker);
  assert(idx >= 0, `Landmark not found: ${label} ("${marker}"). handler.ts's structure moved - update this test's anchor, do not delete the check.`);
  return idx;
}

const MERGE_CANDIDATE_SELECT_MARKER =
  "'id, geom_json, created_at, influence, influence_level, credits_earned, last_active_at, shield_active, shield_expires_at'";

function mergeCandidateQueryBlock(src: string): string {
  const start = findAnchor(src, MERGE_CANDIDATE_SELECT_MARKER, 'merge-candidate SELECT column list');
  const end = src.indexOf(';', start);
  assert(end > start, 'the merge-candidate SELECT statement never terminates with a ";" after its landmark - source structure changed');
  return src.slice(start, end);
}

// The candidate-row-to-ZoneInput mapping is the only ".map((r) => {" in the
// file (the other .map() calls are unrelated ring/coordinate transforms),
// and it is closed by the file's only ".flat();" call.
function candidateInputsMappingBlock(src: string): string {
  const start = findAnchor(src, '.map((r) => {', 'candidate-row-to-ZoneInput mapping');
  const end = findAnchor(src, '.flat();', 'end of candidate-row-to-ZoneInput mapping');
  assert(end > start, 'the ".flat();" landmark appears before the mapping it is meant to close - source order changed');
  return src.slice(start, end);
}

// ---------------------------------------------------------------------------
// AC-5 / AC-13 - level equality feeds into the merge candidate construction
// ---------------------------------------------------------------------------

Deno.test('the merge candidate ZoneInput carries influenceLevel through to computeZoneMerges', () => {
  const block = candidateInputsMappingBlock(readSrc());
  assert(block.includes('influenceLevel:'),
    'handler.ts must pass influenceLevel into each constructed ZoneInput so the level-equality '
      + 'gate inside computeZoneMerges has data to gate on');
});

Deno.test(
  'R2 invariant (unaffected by the level gate): the merge candidate query still scopes to owner_id, city and status owned',
  () => {
    const block = mergeCandidateQueryBlock(readSrc());
    assert(block.includes("eq('owner_id'"), "The merge query must still filter .eq('owner_id', playerId)");
    assert(block.includes("eq('city'"), "The merge query must still filter .eq('city', city)");
    assert(block.includes("eq('status', 'owned')"),
      "A disputed same-owner zone must still be excluded from the merge candidate set regardless "
        + 'of the new level-equality gate - the status filter and the level gate are independent');
  },
);

// ---------------------------------------------------------------------------
// AC-9 - no retroactive/periodic fuse
// ---------------------------------------------------------------------------

// Already true of today's source (one call site); expected to remain true
// after this feature ships - a regression lock against a future periodic
// job being added, not a new-behaviour probe. This is a whole-file exact
// occurrence count, not a positional slice, so it is not fragile to
// unrelated code motion within the file the way an indexOf-plus-substring
// window would be; it stays unchanged.
Deno.test('computeZoneMerges is only ever invoked from inside the claim request handler', () => {
  const src = readSrc();
  const occurrences = src.split('computeZoneMerges(').length - 1;
  assert(occurrences === 1,
    'computeZoneMerges must be called exactly once, from the claim-event merge block - a second '
      + 'call site anywhere in this file would indicate a periodic/retroactive fuse path, which '
      + 'AC-9 explicitly forbids');
});

// ---------------------------------------------------------------------------
// Executing coverage, driven through the real runSplitAndMerge against a
// recording fake client - mirrors claim_territory_merge_wiring_test.ts's
// scenario helper.
// ---------------------------------------------------------------------------

const LAT0 = 39.470000; // Valencia, matching the other claim_territory test files
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

function metresRing(lng0: number, lat0: number, widthM: number, heightM: number): number[][] {
  const dLng = widthM / LNG_M;
  const dLat = heightM / LAT_M;
  const a = [lng0, lat0];
  const b = [lng0 + dLng, lat0];
  const c = [lng0 + dLng, lat0 + dLat];
  const d = [lng0, lat0 + dLat];
  return [a, b, c, d, a];
}

function lngAt(offsetM: number): number {
  return 33.0 + offsetM / LNG_M;
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

Deno.test('unification still takes the MAX influence_level across an (now-guaranteed-equal-level) group', async () => {
  const newId = 'new-claim-zone';
  const z1Ring = metresRing(33.0, LAT0, 40, 40);
  const newRing = metresRing(lngAt(45), LAT0, 40, 40); // 5m gap, no split candidates

  const inputs: ZoneInput[] = [
    { id: 'z1-older', ring: z1Ring, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 4 },
    { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 4 },
  ];

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
    influenceById: new Map([['z1-older', 1], [newId, 1]]),
    influenceLevelById: new Map([['z1-older', 4], [newId, 4]]),
    creditsEarnedById: new Map([['z1-older', 0], [newId, 0]]),
    lastActiveAtById: new Map<string, string | null>([['z1-older', null], [newId, null]]),
    shieldActiveById: new Map([['z1-older', false], [newId, false]]),
    shieldExpiresAtById: new Map<string, string | null>([['z1-older', null], [newId, null]]),
  });

  assertFalse(result instanceof Response, 'runSplitAndMerge must not return an error response for this scenario');
  const mergeCall = db.rpcCalls.find((c) => c.fn === 'apply_zone_merge');
  assert(mergeCall, 'expected a merge RPC call for two touching, equal-level zones');
  assertEquals(mergeCall!.args.p_influence_level, 5,
    'influence_level must remain computeNextInfluenceLevel(MAX across the group) = 5, unchanged by the new level-equality gate');
});

Deno.test('last_active_at still refreshes unconditionally on every claim', async () => {
  const newId = 'new-claim-zone';
  const z1Ring = metresRing(33.0, LAT0, 40, 40);
  const newRing = metresRing(lngAt(45), LAT0, 40, 40);
  const staleTimestamp = '2020-01-01T00:00:00.000Z';

  const inputs: ZoneInput[] = [
    { id: 'z1-older', ring: z1Ring, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
    { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 1 },
  ];

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
    influenceById: new Map([['z1-older', 1], [newId, 1]]),
    influenceLevelById: new Map([['z1-older', 1], [newId, 1]]),
    creditsEarnedById: new Map([['z1-older', 0], [newId, 0]]),
    // Both members are at the same stale timestamp - the new claim has no
    // recorded last_active_at of its own (it did not exist before now), so
    // this proves the write is populated from real per-row data rather than
    // silently omitted or hardcoded to null.
    lastActiveAtById: new Map<string, string | null>([['z1-older', staleTimestamp], [newId, null]]),
    shieldActiveById: new Map([['z1-older', false], [newId, false]]),
    shieldExpiresAtById: new Map<string, string | null>([['z1-older', null], [newId, null]]),
  });

  assertFalse(result instanceof Response, 'runSplitAndMerge must not return an error response for this scenario');
  const mergeCall = db.rpcCalls.find((c) => c.fn === 'apply_zone_merge');
  assert(mergeCall, 'expected a merge RPC call');
  assertEquals(mergeCall!.args.p_last_active_at, staleTimestamp,
    'p_last_active_at must be populated from the per-row last_active_at data on every claim, never omitted or left null when data exists');
});

Deno.test('the split write goes through a dedicated apply_zone_split RPC', async () => {
  const newId = 'new-claim-zone';
  // The claim retraces the west half of an existing same-owner zone, a
  // genuine partial overlap whose remainder clears the sliver floor and is
  // kept - the same scenario shape as
  // claim_territory_split_merge_reconciliation_test.ts's split-remainder
  // case, kept self-contained here rather than depending on that file.
  const zoneRing = metresRing(33.0, LAT0, 40, 40);
  const newRing = metresRing(33.0, LAT0, 20, 40);

  const inputs: ZoneInput[] = [
    { id: 'zone-split-target', ring: zoneRing, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
    { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 1 },
  ];

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
    influenceById: new Map([['zone-split-target', 1], [newId, 1]]),
    influenceLevelById: new Map([['zone-split-target', 1], [newId, 1]]),
    creditsEarnedById: new Map([['zone-split-target', 0], [newId, 0]]),
    lastActiveAtById: new Map<string, string | null>([['zone-split-target', null], [newId, null]]),
    shieldActiveById: new Map([['zone-split-target', false], [newId, false]]),
    shieldExpiresAtById: new Map<string, string | null>([['zone-split-target', null], [newId, null]]),
  });

  assertFalse(result instanceof Response, 'runSplitAndMerge must not return an error response for this scenario');
  const splitCall = db.rpcCalls.find((c) => c.fn === 'apply_zone_split');
  assert(splitCall, 'the split write must go through a dedicated apply_zone_split RPC (one UPDATE, no absorbed-row DELETE)');
  assertEquals(splitCall!.args.p_zone_id, 'zone-split-target');
  assertFalse(
    db.rpcCalls.some((c) => c.fn === 'apply_zone_merge' && (c.args.p_absorbed_ids as string[])?.includes('zone-split-target')),
    'the split-remainder row must never also be absorbed by a merge - a split write and a merge-delete of the same row would race',
  );
});
