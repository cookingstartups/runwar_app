// supabase/functions/tests/claim_territory_shield_void_test.ts
//
// Orchestration-layer proofs that the rival-zone decide/apply loop itself,
// not just the pure carve function, honours an active shield: a fully
// enclosed shield leaves the shielded row untouched and writes no dispute
// fields, a partial overlap is subtracted rather than opening a dispute, a
// claim voided by the post-carve floor performs zero mutating database
// calls, an expired shield falls back to today's ordinary behaviour, and
// the result shape carries structured shield-blocked feedback.
//
// Driven against runShieldAwareClaimDecideApply, the extracted decide/apply
// loop, through a recording fake database client - the same injected-fake
// discipline runSplitAndMerge and claim_territory_split_wiring_test.ts
// already established.
//
// Run: /home/algif/.deno/bin/deno test --allow-all supabase/functions/tests/claim_territory_shield_void_test.ts

import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  runShieldAwareClaimDecideApply,
  type RivalZoneRow,
  type ShieldAwareClaimDbClient,
} from '../claim_territory/handler.ts';

const LAT0 = 39.470000; // Valencia, matching the other claim_territory test files
const LAT_M = 110540;
const LNG_M = 111320 * Math.cos((LAT0 * Math.PI) / 180);

function mLng(meters: number): number {
  return meters / LNG_M;
}
function mLat(meters: number): number {
  return meters / LAT_M;
}

function rect(lng0: number, lat0: number, widthM: number, heightM: number): number[][] {
  const dLng = mLng(widthM);
  const dLat = mLat(heightM);
  const a = [lng0, lat0];
  const b = [lng0 + dLng, lat0];
  const c = [lng0 + dLng, lat0 + dLat];
  const d = [lng0, lat0 + dLat];
  return [a, b, c, d, a];
}

const ATTACKER_ID = 'attacker-player';
const DEFENDER_ID = 'defender-player';
const FUTURE_EXPIRY = new Date(Date.now() + 60 * 60 * 1000).toISOString();
const PAST_EXPIRY = new Date(Date.now() - 5 * 60 * 1000).toISOString();

interface RecordedUpdate {
  zoneId: string;
  patch: Record<string, unknown>;
}

class RecordingDbClient implements ShieldAwareClaimDbClient {
  updates: RecordedUpdate[] = [];

  from(_table: 'zones') {
    return {
      update: (patch: Record<string, unknown>) => ({
        eq: (_column: 'id', value: string) => {
          this.updates.push({ zoneId: value, patch });
          return Promise.resolve({ error: null });
        },
      }),
    };
  }
}

// ---------------------------------------------------------------------------
// A rival claim fully enclosing a shielded zone leaves that row untouched
// and writes NO dispute fields.
// ---------------------------------------------------------------------------

Deno.test('a claim ring fully enclosing an active-shielded rival zone must leave that zone row untouched', async () => {
  const claimRing = rect(33.000000, LAT0, 100, 100);
  const shieldRing = rect(33.000000 + mLng(40), LAT0 + mLat(40), 20, 20);

  const zones: RivalZoneRow[] = [
    {
      id: 'shielded-zone',
      owner_id: DEFENDER_ID,
      status: 'owned',
      geom_json: JSON.stringify({ type: 'Polygon', coordinates: [shieldRing] }),
      shield_active: true,
      shield_expires_at: FUTURE_EXPIRY,
    },
  ];

  const db = new RecordingDbClient();
  const result = await runShieldAwareClaimDecideApply({
    db,
    zones,
    newRing: claimRing,
    playerId: ATTACKER_ID,
    nowMs: Date.now(),
    capturedAreaSqm: 10000,
  });

  assertFalse(
    db.updates.some((u) => u.zoneId === 'shielded-zone'),
    'a fully-enclosed active-shielded rival zone must receive NO database write at all (no conquest, ' +
      'no dispute fields) - the row is untouched, its territory is carved out of the attacker instead. ' +
      'Reverting the fix makes this fail: today\'s decide/apply loop conquers any zone whose own points ' +
      'fall inside the new claim ring, with no shield check.',
  );
  assert(
    result.conqueredId !== 'shielded-zone',
    'shielded-zone must never be reported as conquered',
  );
});

