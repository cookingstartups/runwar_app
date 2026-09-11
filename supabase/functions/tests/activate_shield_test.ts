// supabase/functions/tests/activate_shield_test.ts
//
// Real execution coverage for activateShieldOnZone (the SHIELD-from-
// inventory single-zone activation core). Drives the actual exported
// function against an injected fake database client and asserts on its
// real return value and the real RPC call it records, mirroring the
// FakeDbClient discipline in resolve_decay_merges_test.ts.
//
// Run: deno test --allow-all supabase/functions/tests/activate_shield_test.ts

import { assertEquals, assertNotEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { activateShieldOnZone, type ActivateShieldDbClient } from '../activate_shield/handler.ts';
import { kShieldBaseHoursPerLevel } from '../_shared/constants.ts';

// Records every call the handler makes, distinguishing the single
// transaction-boundary RPC call from any direct table write. A correct
// handler makes exactly one rpc() call and zero from()-based writes on
// every path, because ownership and grant consumption both happen inside
// the RPC's own transaction.
class FakeDbClient implements ActivateShieldDbClient {
  rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
  fromCalls: { table: string; op: string }[] = [];
  rpcResponse: { data: Record<string, unknown>[] | null; error: { message: string } | null };

  constructor(rpcResponse: { data: Record<string, unknown>[] | null; error: { message: string } | null }) {
    this.rpcResponse = rpcResponse;
  }

  rpc(fn: string, args: Record<string, unknown>) {
    this.rpcCalls.push({ fn, args });
    return Promise.resolve(this.rpcResponse);
  }

  from(table: string) {
    return {
      update: (_values: Record<string, unknown>) => {
        this.fromCalls.push({ table, op: 'update' });
        return { eq: (_c: string, _v: unknown) => Promise.resolve({ error: null }) };
      },
      insert: (_values: Record<string, unknown>) => {
        this.fromCalls.push({ table, op: 'insert' });
        return Promise.resolve({ error: null });
      },
    };
  }
}

Deno.test('activating a held SHIELD grant on an owned zone sets shield_active with an expiry scaled to that zone\'s influence level', async () => {
  const expiresAt = '2026-09-08T05:00:00.000Z'; // base_hours * level 4, as the transaction would compute it
  const db = new FakeDbClient({
    data: [{ outcome: 'ok', shield_expires_at: expiresAt, influence_level: 4, grant_id: 'grant-a' }],
    error: null,
  });

  const result = await activateShieldOnZone(db, 'player-a', 'zone-z');

  assertEquals(result.success, true, 'activating an owned zone with an available grant must succeed');
  assertEquals(result.shield_expires_at, expiresAt, 'the response must surface the transaction\'s own computed expiry, not a value the handler invents');
  assertEquals(result.influence_level, 4);
  assertEquals(result.grant_id, 'grant-a');
});

Deno.test('a different owned zone at a different influence level gets a different scaled expiry, proving duration is not a hardcoded constant', async () => {
  const level4Expiry = '2026-09-08T05:00:00.000Z';
  const level9Expiry = '2026-09-08T10:00:00.000Z';

  const dbLevel4 = new FakeDbClient({
    data: [{ outcome: 'ok', shield_expires_at: level4Expiry, influence_level: 4, grant_id: 'grant-a' }],
    error: null,
  });
  const dbLevel9 = new FakeDbClient({
    data: [{ outcome: 'ok', shield_expires_at: level9Expiry, influence_level: 9, grant_id: 'grant-b' }],
    error: null,
  });

  const resultLevel4 = await activateShieldOnZone(dbLevel4, 'player-a', 'zone-low');
  const resultLevel9 = await activateShieldOnZone(dbLevel9, 'player-a', 'zone-high');

  assertNotEquals(resultLevel4.shield_expires_at, resultLevel9.shield_expires_at, 'two different influence levels must not collapse onto the same duration');
  assertEquals(resultLevel4.shield_expires_at, level4Expiry);
  assertEquals(resultLevel9.shield_expires_at, level9Expiry);
});

Deno.test('activation forwards the exact caller id, target zone id, and the shared base-hours-per-level constant to the transaction', async () => {
  const db = new FakeDbClient({
    data: [{ outcome: 'ok', shield_expires_at: '2026-09-08T05:00:00.000Z', influence_level: 4, grant_id: 'grant-a' }],
    error: null,
  });

  await activateShieldOnZone(db, 'player-a', 'zone-z');

  assertEquals(db.rpcCalls.length, 1, 'exactly one RPC call, the single atomic transaction boundary');
  assertEquals(db.rpcCalls[0].fn, 'activate_shield_on_zone_tx');
  assertEquals(db.rpcCalls[0].args, {
    p_user_id: 'player-a',
    p_zone_id: 'zone-z',
    p_hours_per_level: kShieldBaseHoursPerLevel,
  }, 'the transaction must receive the real shared constant, never a duplicated local literal');
});

Deno.test('activating SHIELD on a zone the player does not own is rejected and reports not_owner', async () => {
  const db = new FakeDbClient({
    data: [{ outcome: 'not_owner', shield_expires_at: null, influence_level: null, grant_id: null }],
    error: null,
  });

  const result = await activateShieldOnZone(db, 'player-a', 'zone-owned-by-b');

  assertEquals(result.success, false, 'an activation against a zone the caller does not own must not report success');
  assertEquals(result.reason, 'not_owner', 'the rejection reason must be the transaction\'s own typed outcome, not a generic error string');
});

Deno.test('a rejected activation performs zero direct table writes, leaving the target zone and the grant untouched', async () => {
  const db = new FakeDbClient({
    data: [{ outcome: 'not_owner', shield_expires_at: null, influence_level: null, grant_id: null }],
    error: null,
  });

  await activateShieldOnZone(db, 'player-a', 'zone-owned-by-b');

  assertEquals(db.fromCalls.length, 0, 'the handler must never write a table directly - only the transaction may mutate rows, and it did not on this path');
});

Deno.test('activating SHIELD against a zone id the transaction cannot find is rejected and reports zone_not_found', async () => {
  const db = new FakeDbClient({
    data: [{ outcome: 'zone_not_found', shield_expires_at: null, influence_level: null, grant_id: null }],
    error: null,
  });

  const result = await activateShieldOnZone(db, 'player-a', 'zone-does-not-exist');

  assertEquals(result.success, false, 'an activation against a nonexistent zone must not report success');
  assertEquals(result.reason, 'zone_not_found', 'the rejection reason must be the transaction\'s own typed outcome, not a generic error string');
  assertEquals(db.fromCalls.length, 0, 'a zone_not_found rejection must leave every row untouched, exactly like not_owner');
});

Deno.test('activating SHIELD with no unconsumed grant available is rejected and reports no_grant', async () => {
  const db = new FakeDbClient({
    data: [{ outcome: 'no_grant', shield_expires_at: null, influence_level: null, grant_id: null }],
    error: null,
  });

  const result = await activateShieldOnZone(db, 'player-a', 'zone-owned-by-a');

  assertEquals(result.success, false, 'an activation with no unconsumed grant must not report success');
  assertEquals(result.reason, 'no_grant', 'the rejection reason must be the transaction\'s own typed outcome, not a generic error string');
  assertEquals(db.fromCalls.length, 0, 'a no_grant rejection must leave every row untouched, exactly like not_owner');
});

Deno.test('an RPC-level error (the error field itself set) is rejected and reports rpc_error, never success', async () => {
  const db = new FakeDbClient({
    data: null,
    error: { message: 'connection reset' },
  });

  const result = await activateShieldOnZone(db, 'player-a', 'zone-owned-by-a');

  assertEquals(result.success, false, 'an RPC-level error must never be reported as a successful activation');
  assertEquals(result.reason, 'rpc_error', 'an RPC-level error must map to the rpc_error reason, distinct from any typed outcome the transaction itself can return');
  assertEquals(db.fromCalls.length, 0, 'an RPC-level error must leave every row untouched, exactly like a typed rejection outcome');
});

Deno.test('an RPC call that returns no row at all (empty data) is rejected and reports rpc_error, never success', async () => {
  const db = new FakeDbClient({
    data: [],
    error: null,
  });

  const result = await activateShieldOnZone(db, 'player-a', 'zone-owned-by-a');

  assertEquals(result.success, false, 'an empty result row must never be reported as a successful activation');
  assertEquals(result.reason, 'rpc_error', 'an empty result row must map to the rpc_error reason');
});
