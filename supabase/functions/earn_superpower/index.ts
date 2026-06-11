import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function ok(body: unknown) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status: 200,
  });
}
function err(msg: string, status = 400) {
  return new Response(JSON.stringify({ error: msg }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  });
}

// Probability + pool per event type
const EVENT_CONFIG: Record<string, { prob: number; powers: string[]; tier: string; charges: number; durationMin: number }> = {
  claim:             { prob: 0.15, powers: ['RUSH', 'SHIELD'],    tier: 'common', charges: 1, durationMin: 30  },
  conquest:          { prob: 0.30, powers: ['SHIELD', 'BLITZ'],   tier: 'rare',   charges: 2, durationMin: 60  },
  defence:           { prob: 0.20, powers: ['FORTIFY', 'SHIELD'], tier: 'common', charges: 1, durationMin: 45  },
  run_end:           { prob: 0.10, powers: ['OVERCLOCK', 'RUSH'], tier: 'common', charges: 1, durationMin: 20  },
  zone_count_change: { prob: 0.05, powers: ['FORTIFY'],           tier: 'common', charges: 1, durationMin: 30  },
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return err('Missing authorization', 401);

    const jwt = authHeader.replace('Bearer ', '');
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt);
    if (authErr || !user) return err('Invalid token', 401);
    const playerId = user.id;

    const body = await req.json();
    // Accept both old { run_id } and new EarnEvent { event, run_id?, zone_id? }
    const event: string = body.event ?? 'run_end';
    const config = EVENT_CONFIG[event] ?? EVENT_CONFIG['run_end'];

    // Probabilistic gate
    if (Math.random() > config.prob) {
      return ok({ granted: false, reason: 'not_this_time' });
    }

    const powerType = config.powers[Math.floor(Math.random() * config.powers.length)];
    const expiresAt = new Date(Date.now() + config.durationMin * 60_000).toISOString();
    const grantId = crypto.randomUUID();

    const { error: insertErr } = await supabase.from('superpower_grants').insert({
      id: grantId,
      user_id: playerId,
      power_type: powerType,
      charges: config.charges,
      charges_used: 0,
      source: `earn_event:${event}`,
      expires_at: expiresAt,
    });

    if (insertErr) return err('Failed to create grant', 500);

    return ok({
      granted: true,
      power_type: powerType,
      grant_id: grantId,
      tier: config.tier,
      charges: config.charges,
      expires_at: expiresAt,
    });

  } catch (e) {
    return err((e as Error).message, 500);
  }
});
