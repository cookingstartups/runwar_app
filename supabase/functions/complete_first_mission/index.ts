// supabase/functions/complete_first_mission/index.ts
//
// POST - Auth: Bearer <user JWT>
// Body: {}  (user_id derived from JWT)
//
// Delegates to the atomic Postgres function complete_first_mission_tx which
// stamps first_mission_completed_at + streak_started_at and awards 50 credits
// in a single transaction. Idempotent: returns already_completed:true without
// side effects if the mission was already stamped.
//
// Returns:
//   { ok: true, first_mission_completed_at, credits_after, streak_started_at,
//     already_completed: boolean }
//
// Errors: 401 (missing/invalid auth) | 500 (rpc / db failure)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    // Auth
    const auth = req.headers.get('Authorization')
    if (!auth?.startsWith('Bearer ')) return json({ error: 'Missing authorization' }, 401)
    const jwt = auth.replace('Bearer ', '')

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt)
    if (authErr || !user) return json({ error: 'Invalid token' }, 401)
    const userId = user.id

    // Atomic RPC - stamp + credit in one transaction.
    // NOTE: migration 0050_player_id_to_user_id_unification.sql renamed this
    // RPC's parameter from p_player_id to p_user_id. The param name below
    // must stay in sync with complete_first_mission_tx's live signature.
    const { data, error } = await supabase.rpc('complete_first_mission_tx', {
      p_user_id: userId,
    })

    if (error) return json({ error: error.message }, 500)

    const row = Array.isArray(data) ? data[0] : data
    if (!row) return json({ error: 'No result from complete_first_mission_tx' }, 500)

    return json({
      ok: true,
      already_completed: row.already_completed ?? false,
      first_mission_completed_at: row.first_mission_completed_at ?? null,
      streak_started_at: row.streak_started_at ?? null,
      credits_after: row.credits_after ?? null,
    })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