// ---------------------------------------------------------------------------
// A partial overlap is subtracted; NO dispute is opened.
// ---------------------------------------------------------------------------

Deno.test('a claim ring partially overlapping an active-shielded rival zone must open NO dispute', async () => {
  // A large shielded zone; the claim only straddles one of its edges, with
  // two of the claim's own corners inside the shield and none of the
  // shield's own corners inside the claim - today's code takes the
  // anyNewPointInside branch here (dispute), never conquest.
  const shieldRing = rect(33.000000, LAT0, 300, 300);
  const claimRing = rect(33.000000 + mLng(290), LAT0 + mLat(100), 20, 40);

  const zones: RivalZoneRow[] = [
    {
      id: 'shielded-zone',
      owner_id: DEFENDER_ID,
      status: 'owned',
      geom_json: JSON.stringify({ type: 'Polygon', coordinates: [shieldRing] }),
      shield_active: true,
      shield_expires_at: FUTURE_EXPIRY,
    },
  ];

  const db = new RecordingDbClient();
  const result = await runShieldAwareClaimDecideApply({
    db,
    zones,
    newRing: claimRing,
    playerId: ATTACKER_ID,
    nowMs: Date.now(),
    capturedAreaSqm: 800,
  });

  assertFalse(
    db.updates.some((u) => u.zoneId === 'shielded-zone' && 'dispute_at' in u.patch),
    'a partial overlap against an active-shielded rival zone must never write dispute_at/contested_by_id ' +
      '- the overlap must be subtracted from the attacker\'s claim instead. Reverting the fix makes this ' +
      "fail: today's code opens an ordinary dispute for exactly this partial-overlap shape.",
  );
  assert(
    result.disputedId !== 'shielded-zone',
    'shielded-zone must never be reported as disputed',
  );
});

// ---------------------------------------------------------------------------
// A claim voided by falling under the minimum area performs ZERO mutating
// database calls.
// ---------------------------------------------------------------------------

Deno.test('a claim voided by the post-carve area floor performs zero mutating database calls', async () => {
  // The claim is almost entirely covered by a single active shield -
  // whatever the real carve leaves must fall under the floor and void
  // before any write happens.
  const shieldRing = rect(33.000000, LAT0, 300, 300);
  const claimRing = rect(33.000000 + mLng(10), LAT0 + mLat(10), 20, 20);

  const zones: RivalZoneRow[] = [
    {
      id: 'shielded-zone',
      owner_id: DEFENDER_ID,
      status: 'owned',
      geom_json: JSON.stringify({ type: 'Polygon', coordinates: [shieldRing] }),
      shield_active: true,
      shield_expires_at: FUTURE_EXPIRY,
    },
  ];

  const db = new RecordingDbClient();
  await runShieldAwareClaimDecideApply({
    db,
    zones,
    newRing: claimRing,
    playerId: ATTACKER_ID,
    nowMs: Date.now(),
    capturedAreaSqm: 400,
  });

  assertEquals(
    db.updates.length,
    0,
    `a claim voided by the post-carve area floor must perform exactly 0 mutating database calls, got ` +
      `${db.updates.length}. Reverting the fix makes this fail: today's decide/apply loop always writes ` +
      'a conquest or dispute update for an overlapping rival zone, with no floor short-circuit at all.',
  );
});

// Non-vacuity proof for the assertion above: this sibling scenario has NO
// rival zones at all, so the recorder must show a genuinely empty call list
// - proving `db.updates.length === 0` is not trivially true regardless of
// what the code under test does, but actually reflects "nothing was
// recorded". The voided-claim test above, by contrast, is currently RED
// (a mutating call IS recorded), which is the flipped-to-failing half of
// the same proof.
Deno.test('non-vacuity control: zero rival zones genuinely produces zero recorded mutating calls', async () => {
  const db = new RecordingDbClient();
  await runShieldAwareClaimDecideApply({
    db,
    zones: [],
    newRing: rect(33.000000, LAT0, 20, 20),
    playerId: ATTACKER_ID,
    nowMs: Date.now(),
    capturedAreaSqm: 400,
  });
  assertEquals(db.updates.length, 0, 'the recorder must report a real empty call list when nothing calls it');
});

