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
    const { offer_id, target_zone_id, player_lat, player_lng } = body;
    if (!offer_id) return err('Missing offer_id');

    // Fetch offer
    const { data: offer, error: offerErr } = await supabase
      .from('superpower_offers')
      .select('id, player_id, offered_power_type, tier, cost_credits, status, expires_at, offer_type')
      .eq('id', offer_id)
      .maybeSingle();

    if (offerErr || !offer) return ok({ success: false, reason: 'offer_not_found' });
    if (offer.player_id !== playerId) return ok({ success: false, reason: 'wrong_player' });
    if (offer.status !== 'pending') return ok({ success: false, reason: 'already_resolved' });
    if (new Date(offer.expires_at) <= new Date()) return ok({ success: false, reason: 'offer_expired' });

    // BLITZ/FORTIFY require a target zone
    const requiresZone = ['BLITZ', 'FORTIFY'].includes(offer.offered_power_type);
    if (requiresZone && !target_zone_id) return ok({ success: false, reason: 'no_target_zone' });

    // Fetch player credits from player_economy
    const { data: economy } = await supabase
      .from('player_economy')
      .select('credits')
      .eq('player_id', playerId)
      .maybeSingle();

    const currentCredits: number = economy?.credits ?? 0;
    if (currentCredits < offer.cost_credits) {
      return ok({ success: false, reason: 'insufficient_credits' });
    }

    // Debit credits
    await supabase.rpc('increment_credits', {
      p_player: playerId,
      p_amount: -offer.cost_credits,
    });

    const newBalance = currentCredits - offer.cost_credits;

    // Create grant
    const grantId = crypto.randomUUID();
    await supabase.from('superpower_grants').insert({
      id: grantId,
      player_id: playerId,
      power_type: offer.offered_power_type,
      charges: 1,
      charges_used: 0,
      source: `offer:${offer_id}`,
      expires_at: new Date(Date.now() + 2 * 3600_000).toISOString(),
    });

    // Mark offer resolved
    await supabase.from('superpower_offers').update({ status: 'accepted' }).eq('id', offer_id);

    // Immediate effect for BLITZ / FORTIFY
    let effectApplied: { zone_id: string; influence_delta: number } | null = null;
    if (requiresZone && target_zone_id) {
      const delta = offer.offered_power_type === 'BLITZ' ? -3 : 3;
      const { data: zone } = await supabase
        .from('zones')
        .select('id, owner_id, influence')
        .eq('id', target_zone_id)
        .maybeSingle();
      if (zone) {
        const newInf = Math.max(1, Math.min(15, (zone.influence ?? 1) + delta));
        await supabase.from('zones').update({ influence: newInf }).eq('id', target_zone_id);
        effectApplied = { zone_id: target_zone_id, influence_delta: delta };
      }
    }

    return ok({
      success: true,
      offer_id,
      grant_id: grantId,
      new_balance: newBalance,
      effect_applied: effectApplied,
    });

  } catch (e) {
    return err((e as Error).message, 500);
  }
});
