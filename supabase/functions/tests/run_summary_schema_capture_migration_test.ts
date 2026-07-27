// supabase/functions/tests/run_summary_schema_capture_migration_test.ts
//
// The new runs.distance_m/ended_at/finalized_at columns - these are written
// by stopRun()/cancelRun() and read by finalize_run on the live database
// today, but no migration file anywhere defines them. Source inspection,
// matching this repo's established migration-test convention (no live
// Postgres instance to run \d runs against).
//
// Run: npx deno test supabase/functions/tests/run_summary_schema_capture_migration_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findRunsSchemaCaptureMigration(): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes('run_summary_schema_capture')) {
      return Deno.readTextFileSync(dirPath + entry.name);
    }
  }
  throw new Error(
    'No migration adding runs.distance_m/ended_at/finalized_at found under runwar_app/supabase/migrations/ - none of the three columns exist yet.',
  );
}

Deno.test('a migration idempotently adds distance_m, ended_at, and finalized_at to runs', () => {
  const sql = findRunsSchemaCaptureMigration();
  assert(/alter\s+table\s+runs/i.test(sql), 'must ALTER TABLE runs');
  assert(/add\s+column\s+if\s+not\s+exists\s+distance_m/i.test(sql),
    'distance_m must be added idempotently (IF NOT EXISTS)');
  assert(/add\s+column\s+if\s+not\s+exists\s+ended_at/i.test(sql),
    'ended_at must be added idempotently (IF NOT EXISTS)');
  assert(/add\s+column\s+if\s+not\s+exists\s+finalized_at/i.test(sql),
    'finalized_at must be added idempotently (IF NOT EXISTS)');
});

Deno.test('distance_m is numeric and ended_at/finalized_at are timestamptz', () => {
  const sql = findRunsSchemaCaptureMigration();
  const distanceLine = sql.split('\n').find((l) => /distance_m/i.test(l)) ?? '';
  assert(/numeric/i.test(distanceLine), 'distance_m must be a numeric column');
  const endedLine = sql.split('\n').find((l) => /ended_at/i.test(l)) ?? '';
  assert(/timestamptz/i.test(endedLine), 'ended_at must be timestamptz');
  const finalizedLine = sql.split('\n').find((l) => /finalized_at/i.test(l)) ?? '';
  assert(/timestamptz/i.test(finalizedLine), 'finalized_at must be timestamptz');
});
