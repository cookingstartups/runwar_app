// supabase/functions/tests/dispute_overlap_column_migration_test.ts
//
// The new dispute_overlap_m2 column (spec R2-AC2, design.md §4.1). Source
// inspection of the migration - see resolve_zone_disputes_migration_test.ts
// for why (no live Postgres instance to run \d zones against).
//
// Run: npx deno test supabase/functions/tests/dispute_overlap_column_migration_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findColumnMigration(): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes('dispute_overlap')) {
      return Deno.readTextFileSync(dirPath + entry.name);
    }
  }
  throw new Error(
    'No migration adding zones.dispute_overlap_m2 found under runwar_app/supabase/migrations/ (spec R2-AC2) - the column does not exist yet.',
  );
}

Deno.test('a migration adds zones.dispute_overlap_m2 as a nullable numeric column', () => {
  const sql = findColumnMigration();
  assert(/alter\s+table\s+zones\s+add\s+column/i.test(sql),
    'must ALTER TABLE zones ADD COLUMN (spec R2-AC2)');
  assert(/dispute_overlap_m2/i.test(sql), 'the new column must be named dispute_overlap_m2');
  assert(/double precision|numeric|real|float/i.test(sql),
    'dispute_overlap_m2 must be a floating-point column, matching a square-meter area value');
});
