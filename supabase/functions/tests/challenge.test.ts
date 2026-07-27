// supabase/functions/tests/challenge.test.ts
//
// Tests for complete_challenge and the decrement_reputation RPC
// (reputation floors at 0).
//
// Run with: deno test --allow-net --allow-env challenge.test.ts
//
// These tests will FAIL until complete_challenge and decrement_reputation
// are deployed.

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Helpers ───────────────────────────────────────────────────────────────────

function svcClient() {
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, key);
}

function fnUrl(fn: string) {
  return `${Deno.env.get("SUPABASE_URL")}/functions/v1/${fn}`;
}

async function playerJwt(email: string): Promise<string> {
  const sb = svcClient();
  const { data, error } = await sb.auth.signInWithPassword({
    email,
    password: "TestPass123!",
  });
  if (error) throw new Error(`signIn failed: ${error.message}`);
  return data.session!.access_token;
}

async function createTestPlayer(email: string) {
  const sb = svcClient();
  const { data, error } = await sb.auth.admin.createUser({
    email,
    password: "TestPass123!",
    email_confirm: true,
  });
  if (error) throw new Error(`createTestPlayer failed: ${error.message}`);
  return data.user!;
}

async function deleteTestPlayer(id: string) {
  await svcClient().auth.admin.deleteUser(id);
}

/** Valid motion proof that should pass verifyMotion (variance > 0.05 on both axes, correct pattern, duration >= target). */
function validProof() {
  return {
    samples: [
      { rx: 0.5, ry: 0.5, rz: 0.0, t: 0 },
      { rx: -0.5, ry: -0.5, rz: 0.0, t: 1000 },
      { rx: 0.5, ry: 0.5, rz: 0.0, t: 2000 },
      { rx: -0.5, ry: -0.5, rz: 0.0, t: 3000 },
    ],
    duration_s: 9,
    pattern_detected: "figure_8",
  };
}

/** Flat proof (zero variance) - should fail verifyMotion. */
function flatProof() {
  return {
    samples: [
      { rx: 0.0, ry: 0.0, rz: 0.0, t: 0 },
      { rx: 0.0, ry: 0.0, rz: 0.0, t: 1000 },
    ],
    duration_s: 9,
    pattern_detected: "figure_8",
  };
}

async function insertOpenChallenge(playerId: string): Promise<string> {
  const sb = svcClient();
  const { data, error } = await sb
    .from("challenges")
    .insert({
      player_id: playerId,
      challenge_type: "motion_capture",
      status: "open",
      motion_target: { pattern: "figure_8", tolerance_deg: 30, duration_s: 8 },
    })
    .select("id")
    .single();
  if (error) throw new Error(`insertOpenChallenge failed: ${error.message}`);
  return (data as { id: string }).id;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

// GIVEN an open challenge for a player
// WHEN complete_challenge is called with a valid motion proof
// THEN challenge status becomes 'resolved'
Deno.test("complete_challenge marks status=resolved on valid proof", async () => {
  const email = `tx_ch_resolve_${Date.now()}@test.invalid`;
  const user = await createTestPlayer(email);
  try {
    const challengeId = await insertOpenChallenge(user.id);
    const jwt = await playerJwt(email);
    const res = await fetch(fnUrl("complete_challenge"), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        challenge_id: challengeId,
        motion_capture_proof: validProof(),
      }),
    });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.status, "resolved");

    // Confirm row updated in DB
    const sb = svcClient();
    const { data: row } = await sb
      .from("challenges")
      .select("status")
      .eq("id", challengeId)
      .single();
    assertEquals((row as { status: string }).status, "resolved");
  } finally {
    await deleteTestPlayer(user.id);
  }
});

// GIVEN a player with reputation = 5 (below typical debit of 10)
// WHEN complete_challenge is called with invalid (flat) proof
// THEN reputation is debited but never goes below 0 (floors at 0)
Deno.test("complete_challenge reputation floors at 0 when debit would go negative", async () => {
  const email = `tx_ch_rep_${Date.now()}@test.invalid`;
  const user = await createTestPlayer(email);
  try {
    const sb = svcClient();

    // Set player reputation to 5 (below the 10-point debit)
    await sb.from("players").upsert({ id: user.id, reputation: 5 });

    const challengeId = await insertOpenChallenge(user.id);
    const jwt = await playerJwt(email);
    const res = await fetch(fnUrl("complete_challenge"), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        challenge_id: challengeId,
        motion_capture_proof: flatProof(),
      }),
    });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.status, "failed");

    // Confirm reputation is 0, not -5
    const { data: player } = await sb
      .from("players")
      .select("reputation")
      .eq("id", user.id)
      .single();
    assertEquals((player as { reputation: number }).reputation, 0,
      "reputation must floor at 0, not go negative");
  } finally {
    await deleteTestPlayer(user.id);
  }
});
