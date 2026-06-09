import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function ok(body: unknown) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status: 200,
  });
}
function err(msg: string, status = 400) {
  return new Response(JSON.stringify({ error: msg }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  });
}

// Milestone config: day -> credits
const MILESTONE_CREDITS: Record<number, number> = {
  3: 100,
  7: 200,
  14: 500,
  21: 1000,
  30: 2000,
};

// Milestone superpowers (day -> power_type, duration seconds)
const MILESTONE_POWERS: Record<number, { type: string; duration_s: number } | null> = {
  3: { type: 'SHIELD', duration_s: 3600 },
  7: null,
  14: null,
  21: null,
  30: null,
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return err('Missing authorization', 401);

    const jwt = authHeader.replace('Bearer ', '');
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt);
    if (authErr || !user) return err('Invalid token', 401);
    const playerId = user.id;

    const body = await req.json();
    const { local_date, tz_offset_minutes = 0 } = body;

    if (!local_date) return err('Missing local_date');

    // Fetch player streaks row
    const { data: player, error: playerErr } = await supabase
      .from('player_streaks')
      .select('streak, longest_streak, freeze_tokens, freeze_refreshed_at, last_login_at, milestones_claimed')
      .eq('player_id', playerId)
      .maybeSingle();

    if (playerErr || !player) return err('player_streaks row not found for player', 404);

    const now = new Date();

    // Refresh freeze tokens if >30 days since last refresh
    let freezeTokens: number = player.freeze_tokens ?? 2;
    let freezeRefreshedAt: Date = player.freeze_refreshed_at ? new Date(player.freeze_refreshed_at) : new Date(now);
    const daysSinceRefresh = (now.getTime() - freezeRefreshedAt.getTime()) / (1000 * 60 * 60 * 24);
    if (daysSinceRefresh >= 30) {
      freezeTokens = 2;
      freezeRefreshedAt = now;
    }

    let currentStreak: number = player.streak ?? 0;
    const previousStreak = currentStreak;
    let longestStreak: number = player.longest_streak ?? 0;
    let lastLoginAt: Date | null = player.last_login_at ? new Date(player.last_login_at) : null;
    let streakEvent: string;

    // Compute the player's local calendar date for last login
    // Apply tz_offset_minutes to shift UTC times to local
    const offsetMs = (tz_offset_minutes as number) * 60 * 1000;

    let daysSinceLastLogin: number | null = null;
    if (lastLoginAt !== null) {
      // Get local date strings
      const lastLocalMs = lastLoginAt.getTime() + offsetMs;
      const lastLocalDate = new Date(lastLocalMs);
      const lastDateStr = `${lastLocalDate.getUTCFullYear()}-${String(lastLocalDate.getUTCMonth() + 1).padStart(2, '0')}-${String(lastLocalDate.getUTCDate()).padStart(2, '0')}`;

      // local_date is the client-provided today string
      const todayDate = new Date(`${local_date}T00:00:00Z`);
      const lastDate = new Date(`${lastDateStr}T00:00:00Z`);
      daysSinceLastLogin = Math.round((todayDate.getTime() - lastDate.getTime()) / (1000 * 60 * 60 * 24));
    }

    if (lastLoginAt === null) {
      // First ever login
      currentStreak = 1;
      streakEvent = 'first_login';
      lastLoginAt = now;
    } else if (daysSinceLastLogin === 0) {
      // Already logged in today — noop
      streakEvent = 'noop';
    } else if (daysSinceLastLogin === 1) {
      // Consecutive day
      currentStreak += 1;
      longestStreak = Math.max(longestStreak, currentStreak);
      lastLoginAt = now;
      streakEvent = 'incremented';
    } else if (daysSinceLastLogin === 2 && freezeTokens > 0) {
      // 1-day gap: use a freeze token
      freezeTokens -= 1;
      currentStreak += 1;
      longestStreak = Math.max(longestStreak, currentStreak);
      lastLoginAt = now;
      streakEvent = 'frozen';
    } else {
      // Streak broken
      currentStreak = 1;
      lastLoginAt = now;
      streakEvent = 'broken';
    }

    // Check milestones
    const milestonesClaimed: number[] = Array.isArray(player.milestones_claimed) ? player.milestones_claimed : [];
    let milestoneUnlocked: { day: number; credits: number; power: string | null; power_duration_s: number | null } | null = null;
    let checkInGranted = false;
    let newBalance: number | null = null;

    const milestoneDays = [3, 7, 14, 21, 30];
    for (const day of milestoneDays) {
      if (currentStreak === day && !milestonesClaimed.includes(day) && streakEvent !== 'noop') {
        milestonesClaimed.push(day);

        const credits = MILESTONE_CREDITS[day] ?? 0;
        const powerConfig = MILESTONE_POWERS[day] ?? null;

        // Award credits
        if (credits > 0) {
          await supabase.rpc('increment_credits', {
            p_player: playerId,
            p_amount: credits,
          });
          newBalance = credits; // caller can re-fetch for exact balance if needed
        }

        // Insert SHIELD superpower grant for day 3
        if (powerConfig !== null) {
          await supabase.from('superpower_grants').insert({
            id: crypto.randomUUID(),
            player_id: playerId,
            power_type: powerConfig.type,
            charges: 1,
            charges_used: 0,
            source: `streak_day_${day}`,
            expires_at: new Date(Date.now() + powerConfig.duration_s * 1000).toISOString(),
          });
          checkInGranted = true;
        }

        milestoneUnlocked = {
          day,
          credits,
          power: powerConfig?.type ?? null,
          power_duration_s: powerConfig?.duration_s ?? null,
        };

        // Only award one milestone per login
        break;
      }
    }

    // Persist updated player_streaks row
    const { error: updateErr } = await supabase
      .from('player_streaks')
      .update({
        streak: currentStreak,
        longest_streak: longestStreak,
        last_login_at: lastLoginAt ? lastLoginAt.toISOString() : null,
        freeze_tokens: freezeTokens,
        freeze_refreshed_at: freezeRefreshedAt.toISOString(),
        milestones_claimed: milestonesClaimed,
        updated_at: new Date().toISOString(),
      })
      .eq('player_id', playerId);

    if (updateErr) return err(updateErr.message, 500);

    return ok({
      streak: currentStreak,
      longest_streak: longestStreak,
      previous_streak: previousStreak,
      streak_event: streakEvent,
      milestone_unlocked: milestoneUnlocked,
      new_balance: newBalance,
      check_in_granted: checkInGranted,
    });

  } catch (e) {
    return err((e as Error).message, 500);
  }
});
