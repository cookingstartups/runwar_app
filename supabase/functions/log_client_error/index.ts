// supabase/functions/log_client_error/index.ts
//
// Inserts a single row into the client_errors table.
// Called fire-and-forget from ErrorLogService in the Flutter app.
//
// Auth: anon key (public endpoint).
// Rate limit: 100 inserts per minute per IP (in-function Deno KV counter).
// Full spec: infra/meta/specs/runwar/mvp/boot-splash-unified/requirements.md

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ── Rate-limit state (Deno KV) ────────────────────────────────────────────────
// Key: `rl:${ip}:${minuteBucket}` → count
// TTL: 90 s (covers the current minute + 30 s buffer).
const RATE_LIMIT = 100;   // max inserts per minute per IP
const WINDOW_MS  = 60_000; // 1 minute window

async function checkRateLimit(ip: string): Promise<boolean> {
  try {
    const kv       = await Deno.openKv();
    const bucket   = Math.floor(Date.now() / WINDOW_MS).toString();
    const key      = ['rl', ip, bucket];
    const existing = await kv.get<number>(key);
    const count    = (existing.value ?? 0) + 1;
    if (count > RATE_LIMIT) {
      await kv.close();
      return false; // rate limit exceeded
    }
    await kv.set(key, count, { expireIn: 90_000 });
    await kv.close();
    return true; // allowed
  } catch {
    // If KV is unavailable, allow the request (fail open).
    return true;
  }
}

// ── Required fields ───────────────────────────────────────────────────────────
const REQUIRED_FIELDS = [
  'provider',
  'error_class',
  'error_message',
  'stack_first_line',
  'retry_count',
  'app_version',
  'device',
  'platform',
] as const;

// ── Handler ───────────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  const headers = { 'Content-Type': 'application/json' };

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'method_not_allowed' }),
      { status: 405, headers },
    );
  }

  // Extract client IP for rate-limiting.
  const ip =
    req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ??
    req.headers.get('x-real-ip') ??
    'unknown';

  const allowed = await checkRateLimit(ip);
  if (!allowed) {
    return new Response(
      JSON.stringify({ error: 'rate_limit_exceeded' }),
      { status: 429, headers },
    );
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: 'invalid_json' }),
      { status: 400, headers },
    );
  }

  // Validate required fields.
  for (const field of REQUIRED_FIELDS) {
    if (body[field] === undefined || body[field] === null) {
      return new Response(
        JSON.stringify({ error: `${field} is required` }),
        { status: 400, headers },
      );
    }
  }

  // The function uses the service role key for the DB insert, bypassing RLS.
  // The anon key is validated by the function gateway before this code runs.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { error } = await supabase.from('client_errors').insert({
    user_id:          body.user_id ?? null,
    provider:         body.provider,
    error_class:      body.error_class,
    error_message:    body.error_message,
    stack_first_line: body.stack_first_line,
    retry_count:      body.retry_count,
    app_version:      body.app_version,
    device:           body.device,
    platform:         body.platform,
  });

  if (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers },
    );
  }

  return new Response(JSON.stringify({ ok: true }), { status: 200, headers });
});
