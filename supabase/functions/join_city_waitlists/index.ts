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
    const { slugs, referral_source_code } = body as {
      slugs?: string[];
      referral_source_code?: string;
    };

    if (!Array.isArray(slugs) || slugs.length === 0) {
      return err('slugs must be a non-empty array of city slugs');
    }
    if (slugs.length > 10) {
      return err('Too many slugs — max 10 per call');
    }

    const now = new Date().toISOString();
    const rows = slugs.map((slug) => ({
      user_id: user.id,
      city_slug: slug,
      created_at: now,
      ...(referral_source_code ? { referral_source_code } : {}),
    }));

    const { error: upsertErr } = await supabase
      .from('city_waitlists')
      .upsert(rows, { onConflict: 'city_waitlists_user_id_city_slug_key', ignoreDuplicates: true });

    if (upsertErr) return err(`DB error: ${upsertErr.message}`, 500);

    return ok({ success: true, joined: slugs });
  } catch (e) {
    return err(`Unexpected error: ${e}`, 500);
  }
});
