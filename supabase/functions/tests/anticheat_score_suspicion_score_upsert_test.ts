// supabase/functions/tests/anticheat_score_suspicion_score_upsert_test.ts
//
// Pass 1 net-new write: suspicion_scores must be maintained via the atomic
// upsert_suspicion_score SQL function (called through .rpc()), not a plain
// client-side .upsert(), because the GREATEST/increment semantics cannot be
// expressed through a PostgREST merge upsert. Source inspection, same
// convention as the sibling flags-write test in this directory.
//
// Run: npx deno test supabase/functions/tests/anticheat_score_suspicion_score_upsert_test.ts

import { assert, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';

function readSrc(): string {
  return Deno.readTextFileSync(new URL('../anticheat_score/index.ts', import.meta.url));
}

Deno.test('every batch calls the upsert_suspicion_score RPC function, not a plain client-side upsert', () => {
  const src = readSrc();
  assert(/\.rpc\(\s*['"]upsert_suspicion_score['"]/.test(src),
    'suspicion_scores must be maintained via the upsert_suspicion_score RPC, not written directly');
  assertFalse(/from\(\s*['"]suspicion_scores['"]\s*\)\s*\.upsert\(/.test(src),
    'a plain .upsert() cannot express the GREATEST/increment semantics this table requires - it must go through the RPC');
});

Deno.test('the RPC call passes the batch session max score, run id, and this batch\'s flag count', () => {
  const src = readSrc();
  const rpcIdx = src.indexOf("rpc('upsert_suspicion_score'");
  assert(rpcIdx >= 0, 'expected the upsert_suspicion_score rpc call to exist');
  const callWindow = src.slice(rpcIdx, rpcIdx + 300);
  assert(callWindow.includes('p_user_id'), 'must pass p_user_id');
  assert(callWindow.includes('p_session_max_score'), 'must pass p_session_max_score');
  assert(callWindow.includes('p_run_id'), 'must pass p_run_id');
  assert(callWindow.includes('p_flags_this_batch'), 'must pass p_flags_this_batch so flags_count can increment');
});
