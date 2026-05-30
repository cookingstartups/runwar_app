import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
// Haversine distance in metres
function haversineM(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}
Deno.serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: corsHeaders
    });
  }
  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return new Response(JSON.stringify({
        error: 'Missing authorization'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 401
      });
    }
    const jwt = authHeader.replace('Bearer ', '');
    const supabase = createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'));
    const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt);
    if (authErr || !user) {
      return new Response(JSON.stringify({
        error: 'Invalid token'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 401
      });
    }
    const body = await req.json();
    const { event_id, lat, lng } = body;
    const player_id = user.id;
    if (!event_id || lat == null || lng == null) {
      return new Response(JSON.stringify({
        error: 'Missing required fields'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 400
      });
    }
    // ── Participant check ─────────────────────────────────────────────────────
    const { data: participant, error: partErr } = await supabase.from('ctf_participants').select('player_id').eq('event_id', event_id).eq('player_id', player_id).maybeSingle();
    if (partErr || !participant) {
      return new Response(JSON.stringify({
        error: 'Not a participant in this event'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 403
      });
    }
    // ── Validate coordinates ──────────────────────────────────────────────────
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return new Response(JSON.stringify({
        error: 'Invalid coordinates'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 400
      });
    }
    // ── Fetch CTF event ───────────────────────────────────────────────────────
    const { data: event, error: eventErr } = await supabase.from('ctf_events').select('id, lat, lng, expires_at, is_active, winner_id').eq('id', event_id).maybeSingle();
    if (eventErr || !event) {
      return new Response(JSON.stringify({
        error: 'CTF event not found'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 404
      });
    }
    if (!event.is_active || event.winner_id !== null) {
      return new Response(JSON.stringify({
        error: 'CTF event is no longer active or already won'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 400
      });
    }
    if (new Date(event.expires_at) <= new Date()) {
      return new Response(JSON.stringify({
        error: 'CTF event has expired'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 400
      });
    }
    // ── Distance check ────────────────────────────────────────────────────────
    const distM = haversineM(lat, lng, event.lat, event.lng);
    if (distM > 50) {
      return new Response(JSON.stringify({
        won: false,
        distance_m: distM,
        reason: 'Too far from CTF flag'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 200
      });
    }
    // ── Claim win: update ctf_events ──────────────────────────────────────────
    const { error: updateErr } = await supabase.from('ctf_events').update({
      winner_id: player_id,
      is_active: false
    }).eq('id', event_id).is('winner_id', null) // guard against race condition
    ;
    if (updateErr) {
      return new Response(JSON.stringify({
        error: 'Failed to claim CTF win'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 500
      });
    }
    // ── Award 500 credits ─────────────────────────────────────────────────────
    await supabase.rpc('increment_credits', {
      p_player: player_id,
      p_amount: 500
    });
    // ── Grant SHIELD superpower for 2 hours ───────────────────────────────────
    const shieldExpiry = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
    await supabase.from('superpower_grants').insert({
      player_id,
      power_type: 'SHIELD',
      expires_at: shieldExpiry,
      charge_cost: 0
    });
    // Activate shield on all owned zones immediately
    await supabase.from('zones').update({
      shield_active: true,
      shield_expires_at: shieldExpiry
    }).eq('owner_id', player_id);
    return new Response(JSON.stringify({
      won: true,
      credits_awarded: 500,
      power_type: 'SHIELD',
      shield_expires_at: shieldExpiry
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      },
      status: 200
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: err.message
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      },
      status: 500
    });
  }
});
