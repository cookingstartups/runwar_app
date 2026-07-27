import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (p: unknown, s = 200) =>
  new Response(JSON.stringify(p), { headers: { ...cors, 'Content-Type': 'application/json' }, status: s })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const auth = req.headers.get('Authorization') ?? ''
    if (!auth.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401)

    const svc = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const { data: { user }, error: authErr } = await svc.auth.getUser(auth.replace('Bearer ', ''))
    if (authErr || !user) return json({ error: 'unauthorized' }, 401)

    const { challenge_id, outcome } = await req.json() as { challenge_id: string; outcome: 'resolve' | 'fail' }
    if (!challenge_id || !outcome) return json({ error: 'challenge_id and outcome are required' }, 400)

    const { data: ch } = await svc
      .from('challenges')
      .select('id, pending_payload')
      .eq('id', challenge_id)
      .eq('player_id', user.id)
      .eq('status', 'pending')
      .maybeSingle()
    if (!ch) return json({ error: 'challenge not found' }, 404)

    if (outcome === 'resolve') {
      await svc.from('challenges').update({ status: 'resolved', resolved_at: new Date().toISOString() }).eq('id', challenge_id)
      const payload = ch.pending_payload as { fn?: string; args?: Record<string, unknown> } | null
      if (payload?.fn === 'claim_territory') await svc.rpc('claim_territory', payload.args ?? {})
    } else {
      await svc.from('challenges').update({ status: 'failed', resolved_at: new Date().toISOString() }).eq('id', challenge_id)
      const { data: cfg } = await svc.from('app_config').select('value').eq('key', 'cheat_penalty_reputation').maybeSingle()
      const penalty = cfg ? parseInt(cfg.value as string, 10) : 10
      await svc.rpc('decrement_reputation', { p_player_id: user.id, p_amount: penalty })
    }

    return json({ ok: true })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
