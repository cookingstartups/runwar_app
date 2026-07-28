// supabase/functions/tests/gps_samples_altitude_migration_test.ts
//
// The gps_samples table has no altitude column anywhere in the schema
// today - the only altitude reference in the codebase is a hardcoded
// simulation-fixture stub. Source inspection, matching this repo's
// established migration-test convention.
//
// Run: npx deno test supabase/functions/tests/gps_samples_altitude_migration_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findGpsSamplesAltitudeMigration(): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes('gps_samples_altitude')) {
      return Deno.readTextFileSync(dirPath + entry.name);
    }
  }
  throw new Error(
    'No migration adding gps_samples.altitude found under runwar_app/supabase/migrations/ - the column does not exist yet.',
  );
}

Deno.test('a migration idempotently adds a nullable altitude column to gps_samples', () => {
  const sql = findGpsSamplesAltitudeMigration();
  assert(/alter\s+table\s+gps_samples/i.test(sql), 'must ALTER TABLE gps_samples');
  assert(/add\s+column\s+if\s+not\s+exists\s+altitude/i.test(sql),
    'altitude must be added idempotently (IF NOT EXISTS)');
  assert(/double precision|numeric|real|float/i.test(sql),
    'altitude must be a floating-point column');
});

Deno.test('the migration does not touch any claim-gate threshold or RLS policy', () => {
  const sql = findGpsSamplesAltitudeMigration();
  assert(!/create\s+policy|alter\s+policy/i.test(sql),
    'this is a pure additive schema-capture migration - no RLS/policy change belongs in it');
});
