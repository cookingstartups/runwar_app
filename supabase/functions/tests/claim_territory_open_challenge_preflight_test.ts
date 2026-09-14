// supabase/functions/tests/claim_territory_open_challenge_preflight_test.ts
//
// Anti-cheat pipeline, pass 2: claim_territory's open-challenge preflight
// gate. Follows the anticheat_score_flags_write_test.ts convention:
// Deno.readTextFileSync against the real handler source as text, assert on
// regex/substring code shapes, no live Postgres/Supabase client (handler.ts
// is a Deno.serve handler with no injectable database client here).
//
// Name distinguishes this file from the existing
// claim_territory_shape_gate_flag_test.ts, following the repo's
// claim_territory_<topic>_test.ts naming convention.
//
// Run: npx --yes deno@2 test --allow-read supabase/functions/tests/claim_territory_open_challenge_preflight_test.ts

import { assert, assertNotEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC_PATH = new URL('../claim_territory/handler.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

function rpcCallIndex(src: string): number {
  const single = src.indexOf("'has_open_challenge'");
  const double = src.indexOf('"has_open_challenge"');
  if (single === -1) return double;
  if (double === -1) return single;
  return Math.min(single, double);
}

function zonesSelectIndex(src: string): number {
  const single = src.indexOf(".from('zones')");
  const double = src.indexOf('.from("zones")');
  if (single === -1) return double;
  if (double === -1) return single;
  return Math.min(single, double);
}

Deno.test('the handler calls has_open_challenge via rpc', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge RPC call must be present in the source - it does not exist on the pre-Pass-2 handler');
  assert(/\.rpc\(/.test(src.slice(Math.max(0, rpcIdx - 50), rpcIdx + 50)),
    'has_open_challenge must be invoked via .rpc(...), not referenced as a plain string elsewhere');
});

Deno.test('a non-null result constructs a 403 response near the has_open_challenge check', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge must be present before a nearby 403 can be asserted - fails on unmodified source');
  const vicinity = src.slice(rpcIdx, rpcIdx + 1500);
  assert(/403/.test(vicinity),
    'a 403 status literal must appear within the has_open_challenge branch, not merely elsewhere in the file');
});

Deno.test('the blocked-path response body carries the literal challenge_required string', () => {
  const src = readSrc();
  assert(src.includes('challenge_required'),
    'the response body for the open-challenge branch must include the literal string challenge_required');
});

Deno.test('the blocked-path response body carries a challenge_id field', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1, 'has_open_challenge must be present to locate the challenge_id field near it');
  const vicinity = src.slice(rpcIdx, rpcIdx + 1500);
  assert(/challenge_id/.test(vicinity),
    'the 403 response body must carry a challenge_id field in the has_open_challenge branch');
});

Deno.test('the blocked-path branch writes pending_payload on the challenges table', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge must be present before a nearby pending_payload write can be asserted - fails on unmodified source');
  const vicinity = src.slice(rpcIdx, rpcIdx + 1500);
  assert(/pending_payload/.test(vicinity),
    'the branch must reference pending_payload');
  assert(vicinity.includes("'challenges'") || vicinity.includes('"challenges"'),
    'the branch must target the challenges table');
});

Deno.test('the has_open_challenge check occurs before the zones select in source order', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  const zonesIdx = zonesSelectIndex(src);
  // Explicit -1 checks first: on the pre-Pass-2 handler rpcIdx is -1 and a
  // naive `rpcIdx < zonesIdx` comparison would pass vacuously (-1 is
  // numerically less than any positive index), proving nothing. Asserting
  // both indices are real matches first turns that vacuous pass into a real
  // failure against unmodified source.
  assertNotEquals(rpcIdx, -1, 'has_open_challenge RPC call must be present in the source');
  assertNotEquals(zonesIdx, -1, 'the zones select call must still be present in the source');
  assert(rpcIdx < zonesIdx,
    'has_open_challenge must appear before the zones select in source order');
});

Deno.test('an rpc error on the has_open_challenge check does not fall through to the claim path', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge must be present before a nearby fail-closed error branch can be asserted');
  const vicinity = src.slice(rpcIdx, rpcIdx + 600);
  // Fail-closed shape: the destructured error variable from the
  // has_open_challenge rpc call must be checked and returned on, matching
  // this handler's own convention (if (splitErr) return err(...)) rather
  // than being ignored or only logged.
  assert(/error\s*:\s*\w*[Cc]hallenge\w*[Ee]rr\w*/.test(vicinity),
    'the has_open_challenge rpc destructure must capture an error variable');
  assert(/if\s*\(\s*\w*[Cc]hallenge\w*[Ee]rr\w*\s*\)\s*(\{)?\s*return/.test(vicinity),
    'an error from has_open_challenge must return immediately (fail closed), not fall through to the claim path');
});
