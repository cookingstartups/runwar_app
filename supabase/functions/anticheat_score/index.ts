import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Postgres unique-violation error code. A duplicate pending challenges
// insert for the same user hits the live one-pending-per-user unique index
// and returns this code - an expected, anticipated outcome, not a failure.
const UNIQUE_VIOLATION_CODE = '23505';

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
    const { run_id, samples = [], is_mock_alert = false } = body;

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

      // GPS pattern hash repeat check: look up this user's own history in
      // behavioral_fingerprints. This must run before this batch's own
      // fingerprint row is written below, otherwise every first-time
      // gps_pattern_hash submission would match itself.
      if (body.gps_pattern_hash) {
        const { data: existingHash, error: fpLookupErr } = await supabase
          .from('behavioral_fingerprints')
          .select('id')
          .eq('user_id', playerId)
          .eq('gps_pattern_hash', body.gps_pattern_hash)
          .limit(1);
        if (fpLookupErr) {
          console.error('anticheat_score: behavioral_fingerprints lookup failed', fpLookupErr);
        } else if (existingHash && existingHash.length > 0) {
          flags.push('repeated_gps_pattern');
          score = Math.max(score, 0.6);
        }
      }
    }

    // The batch's one running score (max severity across every rule that
    // fired), carried into anticheat_flags.details and the suspicion_scores
    // upsert below. No per-rule severity model is introduced here.
    const batchScore = score;

    // One anticheat_flags row per fired rule. anticheat_flags has no
    // severity column live, so the batch score is carried in the details
    // jsonb column instead.
    const flagRows = flags.map((flagType) => ({
      id: crypto.randomUUID(),
      user_id: playerId,
      run_id: run_id ?? null,
      flag_type: flagType,
      details: { severity: batchScore },
      created_at: new Date().toISOString(),
    }));

    async function insertFlags(): Promise<{ error: { message: string } | null }> {
      if (flagRows.length > 0) {
        const { error } = await supabase.from('anticheat_flags').insert(flagRows);
        return { error };
      }
      return { error: null };
    }

    // Net-new write: one behavioral_fingerprints row per batch that carries
    // gyro or GPS-pattern data, so a future batch's lookup above has
    // something to match against.
    async function insertFingerprint(): Promise<{ error: { message: string } | null }> {
      if (body.gyro_summary || body.gps_pattern_hash) {
        const { error } = await supabase.from('behavioral_fingerprints').insert({
          id: crypto.randomUUID(),
          user_id: playerId,
          run_id: run_id ?? null,
          gyro_summary: body.gyro_summary ?? null,
          gps_pattern_hash: body.gps_pattern_hash ?? null,
          sample_count: samples.length,
          recorded_at: new Date().toISOString(),
        });
        return { error };
      }
      return { error: null };
    }

    // Net-new write: the user's lifetime running suspicion score. The
    // GREATEST/increment semantics this table needs cannot be expressed by
    // a plain client-side upsert, so this goes through an atomic SQL
    // function instead of a lost-update-prone read-then-write here.
    async function upsertSuspicion(): Promise<{ error: { message: string } | null }> {
      const { error } = await supabase.rpc('upsert_suspicion_score', {
        p_user_id: playerId,
        p_session_max_score: batchScore,
        p_run_id: run_id ?? null,
        p_flags_this_batch: flags.length,
      });
      return { error };
    }

    // No ordering dependency among these three writes, so they run
    // concurrently rather than as three sequential awaits.
    const writeErrors: { table: string; error: string }[] = [];

    function recordWriteError(
      table: string,
      settled: PromiseSettledResult<{ error: { message: string } | null }>,
    ) {
      if (settled.status === 'rejected') {
        writeErrors.push({ table, error: String(settled.reason) });
        console.error(`anticheat_score: ${table} write threw`, settled.reason);
        return;
      }
      if (settled.value.error) {
        writeErrors.push({ table, error: settled.value.error.message });
        console.error(`anticheat_score: ${table} write failed`, settled.value.error);
      }
    }

    const [flagsSettled, fingerprintSettled, suspicionSettled] = await Promise.allSettled([
      insertFlags(),
      insertFingerprint(),
      upsertSuspicion(),
    ]);
    recordWriteError('anticheat_flags', flagsSettled);
    recordWriteError('behavioral_fingerprints', fingerprintSettled);
    recordWriteError('suspicion_scores', suspicionSettled);

    // Create a challenge if the batch's score exceeds the existing
    // threshold. Runs after the concurrent write batch above, since it only
    // depends on the already-known score and should not race those writes.
    let challengeId: string | null = null;
    if (score >= 0.7) {
      const candidateId = crypto.randomUUID();
      const { error: challengeErr } = await supabase.from('challenges').insert({
        id: candidateId,
        user_id: playerId,
        trigger_run_id: run_id ?? null,
        challenge_type: 'motion_capture',
        status: 'pending',
        motion_target: null,
        expires_at: new Date(Date.now() + 24 * 3600_000).toISOString(),
      });
      if (!challengeErr) {
        challengeId = candidateId;
      } else if (challengeErr.code === UNIQUE_VIOLATION_CODE) {
        console.log('anticheat_score: pending challenge already exists, skipped');
      } else {
        writeErrors.push({ table: 'challenges', error: challengeErr.message });
        console.error('anticheat_score: challenges insert failed', challengeErr);
      }
    }

    return ok({ flags, score, challenge_id: challengeId, write_errors: writeErrors });

  } catch (e) {
    return err((e as Error).message, 500);
  }
});
