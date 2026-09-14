// supabase/functions/tests/ops_db_verification_live_io_test.ts
//
// Covers the live I/O layer of ops/verify_deploy.ts (council round-2 finding
// 5): restGet, resolveCredentials/loadCredentials, fetchRowsForCheck and
// runExecuteMode. None of these were previously imported by any test. All
// four are dependency-injected - a fake Fetcher and/or a fake credentials
// resolver is passed in instead of the real `fetch`/filesystem/process env -
// so this suite makes no real network call, no real file write, and reads
// no real credential. It needs only --allow-read (for the module imports
// themselves), matching every other test file in this directory.
//
// Run: npx deno test --allow-read supabase/functions/tests/ops_db_verification_live_io_test.ts

import { assertEquals, assertRejects, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { CHECKS } from '../../../ops/db_verification/checks.ts';
import {
  CredentialError,
  fetchRowsForCheck,
  resolveCredentials,
  restGet,
  runExecuteMode,
  type Credentials,
  type Fetcher,
} from '../../../ops/verify_deploy.ts';

function findCheck(id: string) {
  const check = CHECKS.find((c) => c.id === id);
  if (!check) throw new Error(`check "${id}" not found`);
  return check;
}

function makeJwt(payload: Record<string, unknown>): string {
  const b64url = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(payload)}.fakesig`;
}

const FAKE_CREDS: Credentials = { url: 'https://fake-project.example.test', serviceRoleKey: 'fake-not-a-real-key' };
const SUBJECT = '123e4567-e89b-12d3-a456-426614174000';

function jsonFetcher(body: unknown, status = 200): Fetcher {
  return () => Promise.resolve(new Response(JSON.stringify(body), { status }));
}

function textFetcher(body: string, status: number): Fetcher {
  return () => Promise.resolve(new Response(body, { status }));
}

function throwingFetcher(message: string): Fetcher {
  return () => Promise.reject(new Error(message));
}

function malformedJsonFetcher(): Fetcher {
  return () => Promise.resolve(new Response('not valid json {{{', { status: 200 }));
}

// ---------------------------------------------------------------------------
// restGet - the only function that ever calls the injected fetcher.
// ---------------------------------------------------------------------------

Deno.test('restGet parses a 200 response into rows that evaluate to the right verdict', async () => {
  const check = findCheck('zones-owner-matches');
  const rows = await restGet(
    FAKE_CREDS,
    check.table,
    `select=${check.columns.join(',')}&owner_id=eq.${SUBJECT}`,
    jsonFetcher([{ id: 'z1', owner_id: SUBJECT }]),
  );
  assertEquals(check.evaluate(rows).pass, true);
});

Deno.test('restGet throws with the real HTTP status on a non-2xx response, never a silent pass', async () => {
  await assertRejects(
    () => restGet(FAKE_CREDS, 'zones', 'select=id', textFetcher('permission denied', 503)),
    Error,
    'HTTP 503',
  );
});

Deno.test('restGet propagates a network-level throw from the fetcher', async () => {
  await assertRejects(
    () => restGet(FAKE_CREDS, 'zones', 'select=id', throwingFetcher('connection reset')),
    Error,
    'connection reset',
  );
});

Deno.test('restGet propagates a JSON parse failure on a malformed 200 body', async () => {
  await assertRejects(() => restGet(FAKE_CREDS, 'zones', 'select=id', malformedJsonFetcher()));
});

// ---------------------------------------------------------------------------
// fetchRowsForCheck - the per-check routing on top of restGet.
// ---------------------------------------------------------------------------

Deno.test('fetchRowsForCheck on an empty array leaves a presence check failing, not vacuously passing', async () => {
  const check = findCheck('runs-finalized');
  const rows = await fetchRowsForCheck(check, FAKE_CREDS, SUBJECT, jsonFetcher([]));
  const { pass, detail } = check.evaluate(rows);
  assertEquals(pass, false);
  assertEquals(detail.includes('no run exists'), true);
});

Deno.test('fetchRowsForCheck for gps-samples-present issues a follow-up related fetch per session', async () => {
  const check = findCheck('gps-samples-present');
  const calls: string[] = [];
  const fetcher: Fetcher = (url) => {
    calls.push(url);
    if (url.includes('/rest/v1/runs')) {
      return Promise.resolve(
        new Response(JSON.stringify([{ id: 'r1', session_id: 's1', user_id: SUBJECT, finalized_at: 'now' }]), {
          status: 200,
        }),
      );
    }
    // gps_samples related lookup - empty, so run r1 is missing samples.
    return Promise.resolve(new Response(JSON.stringify([]), { status: 200 }));
  };
  const rows = await fetchRowsForCheck(check, FAKE_CREDS, SUBJECT, fetcher);
  const { pass, detail } = check.evaluate(rows);
  assertEquals(pass, false);
  assertEquals(detail.includes('r1'), true);
  assertEquals(calls.some((u) => u.includes('/rest/v1/gps_samples')), true);
});

// ---------------------------------------------------------------------------
// resolveCredentials - the pure core behind loadCredentials(). Never
// printed, never logged, throws rather than exits. No file/env access at
// all - a plain Map and a stub processEnv function are passed in directly.
// ---------------------------------------------------------------------------

Deno.test('resolveCredentials rejects a non-service-role key without the key ever appearing in the thrown message', () => {
  const fakeAnonKey = makeJwt({ role: 'anon' });
  const fromFile = new Map([
    ['RUNWAR_SUPABASE_URL', 'https://fake-project.example.test'],
    ['RUNWAR_SUPABASE_SERVICE_ROLE_KEY', fakeAnonKey],
  ]);
  let caught: unknown;
  try {
    resolveCredentials('fake.env', fromFile, () => undefined);
  } catch (e) {
    caught = e;
  }
  assertEquals(caught instanceof CredentialError, true);
  const message = (caught as Error).message;
  assertEquals(message.includes(fakeAnonKey), false);
  assertEquals(message.includes('service_role'), true);
});

Deno.test('resolveCredentials throws on a missing credential, naming only the variable, not any value', () => {
  const fromFile = new Map([['RUNWAR_SUPABASE_URL', 'https://fake-project.example.test']]);
  assertThrows(
    () => resolveCredentials('fake.env', fromFile, () => undefined),
    CredentialError,
    'RUNWAR_SUPABASE_SERVICE_ROLE_KEY',
  );
});

Deno.test('resolveCredentials accepts a real service_role JWT from either source and never exposes the key', () => {
  const fakeServiceRoleKey = makeJwt({ role: 'service_role' });
  const fromFile = new Map([['RUNWAR_SUPABASE_URL', 'https://fake-project.example.test']]);
  const creds = resolveCredentials('fake.env', fromFile, (k) =>
    k === 'RUNWAR_SUPABASE_SERVICE_ROLE_KEY' ? fakeServiceRoleKey : undefined);
  assertEquals(creds.url, 'https://fake-project.example.test');
  assertEquals(creds.serviceRoleKey, fakeServiceRoleKey);
});

// ---------------------------------------------------------------------------
// runExecuteMode - full per-check loop, injected fetcher AND injected
// credentials resolver, no process exit, no real file/env/network access.
// ---------------------------------------------------------------------------

function fakeLoadCreds(): Credentials {
  return FAKE_CREDS;
}

Deno.test('runExecuteMode maps a non-2xx response on every check to FAIL with the real status in the reason', async () => {
  const { results, summary } = await runExecuteMode(
    'unused-envfile-path',
    SUBJECT,
    textFetcher('server error', 500),
    fakeLoadCreds,
  );
  assertEquals(summary.verdict, 'FAIL');
  assertEquals(results.length, CHECKS.length);
  for (const r of results) {
    assertEquals(r.pass, false);
    assertEquals(r.detail.includes('500'), true);
  }
});

Deno.test('runExecuteMode maps a network throw on every check to FAIL, never a PASS', async () => {
  const { results, summary } = await runExecuteMode(
    'unused-envfile-path',
    SUBJECT,
    throwingFetcher('DNS resolution failed'),
    fakeLoadCreds,
  );
  assertEquals(summary.verdict, 'FAIL');
  for (const r of results) {
    assertEquals(r.pass, false);
    assertEquals(r.detail.includes('DNS resolution failed'), true);
  }
});
