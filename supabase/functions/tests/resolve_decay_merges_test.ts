// supabase/functions/tests/resolve_decay_merges_test.ts
//
// Real execution coverage for resolveDecayMerge (the decay-triggered
// counterpart of claim_territory's own claim-triggered merge). Drives the
// actual exported function against an injected fake database client and
// asserts on its real return value and the real RPC call it records.
//
// Run: npx deno test supabase/functions/tests/resolve_decay_merges_test.ts

import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  resolveDecayMerge,
  type ResolveDecayMergeDbClient,
} from '../resolve_decay_merges/handler.ts';

const LAT0 = 39.470000; // Valencia, matching the reference point used across the other merge tests
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

interface ZoneRow {
  id: string;
  geom_json: string;
  created_at: string;
  influence: number;
  influence_level: number;
  credits_earned: number;
  last_active_at: string | null;
  shield_active: boolean;
  shield_expires_at: string | null;
}

// Records the rpc call it receives, so a test can assert on exactly what
// was sent to the database.
class FakeDbClient implements ResolveDecayMergeDbClient {
  rows: ZoneRow[];
  rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];

  constructor(rows: ZoneRow[]) {
    this.rows = rows;
  }

  from(_table: string) {
    return {
      select: (_cols: string) => ({
        eq: (_c1: string, ownerId: unknown) => ({
          eq: (_c2: string, city: unknown) => ({
            eq: (_c3: string, status: unknown) =>
              Promise.resolve({
                data: this.rows.map((r) => ({ ...r })),
                error: null,
              }),
          }),
        }),
      }),
    };
  }

  rpc(fn: string, args: Record<string, unknown>) {
    this.rpcCalls.push({ fn, args });
    return Promise.resolve({ error: null });
  }
}

function zoneRow(
  id: string,
  lng0: number,
  createdAt: string,
  influenceLevel: number,
  influence: number,
): ZoneRow {
  return {
    id,
    geom_json: JSON.stringify({ type: 'Polygon', coordinates: [metresRing(lng0, LAT0, 40, 40)] }),
    created_at: createdAt,
    influence,
    influence_level: influenceLevel,
    credits_earned: 0,
    last_active_at: null,
    shield_active: false,
    shield_expires_at: null,
  };
}

Deno.test('a decay tick that brought two touching same-owner zones to equal levels fuses them', async () => {
  const zoneA = zoneRow('zoneA-oldest', 33.0, '2026-01-01T00:00:00Z', 2, 2.02);
  // Touching zoneA within the 25m threshold, already at level 2 (this is
  // the level the decayed zone just stepped down to).
  const zoneB = zoneRow('zoneB-newer', lngAt(40 + 5), '2026-02-01T00:00:00Z', 2, 2.4);

  const db = new FakeDbClient([zoneA, zoneB]);
  const result = await resolveDecayMerge(db, 'owner-1', 'valencia', 'zoneB-newer');

  assert(result.merged, 'two touching same-owner zones at the same level must fuse');
  assertEquals(result.survivorId, 'zoneA-oldest', 'the oldest zone survives, matching claim_territory\'s own rule');
  assertEquals(result.absorbedZoneIds, ['zoneB-newer']);

  const mergeCall = db.rpcCalls.find((c) => c.fn === 'apply_zone_merge');
  assert(mergeCall, 'apply_zone_merge must be called');
  assertEquals(mergeCall!.args.p_influence_level, 2, 'no bonus level-up on a decay-triggered fuse - the survivor keeps the group\'s already-equal level');
  assertEquals(mergeCall!.args.p_influence, 2.02 + 2.4);
});

Deno.test('a decay tick with no adjacent same-level neighbour does not fuse', async () => {
  const zoneA = zoneRow('zoneA-oldest', 33.0, '2026-01-01T00:00:00Z', 2, 2.02);
  // Same owner, touching, but at a DIFFERENT level - must not merge.
  const zoneB = zoneRow('zoneB-newer', lngAt(40 + 5), '2026-02-01T00:00:00Z', 3, 3.4);

  const db = new FakeDbClient([zoneA, zoneB]);
  const result = await resolveDecayMerge(db, 'owner-1', 'valencia', 'zoneA-oldest');

  assertFalse(result.merged, 'a same-owner neighbour at a different level must not fuse');
  assertFalse(db.rpcCalls.some((c) => c.fn === 'apply_zone_merge'), 'apply_zone_merge must never be called when no group forms');
});

Deno.test('a decayed zone with no nearby same-owner neighbour at all does not fuse', async () => {
  const zoneA = zoneRow('zoneA-lonely', 33.0, '2026-01-01T00:00:00Z', 2, 2.02);

  const db = new FakeDbClient([zoneA]);
  const result = await resolveDecayMerge(db, 'owner-1', 'valencia', 'zoneA-lonely');

  assertFalse(result.merged);
  assertEquals(db.rpcCalls.length, 0);
});
