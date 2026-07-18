import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
// Type-only import here (erased at compile time); the runtime binding is
// loaded lazily below, strictly inside the `if (!disputedId)` guard, so the
// merge routine can never execute on a disputed outcome.
import type { ZoneInput } from './merge_geometry.ts';
// Area of the merged geometry is always recomputed from the merge result,
// never summed from source zones (overlapping/adjacent source zones would
// double-count their shared area if simply added together).
import { area as turfArea } from 'https://esm.sh/@turf/area@7';

// Zone-unify edge-to-edge threshold, matching kProximityTriggerM (the same
// 25 m radius used for loop-closure proximity triggering). A same-owner,
// same-city zone within this distance merges into one continuous zone
// (sealed via morphological closing); beyond it, zones stay separate rows.
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

// Haversine distance in metres
function haversineM(lat1: number, lng1: number, lat2: number, lng2: number) {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180)
    * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}

// Ray-cast point-in-polygon (lng/lat coords)
function pointInRing(px: number, py: number, ring: number[][]) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0], yi = ring[i][1];
    const xj = ring[j][0], yj = ring[j][1];
    const intersect = ((yi > py) !== (yj > py)) &&
      (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

function uuid() {
  return crypto.randomUUID();
}

// Return the ring with its first point appended if it is not already closed.
function closedRing(ring: number[][]): number[][] {
  if (ring.length === 0) return ring;
  const [fx, fy] = ring[0];
  const [lx, ly] = ring[ring.length - 1];
  return fx === lx && fy === ly ? ring : [...ring, [fx, fy]];
}

// Build a PostGIS WKT POLYGON from a [lng, lat][] ring. Auto-closes the ring.
function ringToWktBody(ring: number[][]): string {
  const closed = closedRing(ring);
  return `(${closed.map(([lng, lat]) => `${lng} ${lat}`).join(', ')})`;
}

// Build a PostGIS WKT geometry literal from either a plain ring (Polygon,
// pre-merge insert shape) or a merge-result geometry object. The merge
// contract always produces a single continuous Polygon; the MultiPolygon
// branch is kept only so the widened `zones.geom GEOMETRY(Geometry,4326)`
// column can still represent an already-stored legacy row or the rare
// hard-failure fallback in merge_geometry.ts's trueUnion.
function toWkt(
  input: number[][] | { type: 'Polygon'; coordinates: number[][][] } | {
    type: 'MultiPolygon';
    coordinates: number[][][][];
  },
): string {
  if (Array.isArray(input)) {
    return `SRID=4326;POLYGON(${ringToWktBody(input)})`;
  }
  if (input.type === 'Polygon') {
    return `SRID=4326;POLYGON(${ringToWktBody(input.coordinates[0])})`;
  }
  const polys = input.coordinates.map((poly) => `(${ringToWktBody(poly[0])})`).join(', ');
  return `SRID=4326;MULTIPOLYGON(${polys})`;
}

// A zone's geom_json is normally a Polygon (the single-rule merge contract
// never produces a MultiPolygon); a MultiPolygon is only a legacy or
// hard-failure-fallback shape. Returns every member outline as its own ring
// so callers (rival-scan, merge-candidate loading) can test each outline
// independently instead of misreading a MultiPolygon's nested ring array as
// a flat point list.
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
    const { track, city } = body;

    if (!track || track.type !== 'LineString' || !Array.isArray(track.coordinates)) {
      return err('Invalid track GeoJSON');
    }
    if (!city) return err('Missing city');

    const coords: number[][] = track.coordinates;
    if (coords.length < 3) return err('Track too short');

    // Data-sanity cap (NOT anti-cheat): reject a single hop far beyond any plausible
    // GPS gap so an obviously-corrupt track can't produce a garbage polygon. Real runs
    // decimate to a >=50 m point spacing and legitimate GPS dropouts routinely reach
    // ~250 m, so this cap is deliberately generous. Real speed/teleport anti-cheat is
    // owned by the separate anti-cheat pipeline, not by this gate.
    for (let i = 1; i < coords.length; i++) {
      const [lng1, lat1] = coords[i - 1];
      const [lng2, lat2] = coords[i];
      if (haversineM(lat1, lng1, lat2, lng2) > 2000) {
        return ok({ result: 'failed', reason: 'corrupt_track' });
      }
    }

    // Enclosed-area gate - the client's lasso-detection floor is an enclosed
    // area, not a perimeter/distance, so the server must gate on the same
    // quantity or a track that passes the client can still be rejected here.
    // Uses the same turfArea helper already relied on elsewhere in this file
    // for merged-zone area (survivorAreaM2 below) so the area math stays a
    // single source of truth instead of a second hand-rolled projection.
    //
    // Must stay numerically equal to the client-side floor in
    // lib/services/run_recorder_service.dart (_minCapturedAreaSqm) - the two
    // are enforced independently (client gates before dispatch, server gates
    // again on receipt) and a mismatch lets a claim pass one side and fail
    // the other. If this value changes, change the client value too.
    //
    // 4 sqm (a 2x2 m loop) is a data-sanity floor against a degenerate or
    // near-zero-area polygon, not a meaningful anti-jitter gate - ordinary
    // phone GPS noise routinely produces spurious loops well above this size.
    const minCapturedAreaSqm = 4;
    const closedNewRing = closedRing(coords);
    const capturedAreaSqm = turfArea({ type: 'Polygon', coordinates: [closedNewRing] });
    if (capturedAreaSqm < minCapturedAreaSqm) {
      return ok({ result: 'failed', reason: 'too_short' });
    }

    // Load existing zones for this city
    const { data: existingZones } = await supabase
      .from('zones')
      .select('id, owner_id, geom_json, status, influence')
      .eq('city', city);

    const zones = existingZones ?? [];
    const newRing = coords; // [lng, lat] pairs

    let conqueredId: string | null = null;
    let disputedId: string | null = null;
    let disputeResolved = false;

    for (const zone of zones) {
      let outlines: number[][][];
      try {
        const geom = typeof zone.geom_json === 'string'
          ? JSON.parse(zone.geom_json)
          : zone.geom_json;
        // MultiPolygon-aware defensively: a legacy or fallback multi-outline
        // zone stores 2+ member outlines. Each one is tested independently
        // below (OR-combined) so an overlap against ANY member outline is
        // detected, not just the first one misread as a flat ring.
        outlines = outlinesOf(geom).filter((r) => r.length >= 3);
      } catch { continue; }
      if (outlines.length === 0) continue;

      // Check if any rival ring point falls inside our new polygon, and vice
      // versa, across EVERY member outline of this zone's geometry.
      const isRival = zone.owner_id !== playerId;
      const anyRivalPointInside = outlines.some((ring) => ring.some(([x, y]) => pointInRing(x, y, newRing)));
      const anyNewPointInside = outlines.some((ring) => newRing.some(([x, y]) => pointInRing(x, y, ring)));

      if (isRival) {
        if (anyRivalPointInside) {
          // Full or partial conquest
          conqueredId = zone.id;
          await supabase.from('zones').update({
            owner_id: playerId,
            influence: 1,
            status: 'owned',
            contested_by_id: null,
            updated_at: new Date().toISOString(),
          }).eq('id', zone.id);
        } else if (anyNewPointInside) {
          // Partial overlap → dispute
          disputedId = zone.id;
          await supabase.from('zones').update({
            status: 'disputed',
            contested_by_id: playerId,
            updated_at: new Date().toISOString(),
          }).eq('id', zone.id);
        }
      } else {
        // Own zone that was disputed — defending resolves it
        if (zone.status === 'disputed' && anyRivalPointInside) {
          disputeResolved = true;
          await supabase.from('zones').update({
            status: 'owned',
            contested_by_id: null,
            updated_at: new Date().toISOString(),
          }).eq('id', zone.id);
        }
      }
    }

    // Insert new zone for this player. `geom` is NOT NULL on the base table, so it
    // must be populated (the ring is auto-closed for a valid polygon); `geom_json`
    // uses the same closed ring so the rendered polygon matches.
    const newId = uuid();
    const now = new Date().toISOString();
    const ring = closedRing(coords); // [lng, lat] pairs, closed
    const { error: insertErr } = await supabase.from('zones').insert({
      id: newId,
      owner_id: playerId,
      city,
      geom: toWkt(ring),
      geom_json: JSON.stringify({ type: 'Polygon', coordinates: [ring] }),
      influence: 1,
      status: 'owned',
      contested_by_id: null,
      created_at: now,
      updated_at: now,
    });
    if (insertErr) return err(`Zone insert failed: ${insertErr.message}`, 500);

    // Merge only for claimed/conquered outcomes - disputed is excluded even
    // though a new owned row for `playerId` was just inserted.
    let finalZoneId = newId;
    let merged = false;
    let absorbedZoneIds: string[] = [];
    let zoneGeomJson = JSON.stringify({ type: 'Polygon', coordinates: [ring] });

    if (!disputedId) {
      const { computeZoneMerges } = await import('./merge_geometry.ts');
      const { data: candidateRows } = await supabase
        .from('zones')
        .select(
          'id, geom_json, created_at, influence, influence_level, credits_earned, last_active_at, shield_active, shield_expires_at',
        )
        .eq('owner_id', playerId)
        .eq('city', city)
        .eq('status', 'owned')
        .order('created_at', { ascending: true });

      const influenceById = new Map<string, number>();
      const influenceLevelById = new Map<string, number>();
      const creditsEarnedById = new Map<string, number>();
      const lastActiveAtById = new Map<string, string | null>();
      const shieldActiveById = new Map<string, boolean>();
      const shieldExpiresAtById = new Map<string, string | null>();
      const inputs: ZoneInput[] = (candidateRows ?? [])
        .map((r) => {
          influenceById.set(r.id as string, (r.influence as number | null) ?? 1);
          influenceLevelById.set(r.id as string, (r.influence_level as number | null) ?? 1);
          creditsEarnedById.set(r.id as string, (r.credits_earned as number | null) ?? 0);
          lastActiveAtById.set(r.id as string, (r.last_active_at as string | null) ?? null);
          shieldActiveById.set(r.id as string, (r.shield_active as boolean | null) ?? false);
          shieldExpiresAtById.set(r.id as string, (r.shield_expires_at as string | null) ?? null);
          const geom = typeof r.geom_json === 'string' ? JSON.parse(r.geom_json) : r.geom_json;
          // A legacy or fallback multi-outline zone stores 2+ member outlines;
          // feed each one back in as its own ZoneInput ring (same db row id)
          // so a later claim can still test contiguity against each piece
          // independently. computeZoneMerges naturally dedupes them back into
          // one group since they were never actually apart.
          return outlinesOf(geom).map((r2) => ({
            id: r.id as string,
            ring: r2,
            createdAt: r.created_at as string,
          }));
        })
        .flat();

      const groups = computeZoneMerges(inputs, kMergeThresholdMeters);
      const group = groups.find((g) => g.survivorId === newId || g.absorbedIds.includes(newId));

      if (group) {
        const uniqueAbsorbedIds = [...new Set(group.absorbedIds)];
        // No history kept on unification: aggregate additive fields into the
        // survivor, then delete the absorbed rows outright. No lineage-tracking
        // column is written; exactly one row remains per unified territory.
        // The survivor's created_at (oldest in the group) is left untouched.
        const survivorInfluence = (influenceById.get(group.survivorId) ?? 1) +
          uniqueAbsorbedIds.reduce((sum, id) => sum + (influenceById.get(id) ?? 1), 0);

        const groupIds = [group.survivorId, ...uniqueAbsorbedIds];

        // influence_level: MAX across the group, never summed. Merging never
        // grants a free fortification level - the survivor inherits the
        // highest level already earned by any member, capped at 15 by the
        // column's own CHECK constraint (a MAX of already-valid values can
        // never exceed that cap by construction).
        const survivorInfluenceLevel = groupIds.reduce(
          (max, id) => Math.max(max, influenceLevelById.get(id) ?? 1),
          1,
        );

        // credits_earned: additive, same rationale as influence above.
        const survivorCreditsEarned = groupIds.reduce(
          (sum, id) => sum + (creditsEarnedById.get(id) ?? 0),
          0,
        );

        // last_active_at: most-recent activity across the merged group, not
        // just the survivor's own value.
        const survivorLastActiveAt = groupIds.reduce<string | null>((max, id) => {
          const v = lastActiveAtById.get(id) ?? null;
          if (!v) return max;
          if (!max || v > max) return v;
          return max;
        }, null);

        // shield_active: the merged zone is shielded if ANY group member was
        // shielded; when so, shield_expires_at is the latest expiry among the
        // shielded members. Otherwise keep the survivor's own (non-shielding)
        // value untouched.
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

        // area_m2: ALWAYS recomputed from the merged geometry (turf area on
        // the merge result). Never sum source areas - overlapping or
        // adjacent zones would double-count shared area.
        const survivorAreaM2 = turfArea(group.geometry);

        zoneGeomJson = JSON.stringify(group.geometry);
        finalZoneId = group.survivorId;
        merged = true;
        absorbedZoneIds = uniqueAbsorbedIds;

        // Atomic write: the survivor aggregate UPDATE and every absorbed-row
        // DELETE happen inside a single Postgres transaction via the
        // apply_zone_merge RPC, so a crash mid-merge can never leave a stale
        // absorbed row alongside an already-updated survivor (or vice versa).
        // No history is kept: absorbed rows are deleted outright inside the
        // RPC, no lineage-tracking column is written.
        const { error: mergeErr } = await supabase.rpc('apply_zone_merge', {
          p_survivor_id: group.survivorId,
          p_absorbed_ids: uniqueAbsorbedIds,
          p_geom_wkt: toWkt(group.geometry),
          p_geom_json: zoneGeomJson,
          p_influence: survivorInfluence,
          p_influence_level: survivorInfluenceLevel,
          p_credits_earned: survivorCreditsEarned,
          p_last_active_at: survivorLastActiveAt,
          p_shield_active: anyShieldActive,
          p_shield_expires_at: survivorShieldExpiresAt,
          p_area_m2: survivorAreaM2,
          p_updated_at: now,
        });
        if (mergeErr) return err(`Zone merge failed: ${mergeErr.message}`, 500);
      }
    }

    if (conqueredId) {
      return ok({
        result: 'conquered',
        zone_id: finalZoneId,
        dispute_resolved: disputeResolved,
        merged,
        absorbed_zone_ids: absorbedZoneIds,
        zone_geom_json: zoneGeomJson,
      });
    }
    if (disputedId) {
      return ok({
        result: 'disputed',
        zone_id: disputedId,
        dispute_resolved: false,
        merged: false,
        absorbed_zone_ids: [],
        zone_geom_json: zoneGeomJson,
      });
    }
    return ok({
      result: 'claimed',
      zone_id: finalZoneId,
      dispute_resolved: disputeResolved,
      merged,
      absorbed_zone_ids: absorbedZoneIds,
      zone_geom_json: zoneGeomJson,
    });

  } catch (e) {
    return err((e as Error).message, 500);
  }
});
