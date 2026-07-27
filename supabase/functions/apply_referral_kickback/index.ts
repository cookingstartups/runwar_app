import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (p: unknown, s = 200) => new Response(JSON.stringify(p), {
  headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: s,
})

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const auth = req.headers.get('Authorization') ?? ''
    if (auth !== `Bearer ${serviceKey}`) return json({ error: 'unauthorized' }, 401)

    const body = await req.json() as {
      player_id: string; earned_delta: number; source_reason: string; source_id?: string
    }

    // HARD invariant - block recursive kickback chains
    if (body.source_reason === 'referral_kickback') {
      return json({ error: 'recursion_blocked' })
    }

    const svcSb = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey)

    // 1. Resolve inviter
    const { data: referral, error: refErr } = await svcSb
      .from('referrals').select('inviter_id').eq('invitee_id', body.player_id).maybeSingle()
    if (refErr) return json({ error: refErr.message }, 500)
    if (!referral) return json({ skipped: 'no_referral' })
    const { inviter_id } = referral as { inviter_id: string }

    // 2. Compute kickback
    const kickback = Math.floor(body.earned_delta * 0.20)
    if (kickback < 1) return json({ skipped: 'too_small' })

    // 3. Credit inviter
    const { error: creditErr } = await svcSb.rpc('apply_credit_delta', {
      p_player_id:         inviter_id,
      p_delta:             kickback,
      p_reason:            'referral_kickback',
      p_related_entity_id: body.source_id ?? null,
    })
    if (creditErr) return json({ error: 'Failed to apply kickback credits: ' + creditErr.message }, 500)

    // 4. Increment lifetime kickback counter
    const { data: row } = await svcSb
      .from('player_economy').select('total_kickback_earned').eq('player_id', inviter_id).single()
    await svcSb.from('player_economy')
      .update({
        total_kickback_earned: ((row?.total_kickback_earned as number) ?? 0) + kickback,
        updated_at: new Date().toISOString(),
      })
      .eq('player_id', inviter_id)

    return json({ kickback_applied: kickback })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
