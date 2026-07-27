// supabase/functions/passive_income_tick/index.ts
// Manual trigger only - NO pg_cron scheduled. Activation deferred to Phase 5.
//
// POST body: { mode: 'manual' | 'cron', dry_run?: boolean, player_id?: string }
// Auth: Bearer <SERVICE_ROLE_JWT> (manual) OR x-cron-secret header (cron - deferred).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { writeLedger }  from '../_shared/credit_ledger.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
}

interface Body {
  mode:       'manual' | 'cron'
  dry_run?:   boolean
  player_id?: string     // optional: scope to one player for testing / catch-up
}

interface ZoneRow {
  id:                     string
  owner_id:               string
  area_m2:                number | null
  influence_level:        number
  last_passive_income_at: string
  created_at:             string
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const started = Date.now()

  try {
    const body = (await req.json()) as Body

    // ── Auth ──────────────────────────────────────────────────────────────────
    const isCron = body.mode === 'cron'
    if (isCron) {
      const cronSecret = req.headers.get('x-cron-secret')
      if (cronSecret !== Deno.env.get('CRON_SECRET')) {
        return json({ error: 'cron secret missing/invalid' }, 401)
      }
    } else {
      const auth = req.headers.get('Authorization') ?? ''
      if (!auth.startsWith('Bearer ')) return json({ error: 'missing auth' }, 401)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // ── Config ────────────────────────────────────────────────────────────────
    const cfg = await loadCfg(supabase, [
      'passive_income_min_zone_age_seconds',
      'passive_income_min_interval_seconds',
      'overclock_multiplier',
    ])
    const minAgeS  = +cfg.passive_income_min_zone_age_seconds
    const minIvalS = +cfg.passive_income_min_interval_seconds
    const ocMult   = +cfg.overclock_multiplier

    // ── Eligible zones ────────────────────────────────────────────────────────
    let q = supabase
      .from('zones')
      .select('id, owner_id, area_m2, influence_level, last_passive_income_at, created_at')
      .lt('last_passive_income_at',
          new Date(Date.now() - minIvalS * 1000).toISOString())
      .lt('created_at',
          new Date(Date.now() - minAgeS  * 1000).toISOString())
    if (body.player_id) q = q.eq('owner_id', body.player_id)
    const { data: zones, error: zonesErr } = await q
    if (zonesErr) throw new Error(`zones fetch: ${zonesErr.message}`)

    // ── OVERCLOCK lookup ──────────────────────────────────────────────────────
    const ownerIds     = [...new Set((zones ?? []).map((z: ZoneRow) => z.owner_id))]
    const overclocked  = new Set<string>()
    if (ownerIds.length > 0) {
      const { data: oc } = await supabase
        .from('superpower_grants')
        .select('player_id')
        .eq('power_type', 'OVERCLOCK')
        .gt('expires_at', new Date().toISOString())
        .in('player_id', ownerIds)
      for (const row of oc ?? []) overclocked.add(row.player_id as string)
    }

    // ── Compute + apply ───────────────────────────────────────────────────────
    type Bucket = { credits: number; zones: number }
    const perPlayer = new Map<string, Bucket>()
    const errors: Array<{ zone_id: string; error: string }> = []
    const now = new Date()

    for (const z of (zones ?? []) as ZoneRow[]) {
      try {
        const last   = new Date(z.last_passive_income_at)
        const deltaH = (now.getTime() - last.getTime()) / 3_600_000
        if (deltaH <= 0) continue
        const areaKm2 = (z.area_m2 ?? 0) / 1_000_000
        const mult    = overclocked.has(z.owner_id) ? ocMult : 1
        const earned  = Math.floor(z.influence_level * areaKm2 * deltaH * mult)
        if (earned <= 0) continue

        if (!body.dry_run) {
          await writeLedger(supabase, {
            playerId:          z.owner_id,
            delta:             earned,
            reason:            'passive_income',
            relatedEntityId:   z.id,
            relatedEntityType: 'zone',
            metadata: { hours: deltaH, area_km2: areaKm2, multiplier: mult, mode: body.mode },
          })
          await supabase
            .from('zones')
            .update({ last_passive_income_at: now.toISOString() })
            .eq('id', z.id)
        }

        const b = perPlayer.get(z.owner_id) ?? { credits: 0, zones: 0 }
        b.credits += earned
        b.zones   += 1
        perPlayer.set(z.owner_id, b)
      } catch (err) {
        errors.push({ zone_id: z.id, error: (err as Error).message })
      }
    }

    const totalCredits = [...perPlayer.values()].reduce((s, b) => s + b.credits, 0)
    const durationMs   = Date.now() - started

    // ── Audit row ─────────────────────────────────────────────────────────────
    if (!body.dry_run) {
      await supabase.from('passive_income_runs').insert({
        invocation_mode: body.mode,
        zones_processed: zones?.length ?? 0,
        players_paid:    perPlayer.size,
        total_credits:   totalCredits,
        duration_ms:     durationMs,
        errors,
      })
    }

    return json({
      invocation_id:   crypto.randomUUID(),
      zones_processed: zones?.length ?? 0,
      players_paid:    perPlayer.size,
      total_credits:   totalCredits,
      duration_ms:     durationMs,
      dry_run:         !!body.dry_run,
      per_player_breakdown: [...perPlayer.entries()].map(([p, b]) => ({
        player_id: p, credits: b.credits, zones: b.zones,
      })),
      errors,
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
  const { data, error } = await supabase
    .from('app_config').select('key, value').in('key', keys)
  if (error) throw new Error(`loadCfg: ${error.message}`)
  const out: Record<string, string> = {}
  for (const r of data ?? []) out[r.key as string] = r.value as string
  return out
}
