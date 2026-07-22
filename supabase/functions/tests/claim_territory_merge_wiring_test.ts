// supabase/functions/tests/claim_territory_merge_wiring_test.ts
//
// R2-AC1 invariant (never merge across owners/cities), R2's disputed-exclusion
// edge case, and Q2's oldest-survivor ordering, plus the unification
// aggregation rules (Q1-family).
//
// The aggregation rules and the atomic-write behavior live inside
// runSplitAndMerge (the split-then-merge orchestration extracted from
// handler.ts's request handler), which takes an injectable database client -
// see claim_territory_split_merge_reconciliation_test.ts for the original
// worked example of this pattern. Every assertion below that can be driven
// through runSplitAndMerge is executed against a real fake client and
// asserted on the actual RPC call it records, not on source text.
//
// What remains genuinely wiring-only is the merge-candidate SELECT's query
// scope (the DB query filters/ordering) and the disputed-outcome guard: both
// live in handleClaimTerritoryRequest itself, above and outside
// runSplitAndMerge's injection boundary, so they cannot be exercised without
// a live Supabase instance. Those checks stay as source inspection, but
// anchored to a specific structural landmark (the query's own distinctive
// column list, or the exact guard conditional) rather than a positional
// offset - and they fail loudly if the landmark itself is missing, instead
// of silently sliding to the wrong window.
//
// Run: npx deno test supabase/functions/tests/claim_territory_merge_wiring_test.ts

import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { runSplitAndMerge, type SplitMergeDbClient, type SplitMergeSuccess } from '../claim_territory/handler.ts';
import { computeNextInfluenceLevel, computeZoneMerges, computeZoneSplit } from '../claim_territory/merge_geometry.ts';
import type { MergeGroup, ZoneInput } from '../claim_territory/merge_geometry.ts';
import { area as turfArea } from 'https://esm.sh/@turf/area@7';

