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
    const { run_id, samples = [], is_mock_alert = false, triggered_by = 'telemetry' } = body;

    const flags: string[] = [];
    let score = 0;

    if (is_mock_alert) {
      flags.push('mock_location');
      score = 0.9;
    } else if (Array.isArray(samples) && samples.length >= 2) {
      // Speed check between consecutive GPS points
      for (let i = 1; i < samples.length; i++) {
        const a = samples[i - 1];
        const b = samples[i];
        if (a.lat == null || b.lat == null) continue;
        const dist = haversineM(a.lat, a.lng, b.lat, b.lng);
        const dt = Math.max((b.ts ?? 0) - (a.ts ?? 0), 1) / 1000; // seconds
        const speed = dist / dt; // m/s
        if (speed > 12) {
          flags.push('speed_violation');
          score = Math.max(score, Math.min((speed - 12) / 20, 1.0));
        }
        // Teleport: >500m in <5s
        if (dist > 500 && dt < 5) {
          flags.push('teleport');
          score = Math.max(score, 0.95);
        }
      }

      // Gyro correlation check (if provided)
      if (body.gyro_summary) {
        const { variance } = body.gyro_summary;
        if (variance < 0.001) {
          flags.push('no_motion');
          score = Math.max(score, 0.7);
        }
      }

      // GPS pattern hash repeat check (simple: flag if present)
      if (body.gps_pattern_hash) {
        const { data: existingHash } = await supabase
          .from('anticheat_reports')
          .select('id')
          .eq('user_id', playerId)
          .eq('gps_pattern_hash', body.gps_pattern_hash)
          .limit(1);
        if (existingHash && existingHash.length > 0) {
          flags.push('repeated_gps_pattern');
          score = Math.max(score, 0.6);
        }
      }
    }

    // Persist report
    const reportId = crypto.randomUUID();
    await supabase.from('anticheat_reports').insert({
      id: reportId,
      user_id: playerId,
      run_id: run_id ?? null,
      score,
      flags,
      triggered_by,
      gps_pattern_hash: body.gps_pattern_hash ?? null,
      sample_count: samples.length,
      created_at: new Date().toISOString(),
    }).select();

    // Create challenge if score exceeds threshold
    let challengeId: string | null = null;
    if (score >= 0.7) {
      challengeId = crypto.randomUUID();
      await supabase.from('challenges').insert({
        id: challengeId,
        user_id: playerId,
        status: 'open',
        trigger: flags[0] ?? 'anticheat',
        anticheat_report_id: reportId,
        expires_at: new Date(Date.now() + 24 * 3600_000).toISOString(),
        created_at: new Date().toISOString(),
      });
    }

    return ok({ flags, score, challenge_id: challengeId });

  } catch (e) {
    return err((e as Error).message, 500);
  }
});
