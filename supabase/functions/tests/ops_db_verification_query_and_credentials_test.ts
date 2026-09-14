// supabase/functions/tests/ops_db_verification_query_and_credentials_test.ts
//
// Covers the pure logic extracted out of ops/verify_deploy.ts's live I/O
// layer (council finding 5): PostgREST query construction that is
// structurally tied to a check's own table/columns (council finding 13's
// root cause), credential-tier validation (finding 2), --subject
// validation (finding 4), and gps-samples-present's row derivation. None of
// this needs a network call or a live database.
//
// Run: npx deno test --allow-read supabase/functions/tests/ops_db_verification_query_and_credentials_test.ts

import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildCheckQuery, buildRelatedQuery, CHECKS, deriveGpsSamplesRows } from '../../../ops/db_verification/checks.ts';
import { decodeJwtRole, isServiceRoleToken, isValidSubject } from '../../../ops/db_verification/cli.ts';

function findCheck(id: string) {
  const check = CHECKS.find((c) => c.id === id);
  if (!check) throw new Error(`check "${id}" not found`);
  return check;
}

function makeJwt(payload: Record<string, unknown>): string {
  const b64url = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(payload)}.fakesignature`;
}

// ---------------------------------------------------------------------------
// buildCheckQuery / buildRelatedQuery - the select= clause is derived
// directly from check.columns, so a renamed/mismatched column in checks.ts
// cannot silently diverge from the executed query (council finding 13).
// ---------------------------------------------------------------------------

Deno.test('buildCheckQuery derives the select= clause from the check own columns list', () => {
  const check = findCheck('zones-geom-exists');
  const query = buildCheckQuery(check, 'subject-1');
  assertEquals(query, `select=${check.columns.join(',')}&owner_id=eq.subject-1&status=eq.owned&geom=not.is.null&limit=1`);
});

Deno.test('buildCheckQuery reflects a mutated columns array with no second copy to update', () => {
  // Prove the select= clause is really DERIVED, not a second hand-copied
  // list: mutate the check's own columns and confirm the built query
  // changes with it, with nothing else edited.
  const check = findCheck('anticheat-flags-clear');
  const original = [...check.columns];
  check.columns.push('extra_col');
  try {
    const query = buildCheckQuery(check, 'subject-2');
    assertEquals(query.startsWith('select=id,user_id,flag_type,created_at,extra_col&'), true);
  } finally {
    check.columns.length = 0;
    check.columns.push(...original);
  }
});

Deno.test('buildRelatedQuery derives the select= clause from the related columns list', () => {
  const check = findCheck('gps-samples-present');
  const query = buildRelatedQuery(check, 'session-xyz');
  assertEquals(query, `select=${check.related!.columns.join(',')}&session_id=eq.session-xyz&limit=1`);
});

Deno.test('buildRelatedQuery throws for a check with no related query', () => {
  const check = findCheck('zones-geom-exists');
  assertThrows(() => buildRelatedQuery(check, 'x'));
});

// ---------------------------------------------------------------------------
// deriveGpsSamplesRows - the pure logic behind gps-samples-present's fetch,
// extracted so it is testable without a live database (council finding 5).
// ---------------------------------------------------------------------------

Deno.test('deriveGpsSamplesRows fails with an explicit reason when the subject has zero finalized runs', () => {
  // Regression for council finding 6: a subject with no finalized runs at
  // all used to vacuously pass this check.
  const rows = deriveGpsSamplesRows([], new Map());
  assertEquals(rows, [{ run_id: null, session_id: null, reason: 'no-finalized-runs' }]);
});

Deno.test('deriveGpsSamplesRows returns empty when every finalized run has samples', () => {
  const rows = deriveGpsSamplesRows(
    [{ id: 'r1', session_id: 's1' }, { id: 'r2', session_id: 's2' }],
    new Map([['s1', 3], ['s2', 1]]),
  );
  assertEquals(rows, []);
});

Deno.test('deriveGpsSamplesRows flags a finalized run with zero samples', () => {
  const rows = deriveGpsSamplesRows(
    [{ id: 'r1', session_id: 's1' }],
    new Map([['s1', 0]]),
  );
  assertEquals(rows, [{ run_id: 'r1', session_id: 's1' }]);
});

Deno.test('deriveGpsSamplesRows flags a finalized run with no session_id at all', () => {
  const rows = deriveGpsSamplesRows(
    [{ id: 'r1', session_id: null }],
    new Map(),
  );
  assertEquals(rows, [{ run_id: 'r1', session_id: null }]);
});

Deno.test("gps-samples-present.evaluate fails with the no-runs reason for the sentinel row", () => {
  const check = findCheck('gps-samples-present');
  const result = check.evaluate([{ run_id: null, session_id: null, reason: 'no-finalized-runs' }]);
  assertEquals(result.pass, false);
  assertEquals(result.detail.includes('no finalized run exists'), true);
});

// ---------------------------------------------------------------------------
// runs-finalized - an empty result must fail (council finding 6), not
// vacuously pass just because a subject has zero runs.
// ---------------------------------------------------------------------------

Deno.test('runs-finalized.evaluate fails when the subject has zero runs at all', () => {
  const check = findCheck('runs-finalized');
  const result = check.evaluate([]);
  assertEquals(result.pass, false);
  assertEquals(result.detail.includes('no run exists'), true);
});

Deno.test('runs-finalized.evaluate passes when every run for the subject is finalized', () => {
  const check = findCheck('runs-finalized');
  const result = check.evaluate([
    { id: 'r1', status: 'finished', ended_at: '2026-09-01T00:00:00Z', finalized_at: '2026-09-01T00:05:00Z' },
  ]);
  assertEquals(result.pass, true);
});

// ---------------------------------------------------------------------------
// Credential-tier validation - an RLS-denied read and a genuinely empty
// result both return HTTP 200 with [] over PostgREST, so the tool must
// refuse to run at all against a non-service-role key (council finding 2).
// ---------------------------------------------------------------------------

Deno.test('decodeJwtRole reads the role claim from a well-formed JWT', () => {
  const token = makeJwt({ role: 'service_role', iss: 'supabase' });
  assertEquals(decodeJwtRole(token), 'service_role');
});

Deno.test('decodeJwtRole returns null for a malformed token', () => {
  assertEquals(decodeJwtRole('not-a-jwt'), null);
  assertEquals(decodeJwtRole('a.b'), null);
  assertEquals(decodeJwtRole(''), null);
});

Deno.test('isServiceRoleToken is true only for a service_role JWT', () => {
  assertEquals(isServiceRoleToken(makeJwt({ role: 'service_role' })), true);
});

Deno.test('isServiceRoleToken is false for an anon-tier key, closing the RLS-denial-as-PASS hole', () => {
  // Regression for council finding 2: this is exactly the case where a
  // downgraded key would have silently turned an RLS-denied read into a
  // false PASS - loadCredentials (ops/verify_deploy.ts) must refuse here.
  assertEquals(isServiceRoleToken(makeJwt({ role: 'anon' })), false);
  assertEquals(isServiceRoleToken(makeJwt({ role: 'authenticated' })), false);
  assertEquals(isServiceRoleToken('garbage-not-a-jwt'), false);
});

// ---------------------------------------------------------------------------
// --subject validation - an unvalidated subject can be interpolated into a
// PostgREST filter to force an empty (false-PASS) result (council finding 4).
// ---------------------------------------------------------------------------

Deno.test('isValidSubject accepts a well-formed UUID', () => {
  assertEquals(isValidSubject('123e4567-e89b-12d3-a456-426614174000'), true);
});

Deno.test('isValidSubject rejects a filter-injection payload', () => {
  // Regression for council finding 4: --subject "<uuid>&limit=0" must be
  // rejected outright, not silently accepted and interpolated into a filter.
  assertEquals(isValidSubject('123e4567-e89b-12d3-a456-426614174000&limit=0'), false);
});

Deno.test('isValidSubject rejects plain non-UUID strings', () => {
  assertEquals(isValidSubject('player-123'), false);
  assertEquals(isValidSubject(''), false);
});
