// supabase/functions/finalize_run/index.ts
// Awards +25 credits for a completed run, invokes earn_superpower for run_end event.
// Idempotent: if runs.finalized_at is set, returns { result: 'already_finalized' }.
//
// POST body: { run_id: string }
// Auth: Bearer <USER_JWT>

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { writeLedger }  from '../_shared/credit_ledger.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface Body { run_id: string }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const auth = req.headers.get('Authorization')
    if (!auth?.startsWith('Bearer ')) return json({ error: 'missing auth' }, 401)
    const jwt = auth.replace('Bearer ', '')

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt)
    if (authErr || !user) return json({ error: 'invalid token' }, 401)
    const playerId = user.id

    const { run_id } = (await req.json()) as Body
    if (!run_id) return json({ error: 'missing run_id' }, 400)

    const { data: run, error: rErr } = await supabase
      .from('runs')
      .select('id, player_id, finalized_at, distance_m')
      .eq('id', run_id)
      .single()
    if (rErr || !run) return json({ error: 'run not found' }, 404)
    if (run.player_id !== playerId) return json({ error: 'wrong player' }, 403)

    // Idempotency guard
    if (run.finalized_at) {
      return json({ result: 'already_finalized' })
    }

    // Credits per run from config
    const { data: cfgRow } = await supabase
      .from('app_config').select('value').eq('key', 'credits_per_run').single()
    const perRun = Number(cfgRow?.value ?? '25')

    const { newBalance } = await writeLedger(supabase, {
      playerId,
      delta:             perRun,
      reason:            'run',
      relatedEntityId:   run_id,
      relatedEntityType: 'run',
    })

    // Stamp finalized_at BEFORE calling earn_superpower (prevents double-finalize on retry)
    await supabase
      .from('runs')
      .update({ finalized_at: new Date().toISOString() })
      .eq('id', run_id)

    // Chain into earn_superpower for run_end
    const superpowerResp = await supabase.functions.invoke('earn_superpower', {
      body:    { event: 'run_end', run_id },
      headers: { Authorization: `Bearer ${jwt}` },
    })

    return json({
      credits_awarded:   perRun,
      new_balance:       newBalance,
      superpower_check:  superpowerResp.data,
    })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}
