// supabase/functions/tests/claim_territory_split_merge_reconciliation_test.ts
//
// Real execution coverage for runSplitAndMerge (the split-then-merge
// orchestration extracted from claim_territory/handler.ts's request handler).
// Unlike the source-inspection wiring tests, this file drives the ACTUAL
// exported function against an injected fake database client and asserts
// on its real return value and the real calls the fake recorded - it would
// fail against the pre-fix code, not just confirm a string is present
// somewhere in the file.
//
// The bug this covers: `inputs` (the merge candidate list) is built once
// from a SELECT, then the split loop mutates the database directly
// (deleting a fully-absorbed candidate row, or shrinking one to its split
// remainder), without ever refreshing `inputs`. The merge computation then
// runs against that stale, pre-mutation list.
//
// Run: npx deno test supabase/functions/tests/claim_territory_split_merge_reconciliation_test.ts

import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  runSplitAndMerge,
  type SplitMergeDbClient,
  type SplitMergeSuccess,
} from '../claim_territory/handler.ts';
import { computeLevelUpOutcome, computeZoneMerges, computeZoneSplit } from '../claim_territory/merge_geometry.ts';
import type { ZoneInput } from '../claim_territory/merge_geometry.ts';

const LAT0 = 39.470000; // Valencia, same reference point used by the split geometry tests
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

// Records every delete-by-id and rpc call the fake receives, so a test can
// assert on exactly what was sent to the database, not just that the
// function returned without throwing.
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

Deno.test('a candidate row that the split loop deletes outright is never fed to the merge as a survivor or absorbed id', async () => {
  const newId = 'new-claim-zone';

  // zoneA-oldest: this claim's own ring retraces almost all of it, leaving
  // only a below-floor sliver - the split loop deletes this row outright
  // (see claim_territory_split_geometry_test.ts's identical scenario for
  // the underlying computeZoneSplit classification).
  const zoneARing = metresRing(33.0, LAT0, 40, 40);
  const newRing = metresRing(33.0, LAT0, 39, 40);

  // zoneB-newer: a genuinely separate zone, touching the new claim with a
  // 5m gap (well inside the 25m merge threshold), and NEWER than zoneA -
  // so it, not zoneA, must be the merge survivor once zoneA is correctly
  // dropped from the candidate list.
  const zoneBRing = metresRing(lngAt(39 + 5), LAT0, 40, 40);

  const inputs: ZoneInput[] = [
    { id: 'zoneA-oldest', ring: zoneARing, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
    { id: 'zoneB-newer', ring: zoneBRing, createdAt: '2023-06-01T00:00:00.000Z', influenceLevel: 1 },
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
    kLevelUpCooldownMs: 24 * 3600 * 1000,
    computeZoneSplit,
    computeZoneMerges,
    computeLevelUpOutcome,
    ...flatMaps(['zoneA-oldest', 'zoneB-newer', newId]),
  });

  assertFalse(result instanceof Response, 'runSplitAndMerge must not return an error response for this scenario');
  const success = result as SplitMergeSuccess;

  assert(db.deletedIds.includes('zoneA-oldest'), 'zoneA must be deleted by the split loop');

  const mergeCall = db.rpcCalls.find((c) => c.fn === 'apply_zone_merge');
  assert(mergeCall, 'a real merge must still happen between the new claim and the genuinely adjacent zoneB');

  assert(
    mergeCall!.args.p_survivor_id !== 'zoneA-oldest',
    'the deleted row must never be selected as the merge survivor - its UPDATE would match zero rows and the write would silently vanish',
  );
  const absorbedIds = mergeCall!.args.p_absorbed_ids as string[];
  assertFalse(
    absorbedIds.includes('zoneA-oldest'),
    'the deleted row must never be passed as an absorbed id either - it no longer exists to absorb',
  );

  assertEquals(mergeCall!.args.p_survivor_id, 'zoneB-newer', 'zoneB is the correct survivor once zoneA is excluded');
  assertEquals(absorbedIds, [newId], 'only the new claim is absorbed into zoneB');
  assertEquals(success.finalZoneId, 'zoneB-newer');
  assertEquals(success.merged, true);
  assertEquals(success.absorbedZoneIds, [newId]);
});

