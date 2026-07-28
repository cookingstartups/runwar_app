// supabase/functions/account-deletion-executor/index.ts
//
// Service-role only. Invoked by the daily pg_cron sweep (over pg_net) and by
// the manual admin-surface trigger, which passes an optional single
// request_id to scope the run to one row instead of sweeping every eligible
// row.
//
// Each eligible row's zone transfer (claim_and_transfer_zones, via rpc) and
// subsequent auth-user deletion (Admin API) are processed in their own loop
// iteration wrapped in try/catch, so one row's failure never blocks the rest
// of the sweep. The auth user is always deleted through the Admin API -
// never a raw SQL delete against auth.users.
//
// Full spec: infra/meta/specs/runwar/settings-screen/design.md section 3.7/3.8

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface SweepResult {
  id: string;
  ok: boolean;
  error?: string;
}

serve(async (req: Request) => {
  const headers = { 'Content-Type': 'application/json' };

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const requestId = (body.request_id as string | undefined) ?? undefined;

  let eligible: { id: string }[];
  if (requestId) {
    eligible = [{ id: requestId }];
  } else {
    const { data } = await supabase
      .from('account_deletion_requests')
      .select('id')
      .eq('status', 'pending')
      .lte('scheduled_deletion_at', new Date().toISOString());
    eligible = data ?? [];
  }

  const results: SweepResult[] = [];

  for (const row of eligible) {
    try {
      const { data: userId, error } = await supabase.rpc('claim_and_transfer_zones', {
        p_request_id: row.id,
      });

      if (error || !userId) {
        results.push({ id: row.id, ok: false, error: error?.message ?? 'not claimed' });
        continue; // one row's failure never blocks the rest of the sweep
      }

      const { error: deleteError } = await supabase.auth.admin.deleteUser(userId as string);
      results.push({ id: row.id, ok: !deleteError, error: deleteError?.message });
    } catch (err) {
      results.push({ id: row.id, ok: false, error: err instanceof Error ? err.message : String(err) });
      continue;
    }
  }

  return new Response(JSON.stringify({ processed: results }), { status: 200, headers });
});
