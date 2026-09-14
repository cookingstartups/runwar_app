// supabase/functions/tests/ops_db_verification_readonly_guard_test.ts
//
// isReadOnlyQuery (ops/db_verification/cli.ts) is the only gate standing
// between the verification tool and accidentally executing a write against
// a live database. Every mutating and multi-statement form must be
// rejected.
//
// Run: npx deno test --allow-read supabase/functions/tests/ops_db_verification_readonly_guard_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { isReadOnlyQuery } from '../../../ops/db_verification/cli.ts';

Deno.test('accepts a single SELECT statement', () => {
  assertEquals(isReadOnlyQuery('SELECT id FROM zones WHERE owner_id = $1'), true);
});

Deno.test('rejects INSERT', () => {
  assertEquals(isReadOnlyQuery("INSERT INTO zones (id) VALUES ('z1')"), false);
});

Deno.test('rejects UPDATE', () => {
  assertEquals(isReadOnlyQuery("UPDATE zones SET status = 'disputed' WHERE id = 'z1'"), false);
});

Deno.test('rejects DELETE', () => {
  assertEquals(isReadOnlyQuery("DELETE FROM zones WHERE id = 'z1'"), false);
});

Deno.test('rejects DROP', () => {
  assertEquals(isReadOnlyQuery('DROP TABLE zones'), false);
});

Deno.test('rejects ALTER', () => {
  assertEquals(isReadOnlyQuery('ALTER TABLE zones ADD COLUMN foo TEXT'), false);
});

Deno.test('rejects TRUNCATE', () => {
  assertEquals(isReadOnlyQuery('TRUNCATE zones'), false);
});

Deno.test('rejects GRANT', () => {
  assertEquals(isReadOnlyQuery('GRANT SELECT ON zones TO some_role'), false);
});

Deno.test('rejects CREATE', () => {
  assertEquals(isReadOnlyQuery('CREATE TABLE evil (id TEXT)'), false);
});

Deno.test('rejects multi-statement input even when the first statement is a SELECT', () => {
  assertEquals(isReadOnlyQuery('SELECT id FROM zones; DROP TABLE zones;'), false);
});

Deno.test('rejects a SELECT with a trailing second statement after a semicolon', () => {
  assertEquals(isReadOnlyQuery('SELECT id FROM zones WHERE owner_id = $1; SELECT 1;'), false);
});
