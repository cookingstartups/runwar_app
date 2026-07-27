// supabase/functions/tests/support_tickets_migration_test.ts
//
// Source-inspection coverage for the support_tickets migration - pure SQL,
// no live Postgres instance available in this sandbox, matching the same
// escape hatch already established in resolve_zone_disputes_migration_test.ts.
//
// Run: npx deno test supabase/functions/tests/support_tickets_migration_test.ts

import { assert, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findMigration(nameFragment: string): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  const matches: string[] = [];
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes(nameFragment)) matches.push(entry.name);
  }
  assert(
    matches.length > 0,
    `No migration file matching "${nameFragment}" found under supabase/migrations/ - the support_tickets migration has not been created yet.`,
  );
  return Deno.readTextFileSync(dirPath + matches[0]);
}

Deno.test('support_tickets table is created with the locked column set', () => {
  const sql = findMigration('support_tickets');
  assert(sql.includes('CREATE TABLE'), 'must create the support_tickets table');
  assert(sql.includes("kind"), 'must have a kind column');
  assert(/kind\s+text\s+not null\s+check\s*\(\s*kind\s+in\s*\(\s*'support'\s*,\s*'bug'\s*,\s*'account_deletion'\s*\)/i.test(sql),
    'kind must be constrained to support/bug/account_deletion');
});

Deno.test('status defaults to open and is constrained to the four lifecycle values', () => {
  const sql = findMigration('support_tickets');
  assert(/status\s+text\s+not null\s+default\s+'open'/i.test(sql),
    'status must default to open');
  assert(/status\s+in\s*\(\s*'open'\s*,\s*'in_progress'\s*,\s*'resolved'\s*,\s*'rejected'\s*\)/i.test(sql),
    'status must be constrained to open/in_progress/resolved/rejected');
});

Deno.test('user_id cascades on delete (unlike the deletion-requests audit table)', () => {
  const sql = findMigration('support_tickets');
  assert(/user_id\s+uuid\s+not null\s+references\s+auth\.users\(id\)\s+on delete cascade/i.test(sql),
    'support_tickets.user_id must cascade on auth.users deletion');
});

Deno.test('RLS is enabled with insert-own and select-own policies for authenticated users', () => {
  const sql = findMigration('support_tickets');
  assert(sql.includes('ENABLE ROW LEVEL SECURITY'), 'RLS must be enabled');
  assert(/for insert/i.test(sql), 'an insert policy must exist');
  assert(/for select/i.test(sql), 'a select policy must exist');
  assert(/auth\.uid\(\)\s*=\s*user_id/.test(sql), 'policies must be scoped to the row owner');
});

Deno.test('no update or delete policy is granted to regular authenticated users', () => {
  const sql = findMigration('support_tickets');
  assertFalse(/for update\s+to\s+authenticated/i.test(sql),
    'regular users must not be able to update their own ticket status');
  assertFalse(/for delete\s+to\s+authenticated/i.test(sql),
    'regular users must not be able to delete tickets');
});
