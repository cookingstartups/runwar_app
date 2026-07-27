// supabase/functions/tests/invite_code.test.ts
//
// Tests for generate_invite_code and the redeem_invite_code_atomic RPC.
//
// Run with: deno test --allow-net --allow-env invite_code.test.ts
//
// These tests call the Supabase project RPC and edge functions;
// they will FAIL until the migration and edge functions are deployed.

import {
  assertEquals,
  assertExists,
  assertNotEquals,
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

async function userJwt(email: string, password = "TestPass123!"): Promise<string> {
  const sb = svcClient();
  const { data, error } = await sb.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`signIn failed: ${error.message}`);
  return data.session!.access_token;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

// GIVEN a valid player JWT
// WHEN generate_invite_code is called with default options
// THEN returns a code with max_redemptions matching the requested value
Deno.test("generate_invite_code creates code with correct max_redemptions", async () => {
  const email = `tx_ic_gen_${Date.now()}@test.invalid`;
  const user = await createTestPlayer(email);
  try {
    const jwt = await userJwt(email);
    const res = await fetch(fnUrl("generate_invite_code"), {
      method: "POST",
      headers: { ...svcHeaders(), Authorization: `Bearer ${jwt}` },
      body: JSON.stringify({ max_redemptions: 3 }),
    });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertExists(body.code, "response must have a code field");
    assertEquals(body.max_redemptions, 3);
    assertEquals(body.redeemed_count, 0);
  } finally {
    await deleteTestPlayer(user.id);
  }
});

// GIVEN the same player redeems the same code twice
// WHEN redeem_invite_code_atomic is called the second time with identical args
// THEN it returns already_redeemed and no duplicate row is created
Deno.test("redeem_invite_code_atomic is idempotent - same player same code returns already_redeemed", async () => {
  const ownerEmail = `tx_ic_owner_${Date.now()}@test.invalid`;
  const redeemerEmail = `tx_ic_redeemer_${Date.now()}@test.invalid`;
  const owner = await createTestPlayer(ownerEmail);
  const redeemer = await createTestPlayer(redeemerEmail);
  try {
    const sb = svcClient();
    // Insert a code directly via service client (for test setup only - RLS bypassed by service role)
    const testCode = `TDEM${Date.now().toString().slice(-4)}`;
    await sb.from("invitation_codes").insert({
      code: testCode,
      created_by: owner.id,
      max_redemptions: 5,
    });

    // First redemption via RPC - must succeed
    const { error: err1 } = await sb.rpc("redeem_invite_code_atomic", {
      p_code: testCode,
      p_user: redeemer.id,
    });
    assertEquals(err1, null, "first redemption must succeed");

    // Second redemption via RPC - must return already_redeemed
    const { error: err2 } = await sb.rpc("redeem_invite_code_atomic", {
      p_code: testCode,
      p_user: redeemer.id,
    });
    assertExists(err2, "second redemption must error");
    assertEquals(
      (err2 as { message: string }).message.includes("already_redeemed"),
      true,
      "error must be already_redeemed",
    );

    // Confirm only one redemption row was created
    const { count } = await sb
      .from("code_redemptions")
      .select("*", { count: "exact", head: true })
      .eq("code", testCode)
      .eq("redeemed_by", redeemer.id);
    assertEquals(count, 1, "only one code_redemptions row must exist");
  } finally {
    await deleteTestPlayer(owner.id);
    await deleteTestPlayer(redeemer.id);
  }
});

// GIVEN a code with max_redemptions=1 that has already been fully redeemed
// WHEN redeem_invite_code_atomic is called with a new player
// THEN it returns exhausted
Deno.test("redeem_invite_code_atomic returns exhausted when code is at max_redemptions", async () => {
  const ownerEmail = `tx_ic_exh_owner_${Date.now()}@test.invalid`;
  const redeemerAEmail = `tx_ic_exh_a_${Date.now()}@test.invalid`;
  const redeemerBEmail = `tx_ic_exh_b_${Date.now()}@test.invalid`;
  const owner = await createTestPlayer(ownerEmail);
  const redeemerA = await createTestPlayer(redeemerAEmail);
  const redeemerB = await createTestPlayer(redeemerBEmail);
  try {
    const sb = svcClient();
    const testCode = `TEXH${Date.now().toString().slice(-4)}`;
    await sb.from("invitation_codes").insert({
      code: testCode,
      created_by: owner.id,
      max_redemptions: 1,
    });

    // First redemption - exhausts the code
    const { error: err1 } = await sb.rpc("redeem_invite_code_atomic", {
      p_code: testCode,
      p_user: redeemerA.id,
    });
    assertEquals(err1, null, "first redemption must succeed");

    // Second redemption - different player, code is now exhausted
    const { error: err2 } = await sb.rpc("redeem_invite_code_atomic", {
      p_code: testCode,
      p_user: redeemerB.id,
    });
    assertExists(err2, "second redemption must return an error");
    assertEquals(
      (err2 as { message: string }).message.includes("exhausted"),
      true,
      "error must be exhausted",
    );
  } finally {
    await deleteTestPlayer(owner.id);
    await deleteTestPlayer(redeemerA.id);
    await deleteTestPlayer(redeemerB.id);
  }
});
