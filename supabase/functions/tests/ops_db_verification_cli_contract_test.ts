// supabase/functions/tests/ops_db_verification_cli_contract_test.ts
//
// Pins the CLI's credential-free-by-default contract: the no-flags
// invocation must stay in catalog mode and never touch an env file, and
// --execute without --env-file must silently degrade back to catalog mode
// rather than attempt to run anything. Also pins summarize()'s verdict
// arithmetic.
//
// Run: npx deno test --allow-read supabase/functions/tests/ops_db_verification_cli_contract_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parseArgs, summarize } from '../../../ops/db_verification/cli.ts';

Deno.test('no flags at all yields catalog mode with no env file and no subject', () => {
  assertEquals(parseArgs([]), { mode: 'catalog', envFile: null, subject: null });
});

Deno.test('--execute with --env-file yields execute mode with the given env file', () => {
  assertEquals(
    parseArgs(['--execute', '--env-file', '/tmp/verify.env']),
    { mode: 'execute', envFile: '/tmp/verify.env', subject: null },
  );
});

Deno.test('--execute without --env-file degrades to catalog mode, never executes', () => {
  assertEquals(parseArgs(['--execute']), { mode: 'catalog', envFile: null, subject: null });
});

Deno.test('--subject is captured independently of mode', () => {
  assertEquals(
    parseArgs(['--subject', 'player-123']),
    { mode: 'catalog', envFile: null, subject: 'player-123' },
  );
});

Deno.test('summarize reports PASS verdict when every result passed', () => {
  const result = summarize([
    { id: 'a', pass: true, detail: 'ok' },
    { id: 'b', pass: true, detail: 'ok' },
  ]);
  assertEquals(result, {
    passed: 2,
    failed: 0,
    verdict: 'PASS',
    lines: ['PASS a: ok', 'PASS b: ok'],
  });
});

Deno.test('summarize reports FAIL verdict when at least one result failed', () => {
  const result = summarize([
    { id: 'a', pass: true, detail: 'ok' },
    { id: 'b', pass: false, detail: 'zone missing geom' },
  ]);
  assertEquals(result, {
    passed: 1,
    failed: 1,
    verdict: 'FAIL',
    lines: ['PASS a: ok', 'FAIL b: zone missing geom'],
  });
});

Deno.test('summarize reports FAIL verdict on an empty result set', () => {
  const result = summarize([]);
  assertEquals(result, { passed: 0, failed: 0, verdict: 'FAIL', lines: [] });
});
