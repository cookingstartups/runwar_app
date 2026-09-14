// supabase/functions/tests/claim_territory_speed_teleport_test.ts
//
// R2: claim_territory's genuine speed/teleport check. evaluateTrackTiming is
// a new pure function (no Supabase client, no auth, no network), mirroring
// evaluateCapturedRingGates's own extraction pattern - see
// claim_territory_shape_gate_flag_test.ts for the sibling precedent this
// file follows. Ring coordinates are [lng, lat, alt, ts_ms] tuples (or
// legacy [lng, lat] 2-tuples), matching the codebase's existing [lng, lat]
// GeoJSON convention.
//
// Run: ~/.deno/bin/deno test --allow-all supabase/functions/tests/claim_territory_speed_teleport_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { evaluateTrackTiming } from '../claim_territory/handler.ts';

// Metres-to-degrees conversion, same convention as
// claim_territory_merge_wiring_test.ts's metresRing helper.
const LAT0 = 39.470000; // Valencia, matching the other claim_territory test files
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

// Builds a [lng, lat, alt, ts_ms] vertex at (eastOffsetM, northOffsetM) from
// a fixed origin, with a given timestamp and altitude.
function metresPoint(eastOffsetM: number, northOffsetM: number, tsMs: number, altM: number | null = 10): number[] {
  const lng = 33.0 + eastOffsetM / LNG_M;
  const lat = LAT0 + northOffsetM / LAT_M;
  return [lng, lat, altM as number, tsMs];
}

Deno.test('a 4-tuple ring where every hop implies well under 12 m/s with strictly increasing ts passes', () => {
  // Three hops of 70m each over 10000ms = 7 m/s, safely under the 12 m/s
  // sustained-speed threshold and nowhere near the teleport distance/time.
  const ring = [
    metresPoint(0, 0, 0),
    metresPoint(70, 0, 10000),
    metresPoint(140, 0, 20000),
  ];
  const result = evaluateTrackTiming(ring);
  assertEquals(result.passed, true,
    'a 7 m/s sustained pace must clear the 12 m/s threshold - if this fails, the threshold or its comparison direction changed');
});

Deno.test('a 4-tuple ring with one hop at 15 m/s (above threshold, below teleport distance/time) fails as speed_violation', () => {
  // 150m in 10000ms = 15 m/s. Distance (150m) is well under the 500m
  // teleport floor, so only the sustained-speed branch can catch this - a
  // reverted/deleted speed check would return passed:true here, and the
  // reason assertion would never even be reached.
  const ring = [
    metresPoint(0, 0, 0),
    metresPoint(150, 0, 10000),
  ];
  const result = evaluateTrackTiming(ring);
  assertEquals(result.passed, false,
    '15 m/s must exceed the 12 m/s sustained-speed threshold and fail the gate');
  assertEquals(result.reason, 'speed_violation',
    'this hop is short-distance/moderate-speed - only the sustained-speed branch, not teleport, can produce this rejection');
});

Deno.test('a 4-tuple ring with a 600 m hop in 2 s fails specifically as teleport, not speed_violation', () => {
  // 600m in 2000ms implies ~300 m/s - both the speed threshold AND the
  // teleport threshold (>500m in <5s) would independently catch this, but
  // the teleport branch must run first and produce reason:'teleport'. This
  // is the assertion that specifically dies if the teleport branch is
  // removed while the generic speed check remains: the fixture would still
  // fail, but with reason:'speed_violation' instead, and this exact-match
  // assertion on 'teleport' would throw.
  const ring = [
    metresPoint(0, 0, 0),
    metresPoint(600, 0, 2000),
  ];
  const result = evaluateTrackTiming(ring);
  assertEquals(result.passed, false);
  assertEquals(result.reason, 'teleport',
    'a 600m/2s hop must be caught by the teleport branch specifically, not merely fail as a generic speed violation');
});

Deno.test('a non-increasing ts_ms pair fails as teleport even over a short distance that a naive clamp would pass', () => {
  // Only 5m apart, with ts_ms[1] == ts_ms[0] (non-increasing). A naive
  // implementation that clamps elapsed time to a 1ms floor and divides
  // would compute a tiny, clearly-passing speed (5m / 0.001s would actually
  // be huge - but a naive Math.max(dt, 1)-style clamp historically produces
  // an unbounded or masked value depending on how it's written; this
  // fixture is deliberately SHORT distance so that if the explicit
  // non-increasing guard is missing and some other naive clamp masks the
  // anomaly into a small elapsed-time denominator instead of flagging it
  // outright, the resulting speed could still slip under 12 m/s and pass).
  // The explicit guard in the spec treats ts2 <= ts1 as an unconditional
  // teleport, regardless of distance.
  const ring = [
    metresPoint(0, 0, 5000),
    metresPoint(5, 0, 5000), // identical timestamp - non-increasing
  ];
  const result = evaluateTrackTiming(ring);
  assertEquals(result.passed, false,
    'a non-increasing ts_ms pair must never be treated as a legitimate (even if tiny) elapsed time');
  assertEquals(result.reason, 'teleport',
    'non-increasing timestamps must be classified as teleport per the explicit guard, not silently pass as a low-speed hop');
});

Deno.test('a legacy 2-tuple ring is never speed/teleport-checked regardless of implied speed', () => {
  // Legacy [lng, lat] pairs carry no timestamp at all. Even an absurd
  // apparent jump must pass, because the check must be skipped entirely
  // for this shape (compatibility decision, design.md section 3).
  const ring = [
    [33.0, 39.47],
    [34.0, 40.47], // enormous jump - would fail if timestamps existed
  ];
  const result = evaluateTrackTiming(ring);
  assertEquals(result.passed, true,
    'a 2-tuple (legacy, no-timestamp) ring must always skip the check and pass - if this fails, the function started requiring 4 elements unconditionally, breaking legacy client compatibility');
});

Deno.test('a non-finite ts_ms on one vertex fails as teleport rather than silently passing as NaN', () => {
  // NaN arithmetic in JS: `NaN <= x` and `x <= NaN` are always false, and
  // `NaN > 12` is false, so a naive implementation with no Number.isFinite
  // guard would let this ring pass with passed:true. The spec's guard
  // treats a non-finite ts value the same as a non-increasing pair.
  const ring: number[][] = [
    metresPoint(0, 0, 0),
    [33.001, 39.471, 10, NaN],
  ];
  const result = evaluateTrackTiming(ring);
  assertEquals(result.passed, false,
    'a non-finite ts_ms must not silently produce a passing NaN comparison');
  assertEquals(result.reason, 'teleport',
    'a non-finite ts_ms must be treated the same as a non-increasing timestamp pair (teleport), per the Number.isFinite guard');
});
