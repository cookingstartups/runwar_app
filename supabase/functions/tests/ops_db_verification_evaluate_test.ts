// supabase/functions/tests/ops_db_verification_evaluate_test.ts
//
// Exercises each of the six checks' evaluate() against a passing-shape and
// a failing-shape fixture, derived from the real columns in
// runwar_app/supabase/migrations (see ops_db_verification_schema_grounding_test.ts)
// and the write shapes in supabase/functions/anticheat_score/index.ts and
// supabase/functions/finalize_run/index.ts. Looking a check up by id throws
// while the catalog is still empty (RED-phase stub) - that failure is
// itself the intended RED signal for this feature not existing yet, not a
// generic setup error, since the id is the real documented contract pinned
// by ops_db_verification_catalog_test.ts.
//
// Run: npx deno test --allow-read supabase/functions/tests/ops_db_verification_evaluate_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { CHECKS } from '../../../ops/db_verification/checks.ts';

function findCheck(id: string) {
  const check = CHECKS.find((c) => c.id === id);
  if (!check) {
    throw new Error(`check "${id}" not found - catalog is empty until the feature is implemented`);
  }
  return check;
}

Deno.test('zones-geom-exists passes only when a zone row exists with a non-null geom', () => {
  const check = findCheck('zones-geom-exists');
  assertEquals(
    check.evaluate([{ id: 'z1', owner_id: 'p1', geom: 'POLYGON((0 0,1 0,1 1,0 0,0 0))' }]).pass,
    true,
  );
  assertEquals(check.evaluate([{ id: 'z1', owner_id: 'p1', geom: null }]).pass, false);
  assertEquals(check.evaluate([]).pass, false);
});

Deno.test('zones-owner-matches passes only when the owner-filtered row is present', () => {
  const check = findCheck('zones-owner-matches');
  assertEquals(check.evaluate([{ id: 'z1', owner_id: 'p1' }]).pass, true);
  assertEquals(check.evaluate([]).pass, false);
});

Deno.test('zones-adjacent-merged fails when two same-owner zones are left touching', () => {
  const check = findCheck('zones-adjacent-merged');
  assertEquals(check.evaluate([]).pass, true);
  assertEquals(
    check.evaluate([{ a_id: 'z1', b_id: 'z2', owner_id: 'p1' }]).pass,
    false,
  );
});

Deno.test('runs-finalized fails when a run is stuck without a terminal status and end time', () => {
  const check = findCheck('runs-finalized');
  assertEquals(check.evaluate([]).pass, true);
  assertEquals(
    check.evaluate([{ id: 'r1', status: 'active', ended_at: null, finalized_at: null }]).pass,
    false,
  );
});

Deno.test('gps-samples-present fails when a finalized run has zero gps_samples rows', () => {
  const check = findCheck('gps-samples-present');
  assertEquals(check.evaluate([]).pass, true);
  assertEquals(
    check.evaluate([{ run_id: 'r1', session_id: 's1' }]).pass,
    false,
  );
});

Deno.test('anticheat-flags-clear fails when an unresolved flag exists for the subject player', () => {
  const check = findCheck('anticheat-flags-clear');
  assertEquals(check.evaluate([]).pass, true);
  assertEquals(
    check.evaluate([
      { id: 'f1', user_id: 'p1', flag_type: 'speed_impossible', created_at: '2026-09-01T00:00:00Z' },
    ]).pass,
    false,
  );
});
