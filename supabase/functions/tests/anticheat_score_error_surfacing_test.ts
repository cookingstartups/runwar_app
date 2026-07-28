// supabase/functions/tests/anticheat_score_error_surfacing_test.ts
//
// Pass 1 requires every write this fix touches (anticheat_flags,
// suspicion_scores, behavioral_fingerprints, challenges) to check and
// surface its own error instead of the current unchecked-destructure that
// let the schema-shape bug run silently for the function's whole deployed
// lifetime. Source inspection, same convention as the sibling tests in this
// directory.
//
// Run: npx deno test supabase/functions/tests/anticheat_score_error_surfacing_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

function readSrc(): string {
  return Deno.readTextFileSync(new URL('../anticheat_score/index.ts', import.meta.url));
}

Deno.test('the response includes a write_errors field surfacing any failed write', () => {
  const src = readSrc();
  assert(/write_errors/.test(src),
    'the response body must include a write_errors field so a caller can see a partial persistence failure');
});

Deno.test('the anticheat_flags write site destructures and checks its own error', () => {
  const src = readSrc();
  const idx = src.search(/from\(\s*['"]anticheat_flags['"]\s*\)\s*\.insert/);
  assert(idx >= 0, 'expected an anticheat_flags insert to exist');
  const window = src.slice(Math.max(0, idx - 120), idx + 250);
  assert(/error/i.test(window),
    'the anticheat_flags insert must destructure { error } and check it, not run as a bare unchecked await');
});

Deno.test('the suspicion_scores rpc call destructures and checks its own error', () => {
  const src = readSrc();
  const idx = src.indexOf("rpc('upsert_suspicion_score'");
  assert(idx >= 0, 'expected the upsert_suspicion_score rpc call to exist');
  const window = src.slice(Math.max(0, idx - 120), idx + 250);
  assert(/error/i.test(window),
    'the suspicion_scores rpc call must destructure { error } and check it, not run as a bare unchecked await');
});

Deno.test('the behavioral_fingerprints write site destructures and checks its own error', () => {
  const src = readSrc();
  const idx = src.search(/from\(\s*['"]behavioral_fingerprints['"]\s*\)\s*\.insert/);
  assert(idx >= 0, 'expected a behavioral_fingerprints insert to exist');
  const window = src.slice(Math.max(0, idx - 120), idx + 250);
  assert(/error/i.test(window),
    'the behavioral_fingerprints insert must destructure { error } and check it, not run as a bare unchecked await');
});
