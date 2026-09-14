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

import { assert, assertFalse, assertNotEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

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

// Locates the SPECIFIC zones SELECT call the design references
// (handler.ts:661-669, "Load existing zones for this city"), not just any
// occurrence of `.from('zones')` in the file - the same handler also has
// several earlier `.from('zones').update(...)` write calls inside an
// unrelated helper function (shield-aware conquest/dispute resolution),
// positioned BEFORE this task's preflight insertion point. Matching those
// would make the ordering test fail even against a fully correct
// implementation. A `.from('zones')` immediately followed by `.select(` is
// this specific read call.
function zonesSelectIndex(src: string): number {
  const regex = /\.from\((?:'zones'|"zones")\)\s*\n?\s*\.select\(/;
  const match = regex.exec(src);
  return match ? match.index : -1;
}

// Locates the { data: <var>, error: <var> } destructure feeding the
// has_open_challenge rpc call and returns the name bound to `data` - the
// identifier that must later scope the pending_payload UPDATE by id.
function extractChallengeIdVar(src: string, rpcIdx: number): string | null {
  const before = src.slice(Math.max(0, rpcIdx - 200), rpcIdx);
  const match = /data\s*:\s*(\w+)/.exec(before);
  return match ? match[1] : null;
}

// Extracts the full braced block starting at the first `{` after a match of
// ifRegex, using manual brace-depth counting rather than a regex, since a
// naive `[^}]*` cannot survive the nested object literals/destructures the
// real open-challenge branch contains (the pending_payload update's object
// literal and the error destructure both contain their own `}` characters).
function extractIfBlock(src: string, ifRegex: RegExp): string {
  const match = ifRegex.exec(src);
  if (!match) return '';
  const openBraceIdx = src.indexOf('{', match.index);
  if (openBraceIdx === -1) return '';
  let depth = 0;
  for (let i = openBraceIdx; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(openBraceIdx, i + 1);
    }
  }
  return '';
}

Deno.test('the handler calls has_open_challenge via rpc', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge RPC call must be present in the source - it does not exist on the pre-Pass-2 handler');

  // Reject a stray reference inside a // line comment (e.g. an unimplemented
  // TODO) by confirming the source line containing the match is not itself
  // a comment line.
  const lineStart = src.lastIndexOf('\n', rpcIdx) + 1;
  const lineEndIdx = src.indexOf('\n', rpcIdx);
  const line = src.slice(lineStart, lineEndIdx === -1 ? src.length : lineEndIdx);
  assertFalse(/^\s*\/\//.test(line),
    'has_open_challenge must be a live call, not referenced only inside a // comment');

  const before = src.slice(Math.max(0, rpcIdx - 200), rpcIdx);
  assert(/await\s+\w+[\s\S]{0,30}\.rpc\(\s*$/.test(before),
    'has_open_challenge must be invoked as await <client>.rpc(...), immediately preceding the RPC name literal - a commented-out or merely-referenced call must fail this test');
  assert(/data\s*:\s*\w+/.test(before) && /error\s*:\s*\w+/.test(before),
    'the call must destructure both data and error from the rpc result, not merely reference the RPC name string');
});

Deno.test('a non-null result constructs a 403 response near the has_open_challenge check', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge must be present before a nearby 403 can be asserted - fails on unmodified source');
  const vicinity = src.slice(rpcIdx, rpcIdx + 1500);
  assert(/403/.test(vicinity),
    'a 403 status literal must appear within the has_open_challenge branch, not merely elsewhere in the file');
  assert(/403[\s\S]{0,220}challenge_required/.test(vicinity) || /challenge_required[\s\S]{0,220}403/.test(vicinity),
    'the 403 status and the challenge_required response body must appear together as one response, not as two unrelated nearby literals');
});

Deno.test('the blocked-path response body carries the literal challenge_required string', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge must be present before a nearby challenge_required string can be asserted - fails on unmodified source');
  const vicinity = src.slice(rpcIdx, rpcIdx + 1500);
  assert(vicinity.includes('challenge_required'),
    'the response body for the open-challenge branch must include the literal string challenge_required within the has_open_challenge branch, not merely elsewhere in the file (e.g. an unrelated comment)');
});

Deno.test('the blocked-path response body carries a challenge_id field', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1, 'has_open_challenge must be present to locate the challenge_id field near it');
  const vicinity = src.slice(rpcIdx, rpcIdx + 1500);
  assert(/challenge_id/.test(vicinity),
    'the 403 response body must carry a challenge_id field in the has_open_challenge branch');
});