Deno.test('a candidate row with multiple stored outlines is deleted at most once, even when every outline independently qualifies for deletion', async () => {
  const newId = 'new-claim-zone-2';

  // A synthetic legacy multi-outline row: two far-apart squares sharing one
  // db row id. A large new claim ring covers almost all of both, leaving a
  // below-floor sliver on each - so BOTH outline entries independently
  // classify as a discard-and-delete split. Without a same-row guard, the
  // loop (which iterates one ZoneInput per outline) would issue the delete
  // twice for the same id.
  const outlineA = metresRing(0, LAT0, 20, 20);
  const outlineBAbs = metresRing(100 / LNG_M, LAT0, 20, 20);

  const newRing = metresRing(-5 / LNG_M, LAT0, 130, 19); // spans both squares, 1m short on height

  const inputs: ZoneInput[] = [
    { id: 'legacy-multi-outline', ring: outlineA, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
    { id: 'legacy-multi-outline', ring: outlineBAbs, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
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
    kLevelUpCooldownMs: 24 * 3600 * 1000,
    computeZoneSplit,
    computeZoneMerges,
    computeLevelUpOutcome,
    ...flatMaps(['legacy-multi-outline', newId]),
  });

  assertFalse(result instanceof Response, 'runSplitAndMerge must not return an error response for this scenario');

  const deletesForRow = db.deletedIds.filter((id) => id === 'legacy-multi-outline');
  assertEquals(
    deletesForRow.length,
    1,
    'a row with multiple outline entries must be deleted at most once, not once per outline',
  );
  assertFalse(
    inputsStillReferenceDeletedRow(result as SplitMergeSuccess, 'legacy-multi-outline'),
    'the deleted row must not surface anywhere in the merge outcome',
  );
});

function inputsStillReferenceDeletedRow(success: SplitMergeSuccess, deletedId: string): boolean {
  return success.finalZoneId === deletedId || success.absorbedZoneIds.includes(deletedId);
}

Deno.test('a candidate row that keeps a split remainder feeds the REMAINDER ring into the merge scan, not its pre-split full ring', async () => {
  const newId = 'new-claim-zone-3';

  const zoneCRing = metresRing(33.0, LAT0, 40, 40);
  // The claim retraces the west half of zoneC - a genuine partial overlap
  // whose remainder (the east half) clears the sliver floor and is kept
  // (identical geometry to the "roughly half" scenario in
  // claim_territory_split_geometry_test.ts).
  const newRing = metresRing(33.0, LAT0, 20, 40);

  const inputs: ZoneInput[] = [
    { id: 'zoneC-split-target', ring: zoneCRing, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
    { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 1 },
  ];

  // zoneC always ends up in the same merge group as the new claim here (its
  // ring overlaps newRing by construction of the split), so the group's
  // final geometry/area is not itself a useful probe - the union of
  // (remainder + newRing) and (stale full ring + newRing) covers the exact
  // same ground either way. What must be checked directly is the ring
  // actually HANDED to the merge computation for zoneC: a thin wrapper
  // around the real computeZoneMerges captures its `zones` argument (still
  // delegating to the real implementation, so the merge result itself is
  // untouched) so the test can assert on what the orchestration fed it,
  // not just on what came out the other end.
  let capturedZones: ZoneInput[] = [];
  const spyComputeZoneMerges: typeof computeZoneMerges = (zones, thresholdM) => {
    capturedZones = zones;
    return computeZoneMerges(zones, thresholdM);
  };

  const db = new RecordingDbClient();
  const result = await runSplitAndMerge({
    supabase: db,
    inputs,
    newId,
    newRing,
    now: '2026-07-21T12:00:00.000Z',
    kMergeThresholdMeters: 25,
    kMinSplitFragmentAreaSqm: 375,
    kLevelUpCooldownMs: 24 * 3600 * 1000,
    computeZoneSplit,
    computeZoneMerges: spyComputeZoneMerges,
    computeLevelUpOutcome,
    ...flatMaps(['zoneC-split-target', newId]),
  });

  assertFalse(result instanceof Response, 'runSplitAndMerge must not return an error response for this scenario');

  const splitCall = db.rpcCalls.find((c) => c.fn === 'apply_zone_split');
  assert(splitCall, 'the split RPC must fire for zoneC, since its remainder clears the sliver floor');
  assertEquals(splitCall!.args.p_zone_id, 'zoneC-split-target');

  const zoneCEntries = capturedZones.filter((z) => z.id === 'zoneC-split-target');
  assertEquals(zoneCEntries.length, 1, 'zoneC must appear exactly once in the ring set fed to the merge scan');

  const westmostLng = Math.min(...zoneCEntries[0].ring.map((p) => p[0]));
  const remainderWestLng = lngAt(20); // the kept east-half remainder's own west edge
  const staleWestLng = 33.0; // zoneC's original, pre-split west edge

  assert(
    Math.abs(westmostLng - remainderWestLng) < 1e-9,
    `the merge scan must see zoneC's REMAINDER ring (west edge ~${remainderWestLng}), not its stale ` +
      `pre-split full ring (west edge ~${staleWestLng}) - got westmost longitude ${westmostLng}`,
  );
});

Deno.test('a failed delete during the split loop is surfaced as a 500 error response, not swallowed', async () => {
  const newId = 'new-claim-zone-4';
  const zoneARing = metresRing(33.0, LAT0, 40, 40);
  const newRing = metresRing(33.0, LAT0, 39, 40);

  class FailingDeleteDbClient implements SplitMergeDbClient {
    from(_table: 'zones') {
      return {
        delete: () => ({
          eq: (_column: 'id', _value: string) => Promise.resolve({ error: { message: 'connection reset' } }),
        }),
      };
    }
    rpc(_fn: string, _args: Record<string, unknown>) {
      return Promise.resolve({ error: null });
    }
  }

  const inputs: ZoneInput[] = [
    { id: 'zoneA-oldest', ring: zoneARing, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
    { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 1 },
  ];

  const result = await runSplitAndMerge({
    supabase: new FailingDeleteDbClient(),
    inputs,
    newId,
    newRing,
    now: '2026-07-21T12:00:00.000Z',
    kMergeThresholdMeters: 25,
    kMinSplitFragmentAreaSqm: 375,
    kLevelUpCooldownMs: 24 * 3600 * 1000,
    computeZoneSplit,
    computeZoneMerges,
    computeLevelUpOutcome,
    ...flatMaps(['zoneA-oldest', newId]),
  });

  assert(result instanceof Response, 'a failed delete must surface as an error Response, not be swallowed');
  assertEquals((result as Response).status, 500);
  const body = await (result as Response).json();
  assert(String(body.error).includes('connection reset'), 'the underlying delete error message must be surfaced');
});

Deno.test('a failed apply_zone_split RPC is surfaced as a 500 error response', async () => {
  const newId = 'new-claim-zone-5';
  const zoneCRing = metresRing(33.0, LAT0, 40, 40);
  const newRing = metresRing(33.0, LAT0, 20, 40);

  class FailingSplitDbClient implements SplitMergeDbClient {
    from(_table: 'zones') {
      return { delete: () => ({ eq: (_c: 'id', _v: string) => Promise.resolve({ error: null }) }) };
    }
    rpc(fn: string, _args: Record<string, unknown>) {
      if (fn === 'apply_zone_split') return Promise.resolve({ error: { message: 'constraint violation' } });
      return Promise.resolve({ error: null });
    }
  }

  const inputs: ZoneInput[] = [
    { id: 'zoneC-split-target', ring: zoneCRing, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
    { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 1 },
  ];

  const result = await runSplitAndMerge({
    supabase: new FailingSplitDbClient(),
    inputs,
    newId,
    newRing,
    now: '2026-07-21T12:00:00.000Z',
    kMergeThresholdMeters: 25,
    kMinSplitFragmentAreaSqm: 375,
    kLevelUpCooldownMs: 24 * 3600 * 1000,
    computeZoneSplit,
    computeZoneMerges,
    computeLevelUpOutcome,
    ...flatMaps(['zoneC-split-target', newId]),
  });

  assert(result instanceof Response, 'a failed split RPC must surface as an error Response');
  assertEquals((result as Response).status, 500);
  const body = await (result as Response).json();
  assert(String(body.error).includes('constraint violation'));
});

Deno.test('a failed apply_zone_merge RPC is surfaced as a 500 error response', async () => {
  const newId = 'new-claim-zone-6';
  const zoneBRing = metresRing(lngAt(5), LAT0, 40, 40);
  const newRing = metresRing(33.0, LAT0, 3, 40); // small, no split candidates, just touches zoneB

  class FailingMergeDbClient implements SplitMergeDbClient {
    from(_table: 'zones') {
      return { delete: () => ({ eq: (_c: 'id', _v: string) => Promise.resolve({ error: null }) }) };
    }
    rpc(fn: string, _args: Record<string, unknown>) {
      if (fn === 'apply_zone_merge') return Promise.resolve({ error: { message: 'deadlock detected' } });
      return Promise.resolve({ error: null });
    }
  }

  const inputs: ZoneInput[] = [
    { id: 'zoneB-touching', ring: zoneBRing, createdAt: '2020-01-01T00:00:00.000Z', influenceLevel: 1 },
    { id: newId, ring: newRing, createdAt: '2026-07-21T12:00:00.000Z', influenceLevel: 1 },
  ];

  const result = await runSplitAndMerge({
    supabase: new FailingMergeDbClient(),
    inputs,
    newId,
    newRing,
    now: '2026-07-21T12:00:00.000Z',
    kMergeThresholdMeters: 25,
    kMinSplitFragmentAreaSqm: 375,
    kLevelUpCooldownMs: 24 * 3600 * 1000,
    computeZoneSplit,
    computeZoneMerges,
    computeLevelUpOutcome,
    ...flatMaps(['zoneB-touching', newId]),
  });

  assert(result instanceof Response, 'a failed merge RPC must surface as an error Response');
  assertEquals((result as Response).status, 500);
  const body = await (result as Response).json();
  assert(String(body.error).includes('deadlock detected'));
});
