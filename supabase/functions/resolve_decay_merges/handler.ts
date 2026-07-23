// supabase/functions/resolve_decay_merges/handler.ts
//
// Retroactive fuse-on-parity for adjacent same-owner zones whose
// influence_level converges through decay rather than through a claim.
//
// Decay itself runs entirely client-side (territory_service.dart's
// _applyDecay, called on app open) and never submits a claim ring, so it
// cannot run through claim_territory's own split-then-merge path. This
// function is the narrow server-side counterpart the client calls only when
// a single decay tick has just stepped one zone's influence_level DOWN
// across an integer boundary - not on every tick, since most ticks move the
// continuous influence value without crossing a level. Reuses the exact
// same computeZoneMerges level-equality gate claim_territory uses (25 m
// proximity, same-owner, same influence_level required to link), so a zone
// only fuses with a same-owner neighbour once both are confirmed at the same
// level - the "influence never reconciled unless equal" rule stays a single
// source of truth in merge_geometry.ts, not duplicated here.
//
// Deliberately NOT a bonus level-up: unlike a claim (which always earns one
// level via computeNextInfluenceLevel on top of the group's max), a decay-
// triggered fuse is not a player action and must not grant one. The merged
// survivor's influence_level is the plain MAX across the group members -
// already equal by construction, since computeZoneMerges only links zones
// whose influenceLevel already matches.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { computeZoneMerges, type ZoneInput } from '../claim_territory/merge_geometry.ts';
import { area as turfArea } from 'https://esm.sh/@turf/area@7';

const kMergeThresholdMeters = 25;

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

// Every member outline of a possibly-legacy MultiPolygon row, mirroring
// claim_territory/handler.ts's own outlinesOf - kept as a local copy rather
// than an added export from that module, since this is the only other
// caller and the two functions must stay independently deployable.
function outlinesOf(geom: { type?: string; coordinates?: unknown } | null | undefined): number[][][] {
  if (!geom) return [];
  if (geom.type === 'MultiPolygon') {
    return (geom.coordinates as number[][][][]).map((poly) => poly[0]);
  }
  if (geom.type === 'Polygon') {
    const coords = geom.coordinates as number[][][];
    return coords[0] ? [coords[0]] : [];
  }
  return [];
}

function ringToWktBody(ring: number[][]): string {
  const [fx, fy] = ring[0];
  const [lx, ly] = ring[ring.length - 1];
  const closed = fx === lx && fy === ly ? ring : [...ring, [fx, fy]];
  return `(${closed.map(([lng, lat]) => `${lng} ${lat}`).join(', ')})`;
}

function toWkt(
  input: { type: 'Polygon'; coordinates: number[][][] } | { type: 'MultiPolygon'; coordinates: number[][][][] },
): string {
  if (input.type === 'Polygon') {
    return `SRID=4326;POLYGON(${ringToWktBody(input.coordinates[0])})`;
  }
  const polys = input.coordinates.map((poly) => `(${ringToWktBody(poly[0])})`).join(', ');
  return `SRID=4326;MULTIPOLYGON(${polys})`;
}

export interface ResolveDecayMergeRequestBody {
  owner_id: string;
  city: string;
  zone_id: string;
}

export interface ResolveDecayMergeDbClient {
  from(table: string): {
    select(cols: string): {
      eq(col: string, val: unknown): {
        eq(col: string, val: unknown): {
          eq(col: string, val: unknown): PromiseLike<{ data: Record<string, unknown>[] | null; error: { message: string } | null }>;
        };
      };
    };
  };
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<{ error: { message: string } | null }>;
}

export interface ResolveDecayMergeResult {
  merged: boolean;
  survivorId?: string;
  absorbedZoneIds?: string[];
}

