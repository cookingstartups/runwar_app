// supabase/functions/tests/claim_territory_level_up_cooldown_test.ts
//
// RED phase - real per-scenario tests for the repeat-run damping / level-up
// cooldown decision. Targets a NEW pure export,
// computeLevelUpOutcome(priorLastActiveAt, nowMs, cooldownMs, currentLevel),
// which does not exist yet in ../claim_territory/merge_geometry.ts.
//
// The decision itself - given a prior last_active_at, the current time, the
// cooldown window and the row's current level, does the level increment or
// not, clamped at 15 - has no I/O and no geometry in it at all (design.md
// Section 4's own formula is copied here almost verbatim). Extracting it as
// a pure function, mirroring computeZoneMerges/computeZoneSplit in this
// same module, is what makes a mock-free behavioural test possible; the
// ACTUAL wiring - reading last_active_at from the DB before overwriting it,
// and writing the outcome back via the merge/level-up RPC block - remains
// genuinely untestable without a live Supabase instance and stays covered
// by the source-inspection wiring checks in
// claim_territory_split_cooldown_wiring_test.ts. As with the split-geometry
// test file, this is a recommended interface addition beyond what
// design.md's file-by-file plan currently lists, flagged for confirmation
// before implementation, otherwise this file stays red even after a
// behaviourally-correct inline implementation.
//
// Run: npx deno test supabase/functions/tests/claim_territory_level_up_cooldown_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeLevelUpOutcome } from '../claim_territory/merge_geometry.ts';

const COOLDOWN_MS = 15000; // demo-mode value per design.md Section 4

Deno.test('a re-claim inside the cooldown window updates state but does not increment the level', () => {
  const now = 1_000_000_000_000;
  const priorLastActiveAt = new Date(now - 10_000).toISOString(); // 10s ago

  const outcome = computeLevelUpOutcome(priorLastActiveAt, now, COOLDOWN_MS, 3);

  assertEquals(outcome.cooldownActive, true);
  assertEquals(outcome.nextLevel, 3,
    'influence_level must not increment while the cooldown from the last claim is still active');
});

Deno.test('a re-claim after the cooldown has elapsed may increment the level normally', () => {
  const now = 1_000_000_000_000;
  const priorLastActiveAt = new Date(now - 20_000).toISOString(); // 20s ago

  const outcome = computeLevelUpOutcome(priorLastActiveAt, now, COOLDOWN_MS, 3);

  assertEquals(outcome.cooldownActive, false);
  assertEquals(outcome.nextLevel, 4,
    'once the cooldown has elapsed, a re-claim is an ordinary level-up event');
});

Deno.test('a zone already at the level-15 clamp stays at 15 even when the cooldown has elapsed', () => {
  const now = 1_000_000_000_000;
  const priorLastActiveAt = new Date(now - 20_000).toISOString(); // cooldown elapsed

  const outcome = computeLevelUpOutcome(priorLastActiveAt, now, COOLDOWN_MS, 15);

  assertEquals(outcome.cooldownActive, false);
  assertEquals(outcome.nextLevel, 15,
    'the level-15 ceiling applies regardless of cooldown state - a maxed-out re-run is never wasted, '
      + 'but it also never exceeds the clamp');
});

Deno.test('a zone already at the level-15 clamp stays at 15 while the cooldown is still active', () => {
  const now = 1_000_000_000_000;
  const priorLastActiveAt = new Date(now - 10_000).toISOString(); // cooldown active

  const outcome = computeLevelUpOutcome(priorLastActiveAt, now, COOLDOWN_MS, 15);

  assertEquals(outcome.cooldownActive, true);
  assertEquals(outcome.nextLevel, 15,
    'the clamp and an active cooldown independently agree on the same outcome at the ceiling');
});

Deno.test('a zone with no prior last_active_at (first-ever claim) is never treated as cooldown-active', () => {
  const now = 1_000_000_000_000;

  const outcome = computeLevelUpOutcome(null, now, COOLDOWN_MS, 1);

  assertEquals(outcome.cooldownActive, false);
  assertEquals(outcome.nextLevel, 2,
    'a zone with no recorded prior activity has nothing to damp against and levels up normally');
});
