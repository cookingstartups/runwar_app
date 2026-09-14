// supabase/functions/tests/ops_db_verification_catalog_test.ts
//
// Pins the six read-only per-deploy DB end-state checks (ops/db_verification/
// checks.ts) to stable ids and a single-SELECT query, so a future edit
// cannot silently drop, rename, or widen a check without a test noticing.
// Source inspection of the compiled catalog module, matching this repo's
// existing convention for logic with no local Postgres harness.
//
// Run: npx deno test --allow-read supabase/functions/tests/ops_db_verification_catalog_test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { CHECKS } from '../../../ops/db_verification/checks.ts';

const EXPECTED_IDS = [
  'zones-geom-exists',
  'zones-owner-matches',
  'zones-adjacent-merged',
  'runs-finalized',
  'gps-samples-present',
  'anticheat-flags-clear',
];

Deno.test('the catalog contains exactly the six documented end-state checks', () => {
  assertEquals(CHECKS.length, 6, 'the catalog must have exactly six checks');
});

Deno.test('every check has a stable, unique id from the documented set', () => {
  const ids = CHECKS.map((c) => c.id);
  assertEquals(new Set(ids).size, ids.length, 'ids must be unique');
  for (const id of EXPECTED_IDS) {
    assert(ids.includes(id), `missing expected check id: ${id}`);
  }
});

Deno.test('every check targets a real table and is a single read-only SELECT', () => {
  assert(CHECKS.length > 0, 'CHECKS must not be empty for this loop to check anything');
  for (const check of CHECKS) {
    assert(check.table.length > 0, `${check.id}: table must be set`);
    assert(/^\s*select\s/i.test(check.sql), `${check.id}: sql must start with SELECT`);
    assert(!/;\s*\S/.test(check.sql.trim()), `${check.id}: sql must be a single statement`);
    assert(
      !/\b(insert|update|delete|drop|alter|truncate|grant|create)\b/i.test(check.sql),
      `${check.id}: sql must not contain a mutating keyword`,
    );
  }
});

Deno.test('every check declares a non-empty evaluate function and columns list', () => {
  assert(CHECKS.length > 0, 'CHECKS must not be empty for this loop to check anything');
  for (const check of CHECKS) {
    assert(typeof check.evaluate === 'function', `${check.id}: evaluate must be a function`);
    assert(
      Array.isArray(check.columns) && check.columns.length > 0,
      `${check.id}: columns must be a non-empty list`,
    );
  }
});