const SRC_PATH = new URL('../claim_territory/handler.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

// ---------------------------------------------------------------------------
// Anchored source-inspection helpers. Each locates a structural landmark
// that is unique in the file and fails the test immediately (not the
// assertion it backs) if that landmark is missing, rather than silently
// reading whatever text happens to sit at an offset.
// ---------------------------------------------------------------------------

function findAnchor(src: string, marker: string, label: string): number {
  const idx = src.indexOf(marker);
  assert(idx >= 0, `Landmark not found: ${label} ("${marker}"). handler.ts's structure moved - update this test's anchor, do not delete the check.`);
  return idx;
}

// The merge-candidate SELECT's own column list is unique in the file (it is
// the only place influence_level, credits_earned, last_active_at,
// shield_active and shield_expires_at are all selected together), so it is
// a stable anchor for the query chain regardless of where in the file the
// query itself lives.
const MERGE_CANDIDATE_SELECT_MARKER =
  "'id, geom_json, created_at, influence, influence_level, credits_earned, last_active_at, shield_active, shield_expires_at'";

function mergeCandidateQueryBlock(src: string): string {
  const start = findAnchor(src, MERGE_CANDIDATE_SELECT_MARKER, 'merge-candidate SELECT column list');
  const end = src.indexOf(';', start);
  assert(end > start, 'the merge-candidate SELECT statement never terminates with a ";" after its landmark - source structure changed');
  return src.slice(start, end);
}

// The disputed-outcome guard and the conquered-response branch that follows
// it are both unique, exact strings - not fuzzy tokens - so this anchors
// directly to the guard itself rather than to some earlier, unrelated
// mention of "disputedId".
function mergeGuardBlock(src: string): string {
  const start = findAnchor(src, 'if (!disputedId) {', 'disputed-outcome merge guard');
  const end = findAnchor(src, 'if (conqueredId) {', 'post-merge conquered-response branch');
  assert(end > start, 'the conquered-response branch appears before the disputed guard - source order changed, re-derive this anchor pair');
  return src.slice(start, end);
}

Deno.test('R2-AC1 invariant: the merge candidate query scopes to owner_id AND city', () => {
  const block = mergeCandidateQueryBlock(readSrc());
  assert(block.includes("eq('owner_id'"),
    "The merge query must filter .eq('owner_id', playerId) so merges never cross owners");
  assert(block.includes("eq('city'"),
    "The merge query must filter .eq('city', city) so merges never cross cities");
});

Deno.test('Q2: merge candidates are ordered oldest-first so the surviving id is well-defined', () => {
  const block = mergeCandidateQueryBlock(readSrc());
  assert(block.includes("order('created_at'"),
    'The merge query must order by created_at so "oldest survives" is well-defined, not query-order-dependent');
});

Deno.test('R2 edge case: merge never runs for a disputed outcome', () => {
  const block = mergeGuardBlock(readSrc());
  assert(block.includes('runSplitAndMerge('),
    'The merge/split orchestration call must be nested inside the `if (!disputedId)` guard so it never runs when this claim resolved to disputed');
});

// ---------------------------------------------------------------------------
// Executing coverage for the unification aggregation rules, driven through
// the real runSplitAndMerge against a recording fake client. Two zones,
// same owner/city/level, close enough to merge (5m gap, well inside the
// 25m threshold) and not overlapping (so no split branch fires) - only the
// unification path under test runs.
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

interface ZoneField {
  influence?: number;
  influenceLevel?: number;
  creditsEarned?: number;
  lastActiveAt?: string | null;
  shieldActive?: boolean;
  shieldExpiresAt?: string | null;
}

// Runs one merge scenario: an existing zone z1 (older) plus a new claim
// (newId, 5m away, same level) merge into one survivor. `fields` supplies
// per-zone overrides for the fields the unification rules aggregate.
async function runMergeScenario(
  z1Fields: ZoneField,
  newFields: ZoneField,
  onGroups?: (groups: MergeGroup[]) => void,
): Promise<{ db: RecordingDbClient; result: Response | SplitMergeSuccess; mergeCall: { fn: string; args: Record<string, unknown> } | undefined }> {
  const newId = 'new-claim-zone';
  const z1Ring = metresRing(33.0, LAT0, 40, 40);
  const newRing = metresRing(lngAt(45), LAT0, 40, 40); // 5m gap from z1's east edge

  const inputs: ZoneInput[] = [
    { id: 'z1-older', ring: z1Ring, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: z1Fields.influenceLevel ?? 2 },
    { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: newFields.influenceLevel ?? 2 },
  ];

  const influenceById = new Map([['z1-older', z1Fields.influence ?? 1], [newId, newFields.influence ?? 1]]);
  const influenceLevelById = new Map([['z1-older', z1Fields.influenceLevel ?? 2], [newId, newFields.influenceLevel ?? 2]]);
  const creditsEarnedById = new Map([['z1-older', z1Fields.creditsEarned ?? 0], [newId, newFields.creditsEarned ?? 0]]);
  const lastActiveAtById = new Map<string, string | null>([
    ['z1-older', z1Fields.lastActiveAt ?? null],
    [newId, newFields.lastActiveAt ?? null],
  ]);
  const shieldActiveById = new Map([['z1-older', z1Fields.shieldActive ?? false], [newId, newFields.shieldActive ?? false]]);
  const shieldExpiresAtById = new Map<string, string | null>([
    ['z1-older', z1Fields.shieldExpiresAt ?? null],
    [newId, newFields.shieldExpiresAt ?? null],
  ]);

  const db = new RecordingDbClient();
  const spyComputeZoneMerges: typeof computeZoneMerges = (zones, thresholdM) => {
    const groups = computeZoneMerges(zones, thresholdM);
    onGroups?.(groups);
    return groups;
  };
  const result = await runSplitAndMerge({
    supabase: db,
    inputs,
    newId,
    newRing,
    now: '2026-07-21T12:00:00.000Z',
    kMergeThresholdMeters: 25,
    kMinSplitFragmentAreaSqm: 375,
    computeZoneSplit,
    computeZoneMerges: spyComputeZoneMerges,
    computeNextInfluenceLevel,
    influenceById,
    influenceLevelById,
    creditsEarnedById,
    lastActiveAtById,
    shieldActiveById,
    shieldExpiresAtById,
  });

  const mergeCall = (result instanceof Response) ? undefined : db.rpcCalls.find((c) => c.fn === 'apply_zone_merge');
  return { db, result, mergeCall };
}

Deno.test('Unification keeps no history: absorbed zone ids are passed to the atomic merge RPC for deletion, not lineage-tracked', async () => {
  const { result, mergeCall } = await runMergeScenario({}, {});
  assertFalse(result instanceof Response, 'runSplitAndMerge must not return an error response for this scenario');
  assert(mergeCall, 'the two adjacent, equal-level zones must merge, producing an apply_zone_merge RPC call');
  assertEquals(mergeCall!.fn, 'apply_zone_merge',
    'the merge path must delete absorbed rows outright via the atomic apply_zone_merge RPC, not lineage-track them');
  assertEquals(mergeCall!.args.p_absorbed_ids, ['new-claim-zone'],
    'the absorbed zone ids must be passed to apply_zone_merge so it deletes them in the same transaction as the survivor write');
  assertFalse('parent_id' in mergeCall!.args,
    'no parent_id lineage write is permitted - unification keeps no history, exactly one row survives');
});

Deno.test('Unification takes the MAX influence_level across the merged group (never summed, never a free level-up)', async () => {
  // Both zones share level 2 (the level gate requires equality to merge at
  // all); the survivor's new level must be computeNextInfluenceLevel(2) = 3,
  // not 2+2=4 (a sum) and not left at 2 (no level-up).
  const { mergeCall } = await runMergeScenario({ influenceLevel: 2 }, { influenceLevel: 2 });
  assert(mergeCall, 'expected a merge RPC call');
  assertEquals(mergeCall!.args.p_influence_level, 3,
    'influence_level must be computeNextInfluenceLevel(MAX across the group) = 3, never a sum (4) and never left unchanged (2)');
});

Deno.test('Unification applies the survivor UPDATE and absorbed DELETEs atomically via the apply_zone_merge RPC, not step-wise table writes', async () => {
  // SplitMergeDbClient's own type only exposes delete() and rpc() - there is
  // no update() to call even if the implementation wanted one, so a
  // step-wise UPDATE is structurally impossible through this injection
  // boundary. What an executing test can add on top of that is proving the
  // one call that IS made really is the RPC, with the survivor/absorbed ids
  // it names, and that an RPC failure is surfaced rather than swallowed
  // (covered by the "failed apply_zone_merge RPC" case in
  // claim_territory_split_merge_reconciliation_test.ts).
  const { mergeCall } = await runMergeScenario({}, {});
  assert(mergeCall, 'expected a merge RPC call');
  assertEquals(mergeCall!.args.p_survivor_id, 'z1-older');
  assertEquals(mergeCall!.args.p_absorbed_ids, ['new-claim-zone']);
});

Deno.test('Unification aggregates additive fields into the survivor', async () => {
  const { mergeCall } = await runMergeScenario({ influence: 5 }, { influence: 3 });
  assert(mergeCall, 'expected a merge RPC call');
  assertEquals(mergeCall!.args.p_influence, 8,
    'the survivor row update must aggregate influence (sum across the merged group: 5 + 3 = 8), not just copy one member\'s value');
});

Deno.test('Unification sums credits_earned across the merged group', async () => {
  const { mergeCall } = await runMergeScenario({ creditsEarned: 40 }, { creditsEarned: 10 });
  assert(mergeCall, 'expected a merge RPC call');
  assertEquals(mergeCall!.args.p_credits_earned, 50,
    'credits_earned aggregation must sum group members (40 + 10 = 50), not copy a single value');
});

Deno.test('Unification takes the max last_active_at across the merged group', async () => {
  const older = '2026-01-01T00:00:00.000Z';
  const newer = '2026-06-01T00:00:00.000Z';
  const { mergeCall } = await runMergeScenario({ lastActiveAt: older }, { lastActiveAt: newer });
  assert(mergeCall, 'expected a merge RPC call');
  assertEquals(mergeCall!.args.p_last_active_at, newer,
    'last_active_at aggregation must scan group members for the max value, not copy a single member\'s value');
});

Deno.test('Unification recomputes area_m2 from the merged geometry instead of summing source areas', async () => {
  let capturedGroups: MergeGroup[] = [];
  const { mergeCall } = await runMergeScenario({}, {}, (groups) => {
    capturedGroups = groups;
  });
  assert(mergeCall, 'expected a merge RPC call');
  assertEquals(capturedGroups.length, 1, 'expected exactly one merge group');

  const expectedAreaM2 = turfArea(capturedGroups[0].geometry);
  const singleZoneAreaM2 = 40 * 40; // one 40x40m source square
  const naiveSummedAreaM2 = 2 * singleZoneAreaM2; // what a wrong sum-of-sources implementation would report instead

  assertEquals(mergeCall!.args.p_area_m2, expectedAreaM2,
    'p_area_m2 must be exactly turfArea(group.geometry) recomputed from the actual merged shape, not any other figure');
  assert(expectedAreaM2 !== naiveSummedAreaM2,
    'this scenario\'s own expected area must differ from the naive source-area sum, or the exact-match assertion above would not distinguish the two');
});

Deno.test('Unification updates shield_active/shield_expires_at using ANY-active / max-expiry semantics', async () => {
  const earlierExpiry = '2026-08-01T00:00:00.000Z';
  const laterExpiry = '2026-09-01T00:00:00.000Z';
  const { mergeCall } = await runMergeScenario(
    { shieldActive: false, shieldExpiresAt: earlierExpiry },
    { shieldActive: true, shieldExpiresAt: laterExpiry },
  );
  assert(mergeCall, 'expected a merge RPC call');
  assertEquals(mergeCall!.args.p_shield_active, true,
    'shield_active must be true because at least one group member (the new claim) has an active shield');
  assertEquals(mergeCall!.args.p_shield_expires_at, laterExpiry,
    'shield_expires_at must be the latest expiry among the SHIELDED members only');
});
