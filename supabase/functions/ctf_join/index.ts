import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
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
    const player_id = user.id;
    const body = await req.json();
    const { event_id } = body;
    if (!event_id) {
      return new Response(JSON.stringify({
        error: 'Missing event_id'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 400
      });
    }
    // ── Fetch CTF event ───────────────────────────────────────────────────────
    const { data: event, error: eventErr } = await supabase.from('ctf_events').select('id, expires_at, winner_id').eq('id', event_id).maybeSingle();
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
    if (event.winner_id !== null) {
      return new Response(JSON.stringify({
        error: 'CTF event already has a winner'
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
    // ── Insert participant (idempotent via ON CONFLICT DO NOTHING) ───────────
    const { error: insertErr } = await supabase.from('ctf_participants').upsert({
      event_id,
      player_id
    }, {
      onConflict: 'event_id,player_id',
      ignoreDuplicates: true
    });
    if (insertErr) {
      return new Response(JSON.stringify({
        error: 'Failed to join event'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 500
      });
    }
    return new Response(JSON.stringify({
      joined: true
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
