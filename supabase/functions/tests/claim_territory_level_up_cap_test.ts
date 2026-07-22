// supabase/functions/tests/claim_territory_level_up_cap_test.ts
//
// Real per-scenario tests for repeat-run damping: computeNextInfluenceLevel
// in ../claim_territory/merge_geometry.ts. The rule is a level cap only -
// every re-claim of the same ground levels the zone up by one, with no
// time-based gate of any kind, until it stops at the maximum of 15. This
// has no I/O and no geometry in it, mirroring computeZoneMerges/
// computeZoneSplit in the same module as a pure, mock-free function.
//
// Run: npx deno test supabase/functions/tests/claim_territory_level_up_cap_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeNextInfluenceLevel } from '../claim_territory/merge_geometry.ts';

Deno.test('a re-claim of the same ground levels the zone up by one', () => {
  assertEquals(computeNextInfluenceLevel(1), 2);
  assertEquals(computeNextInfluenceLevel(3), 4);
});

Deno.test('repeated re-claims keep leveling up on every single run, back to back', () => {
  let level = 1;
  for (let i = 0; i < 5; i++) {
    level = computeNextInfluenceLevel(level);
  }
  assertEquals(level, 6, 'five consecutive re-claims must produce five consecutive level-ups');
});

Deno.test('a zone one level below the cap levels up to exactly 15', () => {
  assertEquals(computeNextInfluenceLevel(14), 15);
});

Deno.test('a zone already at the level-15 cap stays at 15 on another claim', () => {
  assertEquals(computeNextInfluenceLevel(15), 15,
    'the cap must hold even when the input is already at the maximum - a claim on an already-maxed '
      + 'zone is never a wasted run, but it also never exceeds the ceiling');
});

Deno.test('repeated re-claims driven past the cap settle at 15 and never overshoot', () => {
  let level = 13;
  for (let i = 0; i < 10; i++) {
    level = computeNextInfluenceLevel(level);
  }
  assertEquals(level, 15, 'ten consecutive re-claims starting near the cap must settle at 15, not overshoot it');
});
