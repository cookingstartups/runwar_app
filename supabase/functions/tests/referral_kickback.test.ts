// supabase/functions/tests/referral_kickback.test.ts
//
// Tests for apply_referral_kickback.
//
// Run with: deno test --allow-net --allow-env referral_kickback.test.ts
//
// These tests will FAIL until the edge function is deployed.

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

function svcHeaders() {
  return {
    Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
    "Content-Type": "application/json",
  };
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

// ── Tests ─────────────────────────────────────────────────────────────────────

// GIVEN apply_referral_kickback is called with source_reason='referral_kickback'
// WHEN the request reaches the non-recursion guard
// THEN it returns recursion_blocked immediately and makes no DB writes
Deno.test("earn with source_reason='referral_kickback' returns recursion_blocked - no DB writes", async () => {
  const inviteeEmail = `tx_rkb_recursive_${Date.now()}@test.invalid`;
  const invitee = await createTestPlayer(inviteeEmail);
  try {
    const fakeTxId = crypto.randomUUID();
    const res = await fetch(fnUrl("apply_referral_kickback"), {
      method: "POST",
      headers: svcHeaders(),
      body: JSON.stringify({
        invitee_id: invitee.id,
        earned_amount: 100,
        source_tx_id: fakeTxId,
        source_reason: "referral_kickback",
      }),
    });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.error, "recursion_blocked");

    // No kickback credit_transaction row must exist with this source_tx_id
    const sb = svcClient();
    const { count } = await sb
      .from("credit_transactions")
      .select("*", { count: "exact", head: true })
      .eq("source_id", fakeTxId)
      .eq("reason", "referral_kickback");
    assertEquals(count, 0, "no credit_transactions row must be written on recursion guard");
  } finally {
    await deleteTestPlayer(invitee.id);
  }
});

// GIVEN invitee player has a referral row pointing to an inviter
// WHEN apply_referral_kickback is called with source_reason='claim' and earned_amount=100
// THEN inviter receives a kickback of 20 credits (20% per app_config) via credit_transactions
Deno.test("normal earn triggers kickback of 20% to inviter when referral row exists", async () => {
  const inviterEmail = `tx_rkb_inviter_${Date.now()}@test.invalid`;
  const inviteeEmail = `tx_rkb_invitee_${Date.now()}@test.invalid`;
  const inviter = await createTestPlayer(inviterEmail);
  const invitee = await createTestPlayer(inviteeEmail);
  try {
    const sb = svcClient();

    // Create code and referral row for test setup
    const testCode = `TRKB${Date.now().toString().slice(-4)}`;
    await sb.from("invitation_codes").insert({
      code: testCode,
      created_by: inviter.id,
      max_redemptions: 1,
    });
    await sb.from("referrals").insert({
      invitee_id: invitee.id,
      inviter_id: inviter.id,
      via_code: testCode,
    });

    const sourceTxId = crypto.randomUUID();
    const res = await fetch(fnUrl("apply_referral_kickback"), {
      method: "POST",
      headers: svcHeaders(),
      body: JSON.stringify({
        invitee_id: invitee.id,
        earned_amount: 100,
        source_tx_id: sourceTxId,
        source_reason: "claim",
      }),
    });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.kickback_amount, 20, "kickback must be 20% of earned_amount=100");
    assertEquals(body.inviter_id, inviter.id);

    // Confirm credit_transactions row for inviter with reason referral_kickback
    const { data: txRows } = await sb
      .from("credit_transactions")
      .select("delta, reason")
      .eq("player_id", inviter.id)
      .eq("source_id", sourceTxId)
      .eq("reason", "referral_kickback");
    assertExists(txRows, "credit_transactions row must exist");
    assertEquals(txRows!.length, 1);
    assertEquals(txRows![0].delta, 20);
  } finally {
    await deleteTestPlayer(inviter.id);
    await deleteTestPlayer(invitee.id);
  }
});
