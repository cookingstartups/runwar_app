// supabase/functions/expire_drops/index.ts
// Manual trigger only - NO pg_cron scheduled.
// Soft-expires active drops whose TTL has elapsed (sets status='expired').
//
// POST body: { city?: string } - optional city filter
// Auth: Bearer <SERVICE_ROLE_JWT>

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const auth = req.headers.get('Authorization') ?? ''
    if (!auth.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'missing auth' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const { city } = (await req.json().catch(() => ({}))) as { city?: string }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    let q = supabase
      .from('drops')
      .update({ status: 'expired', expired: true })
      .eq('status', 'active')
      .lt('expires_at', new Date().toISOString())
    if (city) q = q.eq('city', city)

    const { data, error } = await q.select('id, city')
    if (error) throw error

    const cities = [...new Set((data ?? []).map((r: { city: string }) => r.city))]

    return new Response(
      JSON.stringify({ expired_count: data?.length ?? 0, cities }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 },
    )
  }
})
