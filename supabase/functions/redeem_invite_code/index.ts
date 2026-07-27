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
    // ── Auth: JWT user ────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization') ?? ''
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: { user }, error: authErr } = await supabase.auth.getUser()
    if (authErr || !user) return json({ error: 'unauthorized' }, 401)
    const player_id = user.id

    // ── Parse body ────────────────────────────────────────────────────────────
    const { code } = await req.json() as { code: string }
    if (!code) return json({ error: 'code is required' }, 400)

    // ── Atomic RPC ────────────────────────────────────────────────────────────
    const { data, error: rpcErr } = await supabase
      .rpc('redeem_invite_code_atomic', { p_code: code, p_player_id: player_id })
    if (rpcErr) return json({ error: rpcErr.message }, 500)

    const result = data as { success: boolean; error?: string }
    if (!result.success) return json({ error: result.error }, 409)

    return json({ redeemed: true })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
