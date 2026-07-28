// supabase/functions/tests/account_deletion_requests_migration_test.ts
//
// Source-inspection coverage for the account_deletion_requests migration and
// its two load-bearing RPCs (submit_support_ticket, reactivate_account), the
// same escape hatch as resolve_zone_disputes_migration_test.ts.
//
// Run: npx deno test supabase/functions/tests/account_deletion_requests_migration_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findMigration(nameFragment: string): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  const matches: string[] = [];
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes(nameFragment)) matches.push(entry.name);
  }
  assert(
    matches.length > 0,
    `No migration file matching "${nameFragment}" found - the account_deletion_requests migration has not been created yet.`,
  );
  return Deno.readTextFileSync(dirPath + matches[0]);
}

Deno.test('account_deletion_requests survives auth.users deletion (SET NULL, not CASCADE)', () => {
  const sql = findMigration('account_deletion_requests');
  assert(/user_id\s+uuid\s+references\s+auth\.users\(id\)\s+on delete set null/i.test(sql),
    'user_id must be ON DELETE SET NULL so the audit row survives the eventual auth.users delete');
});

Deno.test('status is constrained to pending, reactivated, executed with a pending default', () => {
  const sql = findMigration('account_deletion_requests');
  assert(/status\s+text\s+not null\s+default\s+'pending'/i.test(sql));
  assert(/status\s+in\s*\(\s*'pending'\s*,\s*'reactivated'\s*,\s*'executed'\s*\)/i.test(sql));
});

Deno.test('scheduled_deletion_at is a required, non-null column (the 30-day grace window)', () => {
  const sql = findMigration('account_deletion_requests');
  assert(/scheduled_deletion_at\s+timestamptz\s+not null/i.test(sql));
});

Deno.test('regular authenticated users have no direct write policy on this table', () => {
  const sql = findMigration('account_deletion_requests');
  const insertPolicyForAuthenticated = /create policy[^;]*for insert[^;]*to authenticated/is.test(sql);
  assert(!insertPolicyForAuthenticated,
    'writes must only happen through submit_support_ticket/reactivate_account or the service-role executor, never a direct client insert policy');
});

Deno.test('submit_support_ticket is SECURITY DEFINER, scoped to auth.uid(), and atomically inserts both rows', () => {
  const sql = findMigration('account_deletion_requests');
  assert(sql.includes('submit_support_ticket'), 'submit_support_ticket function must be defined');
  assert(/security definer/i.test(sql));
  assert(sql.includes('auth.uid()'), 'the function body must scope writes to auth.uid()');
  assert(sql.includes('INSERT INTO support_tickets'), 'must insert the ticket row');
  assert(sql.includes('INSERT INTO account_deletion_requests'), 'must also insert the deletion-request row for the account_deletion kind, in the same function');
});

Deno.test('submit_support_ticket sets scheduled_deletion_at to requested_at + 30 days', () => {
  const sql = findMigration('account_deletion_requests');
  assert(/now\(\)\s*\+\s*interval\s*'30 days'/i.test(sql),
    'the 30-day grace window must be computed as now() + interval \'30 days\'');
});

Deno.test('reactivate_account only flips a pending row for the calling user', () => {
  const sql = findMigration('account_deletion_requests');
  assert(sql.includes('reactivate_account'), 'reactivate_account function must be defined');
  assert(/set\s+status\s*=\s*'reactivated'/i.test(sql));
  assert(/where\s+user_id\s*=\s*auth\.uid\(\)\s+and\s+status\s*=\s*'pending'/i.test(sql),
    'reactivation must only touch the calling user\'s own pending row');
});

Deno.test('both RPCs grant execute only to authenticated, never to anon/public', () => {
  const sql = findMigration('account_deletion_requests');
  const grants = sql.match(/GRANT EXECUTE ON FUNCTION[^;]*;/gi) ?? [];
  assert(grants.length >= 2, 'both submit_support_ticket and reactivate_account must have explicit GRANT EXECUTE statements');
  for (const g of grants) {
    assert(/to authenticated/i.test(g), `grant must target authenticated only: ${g}`);
  }
});
