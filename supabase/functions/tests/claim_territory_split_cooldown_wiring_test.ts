// supabase/functions/tests/claim_territory_split_cooldown_wiring_test.ts
//
// RED phase - source-inspection checks against index.ts's call-site wiring
// for the level-gated merge (AC-5, AC-13), the repeat-run cooldown (AC-8),
// the reversible split on re-run (AC-7), and the no-retroactive-fuse
// invariant (AC-9). These target orchestration/DB-write logic embedded in
// index.ts's request handler - the row selection, the RPC call shape, the
// unconditional last_active_at write - which genuinely cannot be exercised
// without a live Supabase instance (mocking the client here would exceed
// the project's >5-mocks-escalate rule for a handler touching select /
// update / rpc calls across three or more tables), so source inspection is
// kept for those specific pieces only.
//
// The decision MATH behind the split and the cooldown gate (does this
// count as a partial overlap or a full containment, is the remainder above
// the sliver floor, does the cooldown block the level increment, does the
// clamp apply) has no I/O in it and is covered behaviourally instead, in
// claim_territory_split_geometry_test.ts and
// claim_territory_level_up_cooldown_test.ts - those replace what used to be
// symbol-presence checks here for that half of the behaviour.
//
// Run: npx deno test supabase/functions/tests/claim_territory_split_cooldown_wiring_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC_PATH = new URL('../claim_territory/index.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

// ---------------------------------------------------------------------------
// AC-5 / AC-13 - level equality feeds into the merge candidate construction
// ---------------------------------------------------------------------------

Deno.test('the merge candidate ZoneInput carries influenceLevel through to computeZoneMerges', () => {
  const src = readSrc();
  assert(src.includes('influenceLevel:'),
    'index.ts must pass influenceLevel into each constructed ZoneInput so the level-equality '
      + 'gate inside computeZoneMerges has data to gate on');
});

Deno.test(
  'R2 invariant (unaffected by the level gate): the merge candidate query still scopes to owner_id, city and status owned',
  () => {
    const src = readSrc();
    assert(src.includes("eq('owner_id'"), "The merge query must still filter .eq('owner_id', playerId)");
    assert(src.includes("eq('city'"), "The merge query must still filter .eq('city', city)");
    assert(src.includes("eq('status', 'owned')"),
      "A disputed same-owner zone must still be excluded from the merge candidate set regardless "
        + 'of the new level-equality gate - the status filter and the level gate are independent');
  },
);

// ---------------------------------------------------------------------------
// AC-4 / AC-11 regression: MAX/SUM aggregation is unchanged once a group is
// already guaranteed equal-level by the new gate.
// ---------------------------------------------------------------------------

Deno.test(
  'unification still takes the MAX influence_level across an (now-guaranteed-equal-level) group',
  () => {
    const src = readSrc();
    assert(src.includes('survivorInfluenceLevel') && src.includes('p_influence_level: survivorInfluenceLevel'),
      'The apply_zone_merge RPC call must still be given influence_level aggregated as the MAX');
    const reduceIdx = src.indexOf('const survivorInfluenceLevel');
    assert(reduceIdx >= 0);
    assert(src.slice(reduceIdx, reduceIdx + 200).includes('Math.max'),
      'influence_level aggregation must remain a MAX, unchanged by the new level-equality gate');
  },
);

// ---------------------------------------------------------------------------
// AC-8 - repeat-run damping / level-up cooldown
// ---------------------------------------------------------------------------

Deno.test('a level-up cooldown constant, backed by a Deno env var, is defined', () => {
  const src = readSrc();
  assert(src.includes('kLevelUpCooldownMs'),
    'index.ts must define a kLevelUpCooldownMs constant for the repeat-run damping gate (AC-8)');
  assert(src.includes("Deno.env.get('LEVEL_UP_COOLDOWN_MS')"),
    'The cooldown constant must be backed by a Deno environment variable, not a client-supplied '
      + 'flag (a request-controlled cooldown value would be a trivial exploit)');
});

// The cooldown DECISION itself (active vs elapsed, the level-15 clamp) is
// covered behaviourally by claim_territory_level_up_cooldown_test.ts
// against computeLevelUpOutcome - a symbol-presence check on
// 'cooldownActive' added nothing beyond confirming a variable name exists,
// so it is dropped here in favour of that real coverage.

Deno.test('last_active_at still refreshes unconditionally regardless of cooldown state', () => {
  const src = readSrc();
  assert(src.includes('survivorLastActiveAt') && src.includes('p_last_active_at: survivorLastActiveAt'),
    'last_active_at must still be written on every claim, independent of whether the cooldown '
      + 'suppressed the level-up itself (AC-8: a maxed-out re-run is never a wasted run)');
});

// ---------------------------------------------------------------------------
// AC-7 - reversible split on re-run of part of a fused area
// ---------------------------------------------------------------------------

Deno.test('a dedicated sliver-tolerance constant for split remainders is defined, distinct from the merge threshold', () => {
  const src = readSrc();
  assert(src.includes('kMinSplitFragmentAreaSqm'),
    'index.ts must define kMinSplitFragmentAreaSqm (AC-7) as its own constant, not a reuse of the '
      + '25m merge/proximity threshold - area and distance are different quantities');
});

// The split classification and remainder-area math (partial overlap vs
// full containment, sliver-tolerance discard) are covered behaviourally by
// claim_territory_split_geometry_test.ts against computeZoneSplit. What
// remains genuinely wiring-only is that the write actually goes out over
// the dedicated RPC, which cannot be confirmed without a live Supabase
// instance.
Deno.test('the split write goes through a dedicated apply_zone_split RPC', () => {
  const src = readSrc();
  assert(src.includes("supabase.rpc('apply_zone_split'"),
    'The split write must go through a dedicated apply_zone_split RPC (one UPDATE, no absorbed-row '
      + 'DELETE), mirroring the atomic-write discipline already used by apply_zone_merge');
});

// ---------------------------------------------------------------------------
// AC-9 - no retroactive/periodic fuse
// ---------------------------------------------------------------------------

// Already true of today's source (one call site); expected to remain true
// after this feature ships - a regression lock against a future periodic
// job being added, not a new-behaviour probe.
Deno.test('computeZoneMerges is only ever invoked from inside the claim request handler', () => {
  const src = readSrc();
  const occurrences = src.split('computeZoneMerges(').length - 1;
  assert(occurrences === 1,
    'computeZoneMerges must be called exactly once, from the claim-event merge block - a second '
      + 'call site anywhere in this file would indicate a periodic/retroactive fuse path, which '
      + 'AC-9 explicitly forbids');
});
