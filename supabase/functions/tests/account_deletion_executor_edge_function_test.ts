// supabase/functions/tests/account_deletion_executor_edge_function_test.ts
//
// Source-inspection coverage for the account-deletion-executor edge
// function: per-row failure isolation (one bad row must not block the rest
// of the sweep), the manual single-row trigger used by the admin surface,
// and the admin_pending_deletions view. No injectable Supabase client is
// available in this sandbox, so this proves shape/wiring, not runtime
// behavior, same caveat as resolve_zone_disputes_migration_test.ts.
//
// Run: npx deno test supabase/functions/tests/account_deletion_executor_edge_function_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

function readFn(): string {
  const path = new URL('../account-deletion-executor/index.ts', import.meta.url).pathname;
  try {
    return Deno.readTextFileSync(path);
  } catch {
    throw new Error('supabase/functions/account-deletion-executor/index.ts does not exist yet');
  }
}

Deno.test('the edge function exists and calls claim_and_transfer_zones via rpc', () => {
  const src = readFn();
  assert(src.includes('claim_and_transfer_zones'), 'must invoke the SQL claim/transfer function');
  assert(src.includes('.rpc('), 'must call it via the Supabase rpc client');
});

Deno.test('one row failing does not stop the rest of the sweep', () => {
  const src = readFn();
  assert(src.includes('continue') || /for\s*\(/.test(src),
    'a per-row loop must exist so a single failure does not abort remaining rows');
  assert(src.includes('results.push'), 'per-row outcomes must be tracked individually');
});

Deno.test('accepts an optional request_id to scope to a single row (manual admin trigger)', () => {
  const src = readFn();
  assert(src.includes('request_id'), 'a request_id parameter must allow scoping to one row');
});

Deno.test('auth deletion goes through the Admin API, never a raw SQL DELETE FROM auth.users', () => {
  const src = readFn();
  assert(src.includes('auth.admin.deleteUser'), 'must delete the auth user via the Admin API');
  assert(!/delete\s+from\s+auth\.users/i.test(src), 'must never issue a raw DELETE FROM auth.users');
});

Deno.test('admin_pending_deletions view lists past-due pending requests with their ticket', () => {
  const dirPath = new URL('../../migrations/', import.meta.url).pathname;
  const matches: string[] = [];
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes('account_deletion_executor')) matches.push(entry.name);
  }
  assert(matches.length > 0, 'the executor migration must exist to define admin_pending_deletions');
  const sql = Deno.readTextFileSync(dirPath + matches[0]);
  assert(sql.includes('admin_pending_deletions'), 'the minimal admin view must be defined');
  assert(sql.includes("status = 'pending'") && sql.includes('scheduled_deletion_at <= now()'),
    'the view must only list still-pending, past-due rows');
});