// Pure orchestration (injectable db client) so tests can exercise it without
// a live Supabase project, the same discipline claim_territory's
// runSplitAndMerge already follows.
export async function resolveDecayMerge(
  supabase: ResolveDecayMergeDbClient,
  ownerId: string,
  city: string,
  zoneId: string,
): Promise<ResolveDecayMergeResult> {
  const { data: candidateRows, error: selectErr } = await supabase
    .from('zones')
    .select(
      'id, geom_json, created_at, influence, influence_level, credits_earned, last_active_at, shield_active, shield_expires_at',
    )
    .eq('owner_id', ownerId)
    .eq('city', city)
    .eq('status', 'owned');
  if (selectErr) throw new Error(`Zone select failed: ${selectErr.message}`);

  const influenceById = new Map<string, number>();
  const influenceLevelById = new Map<string, number>();
  const creditsEarnedById = new Map<string, number>();
  const lastActiveAtById = new Map<string, string | null>();
  const shieldActiveById = new Map<string, boolean>();
  const shieldExpiresAtById = new Map<string, string | null>();

  const inputs: ZoneInput[] = (candidateRows ?? [])
    .map((r) => {
      const id = r.id as string;
      influenceById.set(id, (r.influence as number | null) ?? 1);
      influenceLevelById.set(id, (r.influence_level as number | null) ?? 1);
      creditsEarnedById.set(id, (r.credits_earned as number | null) ?? 0);
      lastActiveAtById.set(id, (r.last_active_at as string | null) ?? null);
      shieldActiveById.set(id, (r.shield_active as boolean | null) ?? false);
      shieldExpiresAtById.set(id, (r.shield_expires_at as string | null) ?? null);
      const geom = typeof r.geom_json === 'string' ? JSON.parse(r.geom_json) : r.geom_json;
      return outlinesOf(geom).map((ring) => ({
        id,
        ring,
        createdAt: r.created_at as string,
        influenceLevel: (r.influence_level as number | null) ?? 1,
      }));
    })
    .flat();

  const groups = computeZoneMerges(inputs, kMergeThresholdMeters);
  const group = groups.find((g) => g.survivorId === zoneId || g.absorbedIds.includes(zoneId));
  if (!group) return { merged: false };

  const uniqueAbsorbedIds = [...new Set(group.absorbedIds)];
  const groupIds = [group.survivorId, ...uniqueAbsorbedIds];

  const survivorInfluence = (influenceById.get(group.survivorId) ?? 1) +
    uniqueAbsorbedIds.reduce((sum, id) => sum + (influenceById.get(id) ?? 1), 0);

  // No level-up on top of the max, unlike claim_territory's merge path - see
  // the module doc comment above. Every group member is already at the same
  // influence_level by construction (computeZoneMerges' own linking gate).
  const survivorInfluenceLevel = groupIds.reduce(
    (max, id) => Math.max(max, influenceLevelById.get(id) ?? 1),
    1,
  );

  const survivorLastActiveAt = groupIds.reduce<string | null>((max, id) => {
    const v = lastActiveAtById.get(id) ?? null;
    if (!v) return max;
    if (!max || v > max) return v;
    return max;
  }, null);

  const survivorCreditsEarned = groupIds.reduce(
    (sum, id) => sum + (creditsEarnedById.get(id) ?? 0),
    0,
  );

  const anyShieldActive = groupIds.some((id) => shieldActiveById.get(id) === true);
  const survivorShieldExpiresAt = anyShieldActive
    ? groupIds.reduce<string | null>((max, id) => {
      if (!shieldActiveById.get(id)) return max;
      const v = shieldExpiresAtById.get(id) ?? null;
      if (!v) return max;
      if (!max || v > max) return v;
      return max;
    }, null)
    : shieldExpiresAtById.get(group.survivorId) ?? null;

  const survivorAreaM2 = turfArea(group.geometry);
  const nowIso = new Date().toISOString();

  const { error: mergeErr } = await supabase.rpc('apply_zone_merge', {
    p_survivor_id: group.survivorId,
    p_absorbed_ids: uniqueAbsorbedIds,
    p_geom_wkt: toWkt(group.geometry),
    p_geom_json: JSON.stringify(group.geometry),
    p_influence: survivorInfluence,
    p_influence_level: survivorInfluenceLevel,
    p_credits_earned: survivorCreditsEarned,
    p_last_active_at: survivorLastActiveAt,
    p_shield_active: anyShieldActive,
    p_shield_expires_at: survivorShieldExpiresAt,
    p_area_m2: survivorAreaM2,
    p_updated_at: nowIso,
  });
  if (mergeErr) throw new Error(`Zone merge failed: ${mergeErr.message}`);

  return { merged: true, survivorId: group.survivorId, absorbedZoneIds: uniqueAbsorbedIds };
}

// Thin HTTP handler, kept separate from index.ts's Deno.serve() call so a
// test can import it directly, matching every other function under
// supabase/functions/. Auth model mirrors the rest of decay: any
// authenticated device may trigger this resolution for any owner/city, the
// same permissive rule the client-side decay tick itself already relies on
// to write other players' zone rows (territory_service.dart's
// _applyDecay iterates every owned zone in a city, not just the caller's
// own). This endpoint does no geometry work of its own beyond what
// resolveDecayMerge above does; ownership of the merge candidates is
// scoped entirely by the owner_id/city query filter, exactly like
// claim_territory's own candidate query.
export async function handleResolveDecayMergesRequest(req: Request): Promise<Response> {
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

    const body = await req.json() as Partial<ResolveDecayMergeRequestBody>;
    const ownerId = body.owner_id;
    const city = body.city;
    const zoneId = body.zone_id;
    if (!ownerId || !city || !zoneId) return err('Missing owner_id, city, or zone_id');

    // Cast rather than rely on structural inference: the real supabase-js
    // client's `.from()/.eq()` chain carries deep generic overloads that
    // make TypeScript's structural check against the narrow
    // ResolveDecayMergeDbClient shape recurse excessively. The real client
    // satisfies the narrow shape at runtime (it is a superset of it); the
    // cast just tells the checker to stop trying to prove that itself.
    const result = await resolveDecayMerge(
      supabase as unknown as ResolveDecayMergeDbClient,
      ownerId,
      city,
      zoneId,
    );
    return ok({
      merged: result.merged,
      survivor_id: result.survivorId ?? null,
      absorbed_zone_ids: result.absorbedZoneIds ?? [],
    });
  } catch (e) {
    return err(`resolve_decay_merges failed: ${e}`, 500);
  }
}
