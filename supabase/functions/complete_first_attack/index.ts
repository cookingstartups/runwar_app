// supabase/functions/complete_first_attack/index.ts
//
// POST - Auth: Bearer <user JWT>
// Body: { zone_id: string }
//
// Stamps first_attack_completed_at on the player if not already set.
// No credit delta applied (first attack reward is implicit in zone conquest).
//
// Idempotent: re-call returns { ok: true, already_completed: true }.
//
// Returns:
//   { ok: true, first_attack_completed_at: string, already_completed: boolean }
//
// Errors: 400 (missing zone_id) | 401 (missing/invalid auth) | 500

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
    // ── Auth ──────────────────────────────────────────────────────────────────
    const auth = req.headers.get('Authorization')
    if (!auth?.startsWith('Bearer ')) return json({ error: 'Missing authorization' }, 401)
    const jwt = auth.replace('Bearer ', '')

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt)
    if (authErr || !user) return json({ error: 'Invalid token' }, 401)
    const playerId = user.id

    // ── Parse body ────────────────────────────────────────────────────────────
    const body = await req.json().catch(() => ({})) as { zone_id?: string }
    if (!body.zone_id) return json({ error: 'zone_id is required' }, 400)

    // ── Idempotency check ─────────────────────────────────────────────────────
    const { data: row, error: fetchErr } = await supabase
      .from('player_progress')
      .select('first_attack_completed_at')
      .eq('user_id', playerId)
      .single()

    if (fetchErr || !row) return json({ error: 'player_progress row not found' }, 500)

    if (row.first_attack_completed_at != null) {
      return json({
        ok: true,
        first_attack_completed_at: row.first_attack_completed_at,
        already_completed: true,
      })
    }

    // ── Stamp timestamp ───────────────────────────────────────────────────────
    const now = new Date().toISOString()

    const { error: updateErr } = await supabase
      .from('player_progress')
      .update({
        first_attack_completed_at: now,
        updated_at: now,
      })
      .eq('user_id', playerId)
      .is('first_attack_completed_at', null) // optimistic-lock

    if (updateErr) return json({ error: 'Failed to stamp attack completion' }, 500)

    return json({
      ok: true,
      first_attack_completed_at: now,
      already_completed: false,
    })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
