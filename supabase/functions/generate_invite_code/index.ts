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
    const { player_id, label } = await req.json() as { player_id: string; label?: string }
    if (!player_id) return json({ error: 'player_id is required' }, 400)

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey)

    // ── Read invite_cap from app_config ───────────────────────────────────────
    const { data: cfgRow } = await supabase
      .from('app_config')
      .select('value')
      .eq('key', 'invite_cap')
      .maybeSingle()
    const cap = cfgRow ? parseInt(cfgRow.value as string, 10) : 10

    // ── Count existing codes for this player ──────────────────────────────────
    const { count } = await supabase
      .from('invitation_codes')
      .select('id', { count: 'exact', head: true })
      .eq('created_by', player_id)
    if ((count ?? 0) >= cap) return json({ error: 'invite_cap_reached' }, 403)

    // ── Generate code and insert ──────────────────────────────────────────────
    const code = crypto.randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase()

    const { error: insertErr } = await supabase
      .from('invitation_codes')
      .insert({
        code,
        created_by:      player_id,
        max_redemptions: 1,
        redeemed_count:  0,
        reserved_label:  label ?? null,
      })
    if (insertErr) return json({ error: 'failed to create code' }, 500)

    return json({ code })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
