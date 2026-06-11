import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function ok(body: unknown = {}) {
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
    const { challenge_id, outcome } = body;
    if (!challenge_id || !outcome) return err('Missing challenge_id or outcome');

    // Fetch challenge — must belong to this player and be open
    const { data: challenge, error: challengeErr } = await supabase
      .from('challenges')
      .select('id, user_id, status')
      .eq('id', challenge_id)
      .maybeSingle();

    if (challengeErr || !challenge) return ok({ error: 'challenge_not_found' });
    if (challenge.user_id !== playerId) return ok({ error: 'wrong_player' });
    if (challenge.status !== 'open') return ok({ error: 'already_resolved' });

    // Update status
    const { error: updateErr } = await supabase
      .from('challenges')
      .update({
        status: outcome,
        resolved_at: new Date().toISOString(),
      })
      .eq('id', challenge_id);

    if (updateErr) return err('Failed to update challenge', 500);

    // If passed, restore player reputation (lift any soft ban)
    if (outcome === 'pass') {
      await supabase
        .from('players')
        .update({ is_flagged: false })
        .eq('user_id', playerId);
    }

    return ok({});

  } catch (e) {
    return err((e as Error).message, 500);
  }
});
