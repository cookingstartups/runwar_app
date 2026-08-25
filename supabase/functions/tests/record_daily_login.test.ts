// supabase/functions/tests/record_daily_login.test.ts
//
// Tests for the record_daily_login Mission-1 gate: a player who has never
// completed Mission 1 (player_streaks.streak_started_at IS NULL) must not
// accrue streak progress or receive milestone rewards, even if their
// player_streaks row exists. A player who HAS completed Mission 1 must
// still progress and receive milestone rewards normally, including the
// day-21 capstone milestone.
//
// Run with: deno test --allow-net --allow-env record_daily_login.test.ts

import {
  assertEquals,
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

function localDateNDaysAgo(n: number): string {
  const d = new Date(Date.now() - n * 24 * 60 * 60 * 1000);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

async function callRecordDailyLogin(jwt: string, local_date: string) {
  const res = await fetch(fnUrl("record_daily_login"), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ local_date, tz_offset_minutes: 0 }),
  });
  return { status: res.status, body: await res.json() };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

// GIVEN a player with a player_streaks row but streak_started_at IS NULL
// (i.e. Mission 1 never completed)
// WHEN record_daily_login is called
// THEN the streak is not incremented and no milestone is unlocked.
//
// Reverting the fix (removing the streak_started_at guard in
// record_daily_login/index.ts) makes this test fail: currentStreak would be
// incremented to 1 via the 'first_login' branch and the function would
// return streak_event: 'first_login' instead of 'mission1_not_started'.
Deno.test("record_daily_login rejects streak progress when Mission 1 not completed", async () => {
  const email = `tx_rdl_nomission_${Date.now()}@test.invalid`;
  const user = await createTestPlayer(email);
  try {
    const sb = svcClient();

    // player_streaks row exists but streak_started_at is NULL (Mission 1
    // never completed) - this mirrors the real state for a fresh player.
    await sb.from("player_streaks").upsert({
      user_id: user.id,
      streak: 0,
      longest_streak: 0,
      freeze_tokens: 2,
      last_login_at: null,
      milestones_claimed: [],
      streak_started_at: null,
    });

    const jwt = await playerJwt(email);
    const { status, body } = await callRecordDailyLogin(jwt, localDateNDaysAgo(0));

    assertEquals(status, 200);
    assertEquals(body.streak_event, "mission1_not_started");
    assertEquals(body.milestone_unlocked, null);
    assertEquals(body.check_in_granted, false);

    // Confirm no streak progress was persisted.
    const { data: row } = await sb
      .from("player_streaks")
      .select("streak, last_login_at, milestones_claimed")
      .eq("user_id", user.id)
      .single();
    assertEquals((row as { streak: number }).streak, 0,
      "streak must not increment before Mission 1 is completed");
    assertEquals((row as { last_login_at: string | null }).last_login_at, null,
      "last_login_at must not be stamped before Mission 1 is completed");
  } finally {
    await deleteTestPlayer(user.id);
  }
});

// GIVEN a player who HAS completed Mission 1 (streak_started_at set) and is
// on day 20 of their streak, with no milestones claimed yet
// WHEN record_daily_login is called for day 21
// THEN the streak increments to 21 and the day-21 milestone (1000 credits)
// is unlocked.
Deno.test("record_daily_login still pays day-21 milestone for a player who completed Mission 1", async () => {
  const email = `tx_rdl_day21_${Date.now()}@test.invalid`;
  const user = await createTestPlayer(email);
  try {
    const sb = svcClient();

    await sb.from("players").upsert({ id: user.id, credits: 0 });

    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    await sb.from("player_streaks").upsert({
      user_id: user.id,
      streak: 20,
      longest_streak: 20,
      freeze_tokens: 2,
      last_login_at: yesterday,
      milestones_claimed: [3, 7, 14],
      streak_started_at: new Date(Date.now() - 20 * 24 * 60 * 60 * 1000).toISOString(),
    });

    const jwt = await playerJwt(email);
    const { status, body } = await callRecordDailyLogin(jwt, localDateNDaysAgo(0));

    assertEquals(status, 200);
    assertEquals(body.streak, 21);
    assertEquals(body.streak_event, "incremented");
    assertEquals(body.milestone_unlocked?.day, 21);
    assertEquals(body.milestone_unlocked?.credits, 1000);

    const { data: row } = await sb
      .from("player_streaks")
      .select("streak, milestones_claimed")
      .eq("user_id", user.id)
      .single();
    assertEquals((row as { streak: number }).streak, 21);
    const claimed = (row as { milestones_claimed: number[] }).milestones_claimed;
    assertEquals(claimed.includes(21), true);
  } finally {
    await deleteTestPlayer(user.id);
  }
});
