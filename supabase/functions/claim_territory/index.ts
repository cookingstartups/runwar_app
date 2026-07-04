import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
// Type-only import here (erased at compile time); the runtime binding is
// loaded lazily below, strictly inside the `if (!disputedId)` guard, so the
// merge routine can never execute on a disputed outcome.
import type { ZoneInput } from './merge_geometry.ts';

// Zone-unify edge-to-edge threshold, matching kProximityTriggerM (the same
// 25 m radius used for loop-closure proximity triggering). A same-owner,
// same-city zone within this distance is still plausibly the same continuous
// run and merges into one zone identity (Tier 1/Tier 2); beyond it, zones
// stay separate rows (Tier 3).
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
// pre-merge insert shape) or a merge-result geometry object (Polygon or
// MultiPolygon, per the three-tier merge contract). Branches on `geometry.type`
// so a Tier-2 MultiPolygon merge result stays representable in the widened
// `zones.geom GEOMETRY(Geometry,4326)` column.
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

// A zone's geom_json may be a Polygon (never merged) or a MultiPolygon (a
// prior Tier-2 merge survivor). Returns every member outline as its own ring
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

    // Total track length gate — must be at least 200 m
    let totalDist = 0;
    for (let i = 1; i < coords.length; i++) {
      const [lng1, lat1] = coords[i - 1];
      const [lng2, lat2] = coords[i];
      totalDist += haversineM(lat1, lng1, lat2, lng2);
    }
    if (totalDist < 200) return ok({ result: 'failed', reason: 'too_short' });

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
        // MultiPolygon-aware: a prior Tier-2 merge survivor stores 2+ member
        // outlines. Each one is tested independently below (OR-combined) so
        // an overlap against ANY member outline is detected, not just the
        // first one misread as a flat ring.
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
        .select('id, geom_json, created_at, influence')
        .eq('owner_id', playerId)
        .eq('city', city)
        .eq('status', 'owned')
        .order('created_at', { ascending: true });

      const influenceById = new Map<string, number>();
      const inputs: ZoneInput[] = (candidateRows ?? [])
        .map((r) => {
          influenceById.set(r.id as string, (r.influence as number | null) ?? 1);
          const geom = typeof r.geom_json === 'string' ? JSON.parse(r.geom_json) : r.geom_json;
          // A survivor of a prior Tier-2 merge stores 2+ member outlines; feed
          // each one back in as its own ZoneInput ring (same db row id) so a
          // later claim can still test contiguity against each piece
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

        zoneGeomJson = JSON.stringify(group.geometry);
        finalZoneId = group.survivorId;
        merged = true;
        absorbedZoneIds = uniqueAbsorbedIds;

        await supabase.from('zones').update({
          geom_json: zoneGeomJson,
          geom: toWkt(group.geometry),
          influence: survivorInfluence,
          updated_at: now,
        }).eq('id', group.survivorId);

        for (const absorbedId of uniqueAbsorbedIds) {
          await supabase.from('zones').delete().eq('id', absorbedId);
        }
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