Deno.test('the blocked-path branch writes pending_payload on the challenges table, scoped by challenge id', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge must be present before a nearby pending_payload write can be asserted - fails on unmodified source');

  const vicinity = src.slice(rpcIdx, rpcIdx + 1500);
  assert(/pending_payload/.test(vicinity), 'the branch must reference pending_payload');
  assert(vicinity.includes("'challenges'") || vicinity.includes('"challenges"'),
    'the branch must target the challenges table');

  const challengeIdVar = extractChallengeIdVar(src, rpcIdx);
  assert(challengeIdVar !== null,
    'the has_open_challenge rpc call must destructure a data variable identifying which challenge was found, so the pending_payload write can be scoped to it');

  const eqIdRegex = new RegExp(`\\.eq\\(\\s*['"]id['"]\\s*,\\s*${challengeIdVar}\\s*\\)`);
  assert(eqIdRegex.test(vicinity),
    `the pending_payload UPDATE must be scoped by .eq('id', ${challengeIdVar}) - an update of every challenges row, or one scoped by an unrelated identifier, must fail this test`);
});

Deno.test('the has_open_challenge check occurs before the zones select and before track/gate parsing in source order', () => {
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

  // AC-6's actual risk is an early claim-shaped ok({result:'failed', ...})
  // return happening before the gate, not merely "before the zones select" -
  // check directly against the earlier track/gate-parsing identifiers too,
  // so a future refactor that moves the preflight below hasCorruptHop but
  // still above the zones select would still fail this test.
  const corruptHopIdx = src.indexOf('function hasCorruptHop');
  // evaluateCapturedRingGates is declared as a top-level EXPORTED function
  // earlier in the module file (before handleClaimTerritoryRequest itself),
  // so a plain indexOf of the identifier would match that declaration (and
  // an even earlier doc-comment mention), not the actual call site inside
  // the handler this ordering check cares about. Match a real call
  // (identifier immediately followed by `(`) that is not the `function
  // evaluateCapturedRingGates(` declaration itself.
  const gatesCallRegex = /(?<!function\s)evaluateCapturedRingGates\(/g;
  let gatesIdx = -1;
  for (const m of src.matchAll(gatesCallRegex)) {
    gatesIdx = m.index!;
    break;
  }
  assertNotEquals(corruptHopIdx, -1, 'hasCorruptHop must still be declared in the source');
  assertNotEquals(gatesIdx, -1, 'evaluateCapturedRingGates must still be called in the source');
  assert(rpcIdx < corruptHopIdx,
    'has_open_challenge must appear before hasCorruptHop is declared/used');
  assert(rpcIdx < gatesIdx,
    'has_open_challenge must appear before evaluateCapturedRingGates runs');
});

Deno.test('an rpc error on the has_open_challenge check returns an error response, not a fall-through', () => {
  const src = readSrc();
  const rpcIdx = rpcCallIndex(src);
  assertNotEquals(rpcIdx, -1,
    'has_open_challenge must be present before a nearby fail-closed error branch can be asserted');
  const vicinity = src.slice(rpcIdx, rpcIdx + 600);
  // Fail-closed shape: the destructured error variable from the
  // has_open_challenge rpc call must be checked and returned on, matching
  // this handler's own convention (if (splitErr) return err(...)) rather
  // than being ignored or only logged. The destructure precedes the .rpc(
  // call in source order (`const { data, error: xErr } = await
  // supabase.rpc(...)`), so this must look BACKWARD from rpcIdx, not
  // forward - a forward-only window would never see it.
  const before = src.slice(Math.max(0, rpcIdx - 200), rpcIdx);
  assert(/error\s*:\s*\w*[Cc]hallenge\w*[Ee]rr\w*/.test(before),
    'the has_open_challenge rpc destructure must capture an error variable');

  // The matched return must itself be `return err(` - a bare `return;` or a
  // claim-shaped `return ok(...)` (fail-open) must NOT satisfy this: a regex
  // that only checks "some return exists" cannot distinguish fail-closed
  // from fail-open, which is the exact security property this branch exists
  // to guarantee (design.md's Fail-open-vs-fail-closed section).
  const failClosedMatch = /if\s*\(\s*\w*[Cc]hallenge\w*[Ee]rr\w*\s*\)\s*(\{)?\s*return\s+err\(/.exec(vicinity);
  assert(failClosedMatch !== null,
    'an error from has_open_challenge must return err(...) immediately (fail closed) - a fail-open branch such as "return ok(...)" or a bare "return;" must fail this test');

  // Separately require the 500 status literal within the same return
  // statement's vicinity, so a fail-closed return using the wrong (non-500,
  // e.g. default-400) status also fails - matching design.md's explicit
  // "hard fail, 500" decision for this specific RPC-error path.
  const afterReturn = vicinity.slice(failClosedMatch.index, failClosedMatch.index + 200);
  assert(/\b500\b/.test(afterReturn),
    'the fail-closed error response must use a 500 status, matching this handler\'s hard-fail convention for a security-gate RPC error');
});

Deno.test('the open-challenge branch returns the 403 response rather than falling through to zones/claim code', () => {
  const src = readSrc();
  const ifRegex = /if\s*\(\s*\w*[Oo]pen\w*[Cc]hallenge\w*\s*\)\s*\{/;
  const block = extractIfBlock(src, ifRegex);
  assertNotEquals(block, '',
    'the if (openChallengeId) block must be present in the source - fails on unmodified/pre-implementation handler');

  assert(!block.includes(".from('zones')") && !block.includes('.from("zones")'),
    'the open-challenge branch must not itself reach the zones select - it must return before any zone/claim code runs');

  // A narrower sub-branch (the pending_payload UPDATE error) also returns
  // inside this block, so checking "some return exists in the block" (or
  // even "some return exists, and 403/challenge_required text exists
  // somewhere after it") is not enough - a broken implementation that
  // CONSTRUCTS the 403 Response without the return keyword (e.g.
  // `const resp = new Response(...)`) would still satisfy either check,
  // since the pendingPayloadErr sub-branch's own unrelated `return err(...)`
  // sits textually just before the un-returned 403 construction. The only
  // check that actually distinguishes these is: does "return" appear
  // DIRECTLY governing the specific expression that constructs the
  // challenge_required body, not just somewhere earlier in the block.
  const crIdx = block.indexOf('challenge_required');
  assert(crIdx !== -1,
    'challenge_required must appear inside the open-challenge block - fails if the 403 body is built outside this if-block entirely');
  const backWindow = block.slice(Math.max(0, crIdx - 150), crIdx);
  assert(/return\s+(new Response\(|err\()/.test(backWindow),
    'the challenge_required response must be directly returned (return new Response(...) or return err(...)) - constructing the Response object without the return keyword (e.g. "const resp = new Response(...)") would silently fall through to zones/claim code, and must fail this test');
});

Deno.test('a pending_payload UPDATE error on the open-challenge branch returns a fail-closed error response, not a fall-through to the 403', () => {
  const src = readSrc();
  const ifRegex = /if\s*\(\s*\w*[Oo]pen\w*[Cc]hallenge\w*\s*\)\s*\{/;
  const block = extractIfBlock(src, ifRegex);
  assertNotEquals(block, '',
    'the if (openChallengeId) block must be present in the source - fails on unmodified/pre-implementation handler');

  const errVarMatch = /error\s*:\s*(\w*[Pp]ending\w*[Pp]ayload\w*[Ee]rr\w*)/.exec(block);
  assert(errVarMatch !== null,
    'the pending_payload UPDATE must destructure an error variable (e.g. pendingPayloadErr)');
  const errVar = errVarMatch[1];

  const ifPendingRegex = new RegExp(`if\\s*\\(\\s*${errVar}\\s*\\)\\s*\\{?`);
  const ifPendingMatch = ifPendingRegex.exec(block);
  assert(ifPendingMatch !== null,
    `the block must check if (${errVar}) after the pending_payload UPDATE`);

  // Fail-closed shape: the branch must return err(...) immediately, matching
  // this handler's own convention - a bare "return;" or a fail-open
  // fall-through into the 403 challenge_required build below must not
  // satisfy this.
  const afterIf = block.slice(ifPendingMatch.index, ifPendingMatch.index + 200);
  assert(/return\s+err\(/.test(afterIf),
    'a pending_payload UPDATE error must return err(...) immediately (fail closed) - a fail-open branch that falls through to the 403 challenge_required response, or a bare "return;", must fail this test');
  assert(/\b500\b/.test(afterIf),
    'the fail-closed pending_payload error response must use a 500 status, matching this handler\'s hard-fail convention for a security-gate write error');

  // Ordering: the pendingPayloadErr fail-closed return must occur BEFORE the
  // challenge_required 403 construction in source order - not merely appear
  // somewhere in the block - so the 403 body is unreachable whenever
  // pendingPayloadErr is set.
  const crIdx = block.indexOf('challenge_required');
  assert(crIdx !== -1, 'challenge_required must appear inside the open-challenge block');
  assert(ifPendingMatch.index < crIdx,
    'the pendingPayloadErr fail-closed check must occur before the challenge_required 403 response is constructed, so a write error cannot fall through into the 403 body');
});
