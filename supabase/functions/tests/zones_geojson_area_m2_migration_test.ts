// supabase/functions/tests/zones_geojson_area_m2_migration_test.ts
//
// zones.area_m2 already exists on the underlying table but the
// zones_geojson view - the only read path the Flutter Zone model has -
// does not select it. Source inspection, matching this repo's established
// migration-test convention.
//
// Run: npx deno test supabase/functions/tests/zones_geojson_area_m2_migration_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findZonesGeojsonAreaMigration(): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes('zones_geojson_area_m2')) {
      return Deno.readTextFileSync(dirPath + entry.name);
    }
  }
  throw new Error(
    'No migration exposing zones.area_m2 through zones_geojson found under runwar_app/supabase/migrations/ - the view does not select it yet.',
  );
}

Deno.test('a migration recreates zones_geojson selecting area_m2', () => {
  const sql = findZonesGeojsonAreaMigration();
  assert(/create\s+or\s+replace\s+view\s+zones_geojson/i.test(sql),
    'must CREATE OR REPLACE VIEW zones_geojson');
  assert(/area_m2/i.test(sql), 'the view must select area_m2');
});

Deno.test('the recreated view still selects every pre-existing column it replaces', () => {
  const sql = findZonesGeojsonAreaMigration();
  for (const col of ['id', 'owner_id', 'status', 'geom_json']) {
    assert(sql.includes(col), `the recreated view must still select ${col}`);
  }
});
