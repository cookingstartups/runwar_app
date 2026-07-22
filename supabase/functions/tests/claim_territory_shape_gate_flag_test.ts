// supabase/functions/tests/claim_territory_shape_gate_flag_test.ts
//
// The claim gate is being reduced to area-only, reversibly, on both the
// Flutter client and this server. Reversibility means the diagonal and
// compactness checks stay in the source, gated behind kEnforceShapeGates
// (default false), not deleted - see the doc comment on kEnforceShapeGates
// and evaluateCapturedRingGates in handler.ts.
//
// evaluateCapturedRingGates is a pure function (no Supabase client, no
// auth, no network) extracted from handleClaimTerritoryRequest specifically
// so it can be unit-tested directly against a ring, the same pattern
// claim_territory_merge_wiring_test.ts already uses for runSplitAndMerge.
//
// Run: ~/.deno/bin/deno test --allow-all --cached-only supabase/functions/tests/claim_territory_shape_gate_flag_test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { evaluateCapturedRingGates, kEnforceShapeGates } from '../claim_territory/handler.ts';

// A thin wedge: area ~1650 sqm (clears the 1500 sqm area floor), a
// bounding-box diagonal ~431 m (clears the 30 m diagonal floor), and a
// compactness of ~0.0089 (area / diagonal^2), far below the 0.15
// compactness floor. Same fixture and derivation as _thinWedgePath in
// test/auto_claim_test.dart (the Flutter client's equivalent test) - ring
// coordinates are [lng, lat] pairs here, matching this file's convention.
const THIN_WEDGE_RING: number[][] = [
  [33.0, 34.7],
  [33.00004292345667, 34.7],
  [33.00004292345667, 34.70389904107111],
  [33.0, 34.70389904107111],
  [33.00000218528903, 34.70000271394971],
];

// Below the 1500 sqm area floor regardless of shape - a tiny ~1.4 sqm simple
// square, same scale as _buildTinyCrossPath in auto_claim_test.dart.
const SUB_AREA_FLOOR_RING: number[][] = [
  [33.0, 34.7],
  [33.0000125, 34.7],
  [33.0000125, 34.7000125],
  [33.0, 34.7000125],
];

Deno.test('the shipped default is OFF', () => {
  assertEquals(kEnforceShapeGates, false,
    'if this fails, the constant itself changed - update this test deliberately, do not just make it pass');
});

Deno.test('default (shape gates OFF): a thin wedge that fails compactness is ACCEPTED', () => {
  const result = evaluateCapturedRingGates(THIN_WEDGE_RING);
  assertEquals(result.passed, true,
    'with shape gates off, only the area floor gates a claim - the thin wedge must pass');
});

Deno.test('shape gates ON: the same thin wedge is REJECTED (too_short)', () => {
  const result = evaluateCapturedRingGates(THIN_WEDGE_RING, true);
  assertEquals(result.passed, false,
    'flipping the flag back on must restore exactly today\'s enforcement');
  assertEquals(result.reason, 'too_short');
  // area and diagonal both clear their own floors; compactness is what
  // actually fails, proving this rejects for the right reason once shape
  // gates are re-enabled, not because area or diagonal secretly regressed.
  assertEquals((result.areaSqm ?? 0) > 1500, true);
  assertEquals((result.diagonalM ?? 0) > 30, true);
  assertEquals((result.compactness ?? 1) < 0.15, true);
});

Deno.test('area floor still bites regardless of the flag - OFF', () => {
  const result = evaluateCapturedRingGates(SUB_AREA_FLOOR_RING);
  assertEquals(result.passed, false);
  assertEquals(result.reason, 'too_short');
  assertEquals(result.areaSqm < 1500, true);
});

Deno.test('area floor still bites regardless of the flag - ON', () => {
  const result = evaluateCapturedRingGates(SUB_AREA_FLOOR_RING, true);
  assertEquals(result.passed, false);
  assertEquals(result.reason, 'too_short');
  assertEquals(result.areaSqm < 1500, true);
});
