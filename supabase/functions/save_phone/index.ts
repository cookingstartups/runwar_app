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

    const body = await req.json();
    const { phone } = body as { phone?: string };

    if (!phone || !/^\+\d{7,15}$/.test(phone)) {
      return err('Invalid phone — must be E.164 format, e.g. +34722456789');
    }

    const { error: updateErr } = await supabase
      .from('players')
      .update({ phone })
      .eq('user_id', user.id);

    if (updateErr) return err(`DB error: ${updateErr.message}`, 500);

    return ok({ success: true });
  } catch (e) {
    return err(`Unexpected error: ${e}`, 500);
  }
});
