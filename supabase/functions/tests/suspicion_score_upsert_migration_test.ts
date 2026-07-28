// supabase/functions/tests/suspicion_score_upsert_migration_test.ts
//
// The upsert_suspicion_score SQL function this fix's suspicion_scores write
// depends on (design.md's atomic UPSERT with GREATEST/increment semantics).
// design.md flags a three-way migration-numbering contest across sibling
// initiatives, none merged yet, so this test locates the migration by
// function-name content across every file in the migrations directory,
// never by a hardcoded number, so it survives whatever number lands first.
// Source inspection, same convention as resolve_zone_disputes_migration_test.ts.
//
// Run: npx deno test supabase/functions/tests/suspicion_score_upsert_migration_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findMigrationByContent(needle: string): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  for (const entry of Deno.readDirSync(dirPath)) {
    if (!entry.isFile) continue;
    const text = Deno.readTextFileSync(dirPath + entry.name);
    if (text.includes(needle)) return text;
  }
  throw new Error(
    `No migration file contains "${needle}" under supabase/migrations/ - the upsert_suspicion_score function has not been created yet.`,
  );
}

Deno.test('a migration creates the upsert_suspicion_score function', () => {
  const sql = findMigrationByContent('upsert_suspicion_score');
  assert(/create\s+or\s+replace\s+function\s+upsert_suspicion_score/i.test(sql),
    'must define upsert_suspicion_score as a SQL function');
});

Deno.test('the function upserts score as the greatest of the existing value and this batch\'s session max', () => {
  const sql = findMigrationByContent('upsert_suspicion_score');
  assert(/greatest\(\s*suspicion_scores\.score\s*,\s*excluded\.session_max_score\s*\)/i.test(sql),
    'score must be GREATEST(existing, new) - a lifetime running max that never decreases');
});

Deno.test('the function increments flags_count rather than overwriting it', () => {
  const sql = findMigrationByContent('upsert_suspicion_score');
  assert(/flags_count\s*=\s*suspicion_scores\.flags_count\s*\+\s*excluded\.flags_count/i.test(sql),
    'flags_count must accumulate across batches, not be replaced by the latest batch\'s count');
});

Deno.test('the upsert is keyed on user_id, the table\'s only key (no separate id column)', () => {
  const sql = findMigrationByContent('upsert_suspicion_score');
  assert(/on\s+conflict\s*\(\s*user_id\s*\)/i.test(sql),
    'ON CONFLICT must target user_id - suspicion_scores has no separate id column live');
});

Deno.test('a unique constraint on user_id is added defensively so ON CONFLICT (user_id) is legal SQL', () => {
  const sql = findMigrationByContent('upsert_suspicion_score');
  assert(/add\s+constraint\s+\S*\s+unique\s*\(\s*user_id\s*\)/i.test(sql),
    'a UNIQUE constraint on user_id must be added (idempotently) since ON CONFLICT requires one to exist');
});
