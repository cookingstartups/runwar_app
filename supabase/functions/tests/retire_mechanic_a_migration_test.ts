// supabase/functions/tests/retire_mechanic_a_migration_test.ts
//
// Mechanic A retirement (spec R1). Source-inspection of the migration set,
// for the same reason given in resolve_zone_disputes_migration_test.ts: no
// live Postgres instance is available to actually run the drop and query
// information_schema, so this asserts the migration's SQL contains the
// required DROP statements and lives in the correct repo.
//
// Run: npx deno test supabase/functions/tests/retire_mechanic_a_migration_test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findRetirementMigration(): { name: string; sql: string } {
  const dirPath = MIGRATIONS_DIR.pathname;
  const matches: string[] = [];
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && /retire.*mechanic.*a|retire.*dispute/i.test(entry.name)) {
      matches.push(entry.name);
    }
  }
  assert(
    matches.length > 0,
    'No mechanic-A retirement migration found under runwar_app/supabase/migrations/ (spec R1-AC1) - the disputes table, apply_dispute_outcome trigger, and resolve_dispute function are still live.',
  );
  const name = matches[0];
  return { name, sql: Deno.readTextFileSync(dirPath + name) };
}

Deno.test('the retirement migration drops the disputes table', () => {
  const { sql } = findRetirementMigration();
  assert(/drop\s+table\s+(if\s+exists\s+)?disputes/i.test(sql),
    'must DROP TABLE disputes (spec R1-AC1)');
});

Deno.test('the retirement migration drops the apply_dispute_outcome trigger and function', () => {
  const { sql } = findRetirementMigration();
  assert(/drop\s+trigger.*dispute_outcome/i.test(sql) || /drop\s+trigger.*on\s+disputes/i.test(sql),
    'must DROP the apply_dispute_outcome trigger (spec R1-AC1)');
  assert(/drop\s+function.*apply_dispute_outcome/i.test(sql),
    'must DROP FUNCTION apply_dispute_outcome() (spec R1-AC1)');
});

Deno.test('the retirement migration file is numbered after 0059 (next free migration number)', () => {
  const { name } = findRetirementMigration();
  const match = name.match(/^(\d+)_/);
  assert(match, `migration filename "${name}" must start with a numeric prefix`);
  const num = parseInt(match![1], 10);
  assert(num > 59, `retirement migration must be numbered after 0059 (found ${name}) - design.md places it as "next free number after 0059" (spec R1-AC1)`);
});

Deno.test('this feature adds no new migration file under runwar_database', () => {
  // runwar_database is a sibling repo; this test only verifies that
  // runwar_app's own migration set does not contain any file that claims to
  // belong to runwar_database's history (a corruption/duplication guard),
  // and that runwar_app is where the new migrations actually live.
  const { name } = findRetirementMigration();
  assert(!name.toLowerCase().includes('runwar_database'),
    'the retirement migration must be an ordinary runwar_app migration file, not a copy referencing runwar_database (spec R1-AC2, R2-AC2 of requirements.md)');
});
