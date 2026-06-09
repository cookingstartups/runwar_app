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

function haversineM(lat1: number, lng1: number, lat2: number, lng2: number) {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180)
    * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}

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
    const { drop_id, player_lat, player_lng } = body;
    if (!drop_id || player_lat == null || player_lng == null) return err('Missing fields');

    // Fetch drop
    const { data: drop, error: dropErr } = await supabase
      .from('drops')
      .select('id, lat, lng, drop_type, value, status, expires_at, city')
      .eq('id', drop_id)
      .maybeSingle();

    if (dropErr || !drop) return ok({ success: false, reason: 'not_found' });
    if (drop.status !== 'active') return ok({ success: false, reason: 'already_claimed' });
    if (new Date(drop.expires_at) <= new Date()) return ok({ success: false, reason: 'expired' });

    // Proximity check — 50 m gate
    const distM = haversineM(player_lat, player_lng, drop.lat, drop.lng);
    if (distM > 50) {
      return ok({ success: false, reason: 'too_far', distance_m: Math.round(distM) });
    }

    // Mark drop claimed
    const { error: updateErr } = await supabase
      .from('drops')
      .update({ status: 'claimed', claimed_by: playerId, claimed_at: new Date().toISOString() })
      .eq('id', drop_id)
      .eq('status', 'active'); // guard race condition

    if (updateErr) return err('Failed to claim drop', 500);

    const dropType: string = drop.drop_type;
    const value: number = drop.value ?? 0;

    if (dropType === 'credits_cache') {
      const { error: creditErr } = await supabase.rpc('increment_credits', { p_player: playerId, p_amount: value });
      if (creditErr) return new Response(JSON.stringify({ error: 'Failed to award credits: ' + creditErr.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
      const { data: economy } = await supabase
        .from('player_economy')
        .select('credits')
        .eq('player_id', playerId)
        .maybeSingle();
      return ok({
        success: true,
        drop_type: dropType,
        credits_awarded: value,
        new_balance: economy?.credits ?? 0,
      });
    }

    if (dropType === 'influence_crystal') {
      // Boost influence on player's nearest zone in this city
      const { data: zones } = await supabase
        .from('zones')
        .select('id, influence')
        .eq('owner_id', playerId)
        .eq('city', drop.city)
        .limit(1);
      const zone = zones?.[0];
      let newInfluence = 1;
      if (zone) {
        newInfluence = Math.min((zone.influence ?? 1) + 1, 15);
        await supabase.from('zones').update({ influence: newInfluence }).eq('id', zone.id);
      }
      return ok({
        success: true,
        drop_type: dropType,
        zone_id: zone?.id ?? null,
        new_influence: newInfluence,
      });
    }

    if (dropType === 'power_core') {
      const powers = ['RUSH', 'SHIELD', 'OVERCLOCK', 'GHOST_RUN'];
      const grantedPower = powers[Math.floor(Math.random() * powers.length)];
      const grantId = crypto.randomUUID();
      await supabase.from('superpower_grants').insert({
        id: grantId,
        player_id: playerId,
        power_type: grantedPower,
        charges: value || 1,
        charges_used: 0,
        source: `drop:${drop_id}`,
        expires_at: new Date(Date.now() + 24 * 3600_000).toISOString(),
      });
      return ok({
        success: true,
        drop_type: dropType,
        granted_power: grantedPower,
        tier: 'common',
        charges: value || 1,
      });
    }

    return ok({ success: false, reason: 'unknown_drop_type' });

  } catch (e) {
    return err((e as Error).message, 500);
  }
});
