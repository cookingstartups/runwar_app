// supabase/functions/activate_shield/handler.ts
//
// Consumes one unused SHIELD grant from a player's inventory and activates
// it on a single zone the player owns. The ownership check, the grant
// consumption and the zone's shield fields are all written inside one
// database transaction (the activate_shield_on_zone_tx RPC), so a rejected
// activation leaves every row exactly as it was. This handler itself never
// writes a table directly - it authenticates, validates the request body,
// calls the RPC once, and maps the RPC's typed outcome to a response.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { kShieldBaseHoursPerLevel } from '../_shared/constants.ts';

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

// The narrow client surface this handler needs. A test injects a fake
// implementing exactly this shape, mirroring resolve_decay_merges_test.ts's
// FakeDbClient discipline, so real execution runs against a recorder
// instead of a live database.
export interface ActivateShieldDbClient {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: Record<string, unknown>[] | Record<string, unknown> | null; error: { message: string } | null }>;
  from(table: string): {
    update(values: Record<string, unknown>): {
      eq(col: string, val: unknown): PromiseLike<{ error: { message: string } | null }>;
    };
    insert(values: Record<string, unknown>): PromiseLike<{ error: { message: string } | null }>;
  };
}

export interface ActivateShieldResult {
  success: boolean;
  zone_id?: string;
  shield_expires_at?: string;
  influence_level?: number;
  grant_id?: string;
  reason?: string;
}

// Pure(ish) core: given an injected client, a caller id and a target zone,
// consume a grant and activate the shield. No Request/Response handling
// here, matching resolveDecayMerge's own testable-core shape.
//
// STUB: this is a placeholder pending the real implementation. It forwards
// the call to the RPC with the correct arguments, but does not yet inspect
// the RPC's returned outcome row at all - it always reports success and
// never surfaces shield_expires_at / influence_level / grant_id, and never
// maps not_owner / no_grant / zone_not_found to a rejection. This exists
// only so imports resolve and the real behavior can be asserted against and
// found missing.
export async function activateShieldOnZone(
  db: ActivateShieldDbClient,
  userId: string,
  targetZoneId: string,
  hoursPerLevel: number = kShieldBaseHoursPerLevel,
): Promise<ActivateShieldResult> {
  const { error } = await db.rpc('activate_shield_on_zone_tx', {
    p_user_id: userId,
    p_zone_id: targetZoneId,
    p_hours_per_level: hoursPerLevel,
  });
  if (error) {
    return { success: false, reason: 'rpc_error' };
  }
  return { success: true, zone_id: targetZoneId };
}

export async function handleActivateShieldRequest(req: Request): Promise<Response> {
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
    const { target_zone_id } = body;
    if (!target_zone_id) return err('Missing target_zone_id');

    const result = await activateShieldOnZone(supabase, user.id, target_zone_id);
    return ok(result);
  } catch (e) {
    return err((e as Error).message, 500);
  }
}
