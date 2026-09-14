// supabase/functions/tests/has_open_challenge_migration_test.ts
//
// Anti-cheat pipeline, pass 2: source inspection of the new has_open_challenge
// migration. Follows the anticheat_score_flags_write_test.ts convention:
// Deno.readTextFileSync against the real migration file as text, assert on
// regex/substring code shapes, no live Postgres/Supabase client.
//
// The migration file does not exist until implementation lands. The
// migration number is not hardcoded here - the file is located by globbing
// supabase/migrations/ for a filename matching has_open_challenge, so this
// test does not break when the implementer picks the next free number.
//
// Run: npx --yes deno@2 test --allow-read supabase/functions/tests/has_open_challenge_migration_test.ts

import { assert, assertFalse, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findMigrationSrc(): string {
  const matches: string[] = [];
  for (const entry of Deno.readDirSync(MIGRATIONS_DIR)) {
    if (entry.isFile && entry.name.includes('has_open_challenge') && entry.name.endsWith('.sql')) {
      matches.push(entry.name);
    }
  }
  assert(matches.length > 0,
    'no migration file matching has_open_challenge found under supabase/migrations/ - implementation has not landed yet');
  assertEquals(matches.length, 1,
    'expected exactly one has_open_challenge migration file, found: ' + matches.join(', '));
  return Deno.readTextFileSync(new URL(matches[0], MIGRATIONS_DIR));
}

Deno.test('defines has_open_challenge as LANGUAGE sql STABLE', () => {
  const src = findMigrationSrc();
  assert(/CREATE (OR REPLACE )?FUNCTION\s+has_open_challenge/i.test(src),
    'must define a has_open_challenge function');
  assert(/LANGUAGE\s+sql\s+STABLE/i.test(src),
    'the function must be LANGUAGE sql STABLE since it is a read-only helper');
});

Deno.test('selects from challenges filtering on user_id, not the doctrine-literal player_id', () => {
  const src = findMigrationSrc();
  assert(/FROM\s+public\.challenges/i.test(src) || /FROM\s+challenges/i.test(src),
    'must select from the live challenges table');
  assert(/user_id\s*=\s*p_player_id/i.test(src),
    'must filter on the live user_id column');
  assertFalse(/player_id\s*=\s*p_player_id/i.test(src),
    'must not reference a player_id column - challenges has no such column live');
});

Deno.test('filters on the live pending status literal, not the doctrine-literal open', () => {
  const src = findMigrationSrc();
  assert(/status\s*=\s*'pending'/i.test(src),
    'must filter on status = pending, the live default/unique-index convention');
  assertFalse(/status\s*=\s*'open'/i.test(src),
    'must not filter on status = open - the live schema never sets this value');
});

Deno.test('joins user_id and status = pending with AND, not two independent or OR-joined clauses', () => {
  const src = findMigrationSrc();
  assert(/WHERE\s+user_id\s*=\s*p_player_id\s+AND\s+status\s*=\s*'pending'/i.test(src),
    'the WHERE clause must combine user_id = p_player_id AND status = \'pending\' with AND - a body written with OR (or any join returning any pending challenge for any player, or any status for the given player) must fail this test');
});

Deno.test('orders by issued_at descending, limited to one row', () => {
  const src = findMigrationSrc();
  assert(/ORDER BY\s+issued_at\s+DESC/i.test(src),
    'must order by issued_at DESC to return the most recent pending challenge');
  assert(/LIMIT\s+1/i.test(src),
    'must limit to a single row');
});

Deno.test('grants EXECUTE to service_role only, never to authenticated or anon', () => {
  const src = findMigrationSrc();
  assert(/GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+has_open_challenge\(uuid\)\s+TO\s+service_role/i.test(src),
    'must grant EXECUTE on has_open_challenge(uuid) to service_role');
  assertFalse(/GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+has_open_challenge\(uuid\)\s+TO\s+(authenticated|anon)/i.test(src),
    'must not grant EXECUTE to authenticated or anon - only the service-role edge function client calls this');
});
