// supabase/functions/spawn_drops/index.ts
// Manual trigger only - NO pg_cron scheduled.
//
// POST body: { city: string, batch_size?: number, dry_run?: boolean }
// Auth: Bearer <SERVICE_ROLE_JWT>

import { createClient }  from 'https://esm.sh/@supabase/supabase-js@2'
import { loadCityBounds } from '../_shared/city_bounds.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
}

interface Body { city: string; batch_size?: number; dry_run?: boolean }

type DropType = 'credits_cache' | 'influence_crystal' | 'power_core'

// Weights: 50 % credits_cache / 30 % influence_crystal / 20 % power_core
const DROP_WEIGHTS: Array<[DropType, number]> = [
  ['credits_cache',     0.50],
  ['influence_crystal', 0.30],
  ['power_core',        0.20],
]

function weightedPick(): DropType {
  const r = Math.random()
  let cum = 0
  for (const [t, w] of DROP_WEIGHTS) { cum += w; if (r < cum) return t }
  return 'credits_cache'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const body = (await req.json()) as Body
    if (!body.city) return json({ error: 'missing city' }, 400)

    const auth = req.headers.get('Authorization') ?? ''
    if (!auth.startsWith('Bearer ')) return json({ error: 'missing auth' }, 401)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const bounds = await loadCityBounds(supabase, body.city)

    const cfg = await loadCfg(supabase, [
      'drop_max_active_per_city',
      'drop_ttl_minutes',
      'drop_spawn_batch_size',
      'credits_per_drop_cache',
    ])
    const cap         = +cfg.drop_max_active_per_city
    const ttlMin      = +cfg.drop_ttl_minutes
    const batchTarget = body.batch_size ?? +cfg.drop_spawn_batch_size
    const cashValue   = +cfg.credits_per_drop_cache

    const { count } = await supabase
      .from('drops')
      .select('id', { count: 'exact', head: true })
      .eq('city', body.city)
      .eq('status', 'active')
    const active    = count ?? 0
    const remaining = Math.max(0, cap - active)
    const target    = Math.min(batchTarget, remaining)

    const batchId   = crypto.randomUUID()
    const spawned: Array<{ id: string; lat: number; lng: number; drop_type: DropType }> = []
    let skipped     = 0
    const expiresAt = new Date(Date.now() + ttlMin * 60_000).toISOString()

    for (let i = 0; i < target; i++) {
      let lat = 0, lng = 0, ok = false
      for (let attempt = 0; attempt < 10; attempt++) {
        lat = bounds.south + Math.random() * (bounds.north - bounds.south)
        lng = bounds.west  + Math.random() * (bounds.east  - bounds.west)
        const { data: denied } = await supabase
          .rpc('is_point_denied', { p_city: body.city, p_lat: lat, p_lng: lng })
        if (denied === false) { ok = true; break }
      }
      if (!ok) { skipped++; continue }

      const dropType = weightedPick()
      const value =
        dropType === 'credits_cache'    ? cashValue :
        dropType === 'influence_crystal'? 1 :
        1   // power_core: 1 charge

      if (body.dry_run) {
        spawned.push({ id: 'dryrun', lat, lng, drop_type: dropType })
        continue
      }

      const { data: inserted, error: insErr } = await supabase
        .from('drops')
        .insert({
          city: body.city, lat, lng, drop_type: dropType, value,
          expires_at: expiresAt, spawn_batch_id: batchId, status: 'active',
        })
        .select('id')
        .single()
      if (insErr) { skipped++; continue }
      spawned.push({ id: inserted.id as string, lat, lng, drop_type: dropType })
    }

    return json({
      spawn_batch_id:     batchId,
      spawned,
      skipped,
      active_count_after: active + spawned.length,
      cap,
      dry_run:            !!body.dry_run,
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

async function loadCfg(supabase: ReturnType<typeof createClient>, keys: string[]): Promise<Record<string, string>> {
  const { data } = await supabase.from('app_config').select('key, value').in('key', keys)
  const out: Record<string, string> = {}
  for (const r of data ?? []) out[r.key as string] = r.value as string
  return out
}
