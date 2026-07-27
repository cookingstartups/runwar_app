import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    // ── Auth: service-role only ───────────────────────────────────────────────
    const auth = req.headers.get('Authorization') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    if (auth !== `Bearer ${serviceKey}`) return json({ error: 'unauthorized' }, 401)

    // ── Parse body ────────────────────────────────────────────────────────────
    const { player_id } = await req.json() as { player_id: string }
    if (!player_id) return json({ error: 'player_id is required' }, 400)

    const svcSb = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey)

    // ── Step 1: Look up inviter ───────────────────────────────────────────────
    const { data: referral } = await svcSb
      .from('referrals')
      .select('inviter_id')
      .eq('invitee_id', player_id)
      .maybeSingle()

    if (!referral?.inviter_id) return json({ propagated: false })

    const inviter_id = referral.inviter_id

    // ── Step 3: Read penalty from app_config ──────────────────────────────────
    const { data: cfgRow } = await svcSb
      .from('app_config')
      .select('value')
      .eq('key', 'cheat_penalty_reputation')
      .maybeSingle()
    const penalty = cfgRow ? parseInt(cfgRow.value as string, 10) : 10

    // ── Step 4: Apply penalty to inviter ─────────────────────────────────────
    const { error: rpcErr } = await svcSb.rpc('decrement_reputation', {
      p_player_id: inviter_id,
      p_amount:    penalty,
    })
    if (rpcErr) return json({ error: 'failed to apply penalty' }, 500)

    // ── Step 5: Return result ─────────────────────────────────────────────────
    return json({ propagated: true, inviter_id, penalty_applied: penalty })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
