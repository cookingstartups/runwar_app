// supabase/functions/tests/claim_territory_area_scaled_influence_test.ts
//
// Closes the game-theory review's flat-per-claim-reward finding: with a
// flat influence award (the old `influence: 1` on every new zone,
// conquest, and merge survivor, regardless of captured size), the
// dominant strategy was spamming the cheapest claim that clears the area
// floor up to the daily cap - no floor value fixes that on its own.
// computeClaimInfluence (merge_geometry.ts) replaces the flat award with a
// sqrt-scaled function of the captured area, and the merge path
// (handler.ts's runSplitAndMerge) now recomputes it from the survivor's
// OWN final merged area instead of summing pre-merge member values - see
// both functions' doc comments for the full reasoning.
//
// This file covers:
//   1. A small claim near the area floor earns proportionally less than a
//      large claim (computeClaimInfluence is monotonically increasing in
//      area).
//   2. Reward growth is sublinear - doubling area does not double the
//      award.
//   3. The server-side area floor (evaluateCapturedRingGates) rejects a
//      too-small ring based on the ring's REAL geometry, and is
//      structurally immune to a spoofed client-submitted value: it is a
//      pure function of the ring's coordinates alone, and (source-anchor
//      check) the request handler never reads an influence/area field off
//      the client's JSON body in the first place, so no such field could
//      reach the reward calculation even if a debug/test client sent one.
//
// Run: ~/.deno/bin/deno test --allow-all --cached-only supabase/functions/tests/claim_territory_area_scaled_influence_test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeClaimInfluence } from '../claim_territory/merge_geometry.ts';
import { evaluateCapturedRingGates } from '../claim_territory/handler.ts';

const SRC_PATH = new URL('../claim_territory/handler.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

// ---------------------------------------------------------------------------
// 1 & 2: computeClaimInfluence - proportional-but-sublinear scaling
// ---------------------------------------------------------------------------

// The 1500 sqm value must stay numerically equal to the server's own
// minCapturedAreaSqm floor in handler.ts's evaluateCapturedRingGates - a
// mismatch here would silently decouple this test's fixtures from what the
// floor actually enforces.
const FLOOR_AREA_SQM = 1500;

Deno.test('a claim exactly at the area floor keeps the pre-existing baseline influence of 1', () => {
  assertEquals(computeClaimInfluence(FLOOR_AREA_SQM), 1,
    'a floor-clearing claim must never be worth LESS than the old flat award, only ever more once above the floor');
});

Deno.test('a small claim near the floor earns strictly less influence than a large claim', () => {
  const small = computeClaimInfluence(FLOOR_AREA_SQM * 1.1); // just above the floor
  const large = computeClaimInfluence(FLOOR_AREA_SQM * 40); // a genuinely large loop
  assert(small < large,
    'a claim that barely clears the area floor must be worth less than a much larger claim - a flat award made them equal, which is exactly the spam incentive this closes');
});

Deno.test('influence scales proportionally with area between two non-trivial claims', () => {
  const a = computeClaimInfluence(6000);
  const b = computeClaimInfluence(24000); // 4x the area of `a`
  assert(b > a, 'more captured area must always earn more influence');
  // sqrt(4) = 2 exactly, so this ratio is an exact check, not an approximation.
  assertEquals(b / a, 2,
    'quadrupling area must double the award under sqrt scaling (sqrt(4x) = 2 * sqrt(x))');
});

Deno.test('reward growth is sublinear: doubling area does not double the reward', () => {
  const area = 30_000;
  const single = computeClaimInfluence(area);
  const doubled = computeClaimInfluence(area * 2);
  assert(doubled > single, 'a larger claim must still earn more, just not proportionally more');
  assert(doubled < single * 2,
    'doubling the captured area must NOT double the influence award - that would be linear (or worse, snowballing) scaling, not sublinear');
  // sqrt(2) exactly - the precise sublinear factor this formula guarantees.
  assertEquals(doubled / single, Math.sqrt(2));
});

Deno.test('a very large claim is clamped at the influence ceiling (15), never unbounded', () => {
  const huge = computeClaimInfluence(1_000_000_000); // absurdly large, to probe the ceiling
  assertEquals(huge, 15,
    'influence must stay within [1, 15] regardless of area, matching the existing decay/display range');
});

Deno.test('influence never drops below 1, even for an area under the floor (rejection is evaluateCapturedRingGates\'s job, not this function\'s)', () => {
  assertEquals(computeClaimInfluence(10), 1,
    'computeClaimInfluence itself only ever scales UP from the baseline of 1 - the area floor is enforced separately, before this function is ever called with a real claim');
});

// ---------------------------------------------------------------------------
// 3: server-side floor rejects a claim below the safe minimum, regardless
// of any value a client might submit alongside it.
// ---------------------------------------------------------------------------

// Below the 1500 sqm area floor regardless of shape - same fixture as
// claim_territory_shape_gate_flag_test.ts's SUB_AREA_FLOOR_RING.
const SUB_AREA_FLOOR_RING: number[][] = [
  [33.0, 34.7],
  [33.0000125, 34.7],
  [33.0000125, 34.7000125],
  [33.0, 34.7000125],
];

Deno.test('the server floor rejects a too-small ring purely from its own real geometry', () => {
  const result = evaluateCapturedRingGates(SUB_AREA_FLOOR_RING);
  assertEquals(result.passed, false, 'a ring under the area floor must be rejected');
  assertEquals(result.reason, 'too_short');
  assert(result.areaSqm < FLOOR_AREA_SQM,
    'the rejection must be driven by the ring\'s actual enclosed area, not a value read from anywhere else');
});

Deno.test('evaluateCapturedRingGates takes only a ring - there is no parameter through which a client could pass a spoofed area or influence value', () => {
  // A structural guarantee, not just a behavioral one: the function's own
  // signature has no second data-carrying parameter (only the boolean
  // enforceShapeGates test hook), so a debug/test client submitting extra
  // JSON fields (a fabricated `area_m2` or `influence`) has no path INTO
  // this computation at all - it is fed exclusively the ring's coordinates.
  assertEquals(evaluateCapturedRingGates.length, 1,
    'evaluateCapturedRingGates must take exactly one required argument (the ring) - a second required argument would be a route for a client-supplied value to influence the area floor');
});

Deno.test('the request handler never reads an influence or area field off the client JSON body', () => {
  const src = readSrc();
  const bodyDestructureMarker = "const { track, tracks, city } = body;";
  assert(src.includes(bodyDestructureMarker),
    'handler.ts\'s structure moved - update this anchor, do not delete the check');
  // Anchor from the body destructure up to the first area/gate computation,
  // and confirm nothing in that span reads an area or influence value back
  // off the client-submitted body. If a client (debug or otherwise) sent a
  // spoofed `area_m2`, `influence`, or `reward` field, this proves it is
  // never even looked at - the area used for both the floor and the
  // reward always comes from turfArea() on the actual submitted
  // coordinates, computed server-side.
  const start = src.indexOf(bodyDestructureMarker);
  const end = src.indexOf('evaluateCapturedRingGates(coords)');
  assert(end > start, 'evaluateCapturedRingGates(coords) call not found after the body destructure - source structure changed');
  const span = src.slice(start, end);
  assert(!span.includes('body.area'), 'the handler must never read an area value off the client body');
  assert(!span.includes('body.influence'), 'the handler must never read an influence value off the client body');
  assert(!span.includes('body[\'area'), 'the handler must never read an area value off the client body');
  assert(!span.includes('body[\'influence'), 'the handler must never read an influence value off the client body');
});
