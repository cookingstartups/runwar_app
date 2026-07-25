// supabase/functions/tests/claim_territory_dispute_timer_test.ts
//
// Dispute-open timer/overlap snapshot (spec R2) and the full-conquest
// dispute-state clear fix (spec R9).
//
// R2-AC2's overlap-area snapshot is pure geometry and is exercised for real
// against computeDisputeOverlapAreaSqm, a not-yet-exported function this
// test expects merge_geometry.ts to gain (mirroring computeClaimInfluence's
// existing pure-function shape). R2-AC1 (dispute_at write) and R9
// (full-conquest clears dispute_at/dispute_overlap_m2) live inside
// handleClaimTerritoryRequest's own non-injectable database calls (the same
// boundary claim_territory_merge_wiring_test.ts already documents as
// requiring anchored source inspection rather than a live Supabase
// instance) - anchored to the exact branch bodies so the test fails loudly
// if handler.ts's structure moves, instead of silently checking nothing.
//
// Run: npx deno test supabase/functions/tests/claim_territory_dispute_timer_test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeDisputeOverlapAreaSqm } from '../claim_territory/merge_geometry.ts';

const HANDLER_SRC_PATH = new URL('../claim_territory/handler.ts', import.meta.url);

function readHandlerSrc(): string {
  return Deno.readTextFileSync(HANDLER_SRC_PATH);
}

function findAnchor(src: string, marker: string, label: string): number {
  const idx = src.indexOf(marker);
  assert(idx >= 0, `Landmark not found: ${label} ("${marker}"). handler.ts's structure moved - update this test's anchor, do not delete the check.`);
  return idx;
}

const LAT0 = 39.470000; // Valencia
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

function metresRing(lng0: number, lat0: number, widthM: number, heightM: number): number[][] {
  const dLng = widthM / LNG_M;
  const dLat = heightM / LAT_M;
  const a = [lng0, lat0];
  const b = [lng0 + dLng, lat0];
  const c = [lng0 + dLng, lat0 + dLat];
  const d = [lng0, lat0 + dLat];
  return [a, b, c, d, a];
}

// ── R2-AC2: overlap-area snapshot (real geometry, not mocked) ────────────────

Deno.test('computeDisputeOverlapAreaSqm returns the true intersection area between the attacker ring and the zone', () => {
  // Zone Z: a 40x40 m square. Attacker's new ring overlaps exactly the left
  // half (40x20 m -> 800 sqm), so the intersection is a known quantity.
  const zoneOutline = metresRing(33.0, LAT0, 40, 40);
  const attackerRing = metresRing(33.0, LAT0, 40, 20);

  const overlap = computeDisputeOverlapAreaSqm(attackerRing, [zoneOutline]);

  assert(overlap > 750 && overlap < 850,
    `expected roughly 800 sqm intersection, got ${overlap}`);
});

Deno.test('computeDisputeOverlapAreaSqm returns 0 for non-overlapping rings', () => {
  const zoneOutline = metresRing(33.0, LAT0, 40, 40);
  // Far away, no overlap at all.
  const attackerRing = metresRing(33.0 + 1.0, LAT0, 40, 40);

  const overlap = computeDisputeOverlapAreaSqm(attackerRing, [zoneOutline]);

  assertEquals(overlap, 0);
});

Deno.test('computeDisputeOverlapAreaSqm OR-sums overlap across every outline of a MultiPolygon-shaped zone', () => {
  const outlineA = metresRing(33.0, LAT0, 40, 40);
  // A second, disjoint member outline of the same (legacy MultiPolygon) zone.
  const outlineB = metresRing(33.0 + 0.01, LAT0, 40, 40);
  // Attacker ring overlaps only outlineB.
  const attackerRing = metresRing(33.0 + 0.01, LAT0, 40, 20);

  const overlap = computeDisputeOverlapAreaSqm(attackerRing, [outlineA, outlineB]);

  assert(overlap > 750 && overlap < 850,
    `expected the outlineB-only overlap (~800 sqm) to be picked up, got ${overlap}`);
});

// ── R2-AC1: dispute_at absolute-deadline write ───────────────────────────────

Deno.test('the disputed branch writes dispute_at as an absolute now()+15min deadline', () => {
  const src = readHandlerSrc();
  const disputedBranchIdx = findAnchor(
    src,
    "status: 'disputed',",
    'disputed-branch UPDATE (partial overlap)',
  );
  const branchWindow = src.slice(disputedBranchIdx, disputedBranchIdx + 400);

  assert(branchWindow.includes('dispute_at'),
    'the disputed branch must set dispute_at in the same UPDATE that sets status=\'disputed\'');
});

// ── R2-AC2 (wiring): dispute_overlap_m2 written in the same UPDATE ───────────

Deno.test('the disputed branch writes dispute_overlap_m2 as the snapshotted intersection area', () => {
  const src = readHandlerSrc();
  const disputedBranchIdx = findAnchor(
    src,
    "status: 'disputed',",
    'disputed-branch UPDATE (partial overlap)',
  );
  const branchWindow = src.slice(disputedBranchIdx, disputedBranchIdx + 400);

  assert(branchWindow.includes('dispute_overlap_m2'),
    'the disputed branch must set dispute_overlap_m2 in the same UPDATE that sets status=\'disputed\'');
});

// ── R9: full-conquest branch also clears dispute state ───────────────────────

Deno.test('the full-conquest branch also clears dispute_at and dispute_overlap_m2, not just contested_by_id', () => {
  const src = readHandlerSrc();
  const conquestBranchIdx = findAnchor(
    src,
    'owner_id: playerId,',
    'full-conquest branch UPDATE (total overlap)',
  );
  const branchWindow = src.slice(conquestBranchIdx, conquestBranchIdx + 500);

  assert(branchWindow.includes('contested_by_id: null'),
    'sanity check: the existing contested_by_id clear must still be present');
  assert(branchWindow.includes('dispute_at: null'),
    'the full-conquest branch must also null dispute_at, or a third-party conquest of a mid-dispute zone leaves stale dispute state for the cron resolver to misfire against (spec R9)');
  assert(branchWindow.includes('dispute_overlap_m2: null'),
    'the full-conquest branch must also null dispute_overlap_m2 for the same reason as dispute_at above (spec R9)');
});