// ---------------------------------------------------------------------------
// An EXPIRED shield triggers no subtraction and falls back to today's
// ordinary behaviour, in the SAME scenario as an active shield that DOES
// block - so a fix that (wrongly) blocks on expiry too, or a null
// implementation that never blocks at all, both show up as a failure here.
// ---------------------------------------------------------------------------

Deno.test('an active shield blocks conquest while an expired shield on a different zone does not', async () => {
  const claimRing = rect(33.000000, LAT0, 300, 300);
  const activeShieldRing = rect(33.000000 + mLng(20), LAT0 + mLat(20), 20, 20);
  const expiredShieldRing = rect(33.000000 + mLng(100), LAT0 + mLat(20), 20, 20);

  const zones: RivalZoneRow[] = [
    {
      id: 'active-shielded-zone',
      owner_id: DEFENDER_ID,
      status: 'owned',
      geom_json: JSON.stringify({ type: 'Polygon', coordinates: [activeShieldRing] }),
      shield_active: true,
      shield_expires_at: FUTURE_EXPIRY,
    },
    {
      id: 'expired-shielded-zone',
      owner_id: DEFENDER_ID,
      status: 'owned',
      geom_json: JSON.stringify({ type: 'Polygon', coordinates: [expiredShieldRing] }),
      shield_active: true,
      shield_expires_at: PAST_EXPIRY,
    },
  ];

  const db = new RecordingDbClient();
  await runShieldAwareClaimDecideApply({
    db,
    zones,
    newRing: claimRing,
    playerId: ATTACKER_ID,
    nowMs: Date.now(),
    capturedAreaSqm: 90000,
  });

  assertFalse(
    db.updates.some((u) => u.zoneId === 'active-shielded-zone'),
    'the zone with an active, unexpired shield must receive no database write at all',
  );
  assert(
    db.updates.some((u) => u.zoneId === 'expired-shielded-zone'),
    'the zone whose shield already expired must still be conquered/disputed under ordinary rules - an ' +
      'expired shield must fall back to today\'s ordinary behaviour, not be treated as still protecting. ' +
      "Reverting a fix that mistakenly ignores expiry entirely (blocks both) makes this fail.",
  );
});

// ---------------------------------------------------------------------------
// The result carries structured shield-blocked feedback: affected zone ids
// and the resulting claimed area.
// ---------------------------------------------------------------------------

Deno.test('a voided claim reports a structured shield_blocked outcome naming the blocking zone id(s)', async () => {
  const shieldRing = rect(33.000000, LAT0, 300, 300);
  const claimRing = rect(33.000000 + mLng(10), LAT0 + mLat(10), 20, 20);

  const zones: RivalZoneRow[] = [
    {
      id: 'shielded-zone',
      owner_id: DEFENDER_ID,
      status: 'owned',
      geom_json: JSON.stringify({ type: 'Polygon', coordinates: [shieldRing] }),
      shield_active: true,
      shield_expires_at: FUTURE_EXPIRY,
    },
  ];

  const db = new RecordingDbClient();
  const result = await runShieldAwareClaimDecideApply({
    db,
    zones,
    newRing: claimRing,
    playerId: ATTACKER_ID,
    nowMs: Date.now(),
    capturedAreaSqm: 400,
  });

  assertEquals(
    result.outcome,
    'shield_blocked',
    `a claim voided by the shield floor must report outcome 'shield_blocked', got '${result.outcome}'. ` +
      "Reverting the fix makes this fail: today's decide/apply loop has no shield_blocked outcome at all.",
  );
  assert(result.shieldBlocked, 'shield_blocked payload must be present when outcome is shield_blocked');
  assert(
    result.shieldBlocked!.zone_ids.includes('shielded-zone'),
    'shield_blocked.zone_ids must name the zone(s) whose shield caused the void',
  );
  assert(
    typeof result.shieldBlocked!.claimed_area_m2 === 'number',
    'shield_blocked.claimed_area_m2 must convey the resulting claimed area as a number',
  );
});
