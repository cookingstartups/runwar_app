// supabase/functions/tests/anticheat_score_write_ordering_test.ts
//
// The designed partial-write degradation order for Pass 1: the
// behavioral_fingerprints read runs first (it feeds flags/score), then the
// anticheat_flags insert, the behavioral_fingerprints write, and the
// suspicion_scores upsert run concurrently via Promise.allSettled (no
// ordering dependency among them), then the conditional challenges insert
// runs last. Source inspection, same convention as the sibling tests in
// this directory.
//
// Run: npx deno test supabase/functions/tests/anticheat_score_write_ordering_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

function readSrc(): string {
  return Deno.readTextFileSync(new URL('../anticheat_score/index.ts', import.meta.url));
}

Deno.test('the three independent writes run concurrently via Promise.allSettled', () => {
  const src = readSrc();
  assert(src.includes('Promise.allSettled'),
    'anticheat_flags, behavioral_fingerprints write, and suspicion_scores upsert have no ordering dependency among them and must run concurrently, not as three sequential awaits');
});

Deno.test('the challenges insert runs after the concurrent write batch, not before it', () => {
  const src = readSrc();
  const allSettledIdx = src.indexOf('Promise.allSettled');
  const challengesIdx = src.search(/from\(\s*['"]challenges['"]\s*\)\s*\.insert/);
  assert(allSettledIdx >= 0 && challengesIdx >= 0, 'both the concurrent write batch and the challenges insert must exist');
  assert(allSettledIdx < challengesIdx,
    'the challenges insert depends only on the already-known score and must not race the other three writes');
});

Deno.test('the fingerprint read runs before the concurrent write batch, since it feeds flags/score', () => {
  const src = readSrc();
  const readIdx = src.search(/from\(\s*['"]behavioral_fingerprints['"]\s*\)\s*\.select/);
  const allSettledIdx = src.indexOf('Promise.allSettled');
  assert(readIdx >= 0 && allSettledIdx >= 0, 'both the fingerprint read and the concurrent write batch must exist');
  assert(readIdx < allSettledIdx,
    'flags/score must be finalized (which requires the fingerprint read) before the concurrent writes fire');
});
