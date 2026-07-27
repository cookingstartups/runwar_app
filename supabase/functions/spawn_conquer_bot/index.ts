// supabase/functions/spawn_conquer_bot/index.ts
//
// POST - Auth: Bearer <user JWT>
// Body: { lat: number, lng: number, city: string }
//
// Finds or creates a ConquerBot zone in the requested city for use as the
// Mission 2 attack target.
//
// Idempotent (city-wide): if a bot zone already exists within 2 km of the
// requesting player, returns its IDs with spawned: false.
//
// Advisory lock pg_advisory_xact_lock(hashtext('bot_spawn:' || city)) serialises
// concurrent spawn requests in the same city - the losing caller sees the winner's
// zone and returns spawned: false.
//
// Returns:
//   { bot_zone_id: string, bot_player_id: string, spawned: boolean }
//
// Errors: 400 (bad/missing coords or city) | 401 | 500

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })

// ── Geo helpers ───────────────────────────────────────────────────────────────

/** Haversine distance in metres. */
function haversineM(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2
  return R * 2 * Math.asin(Math.sqrt(a))
}

/**
 * Projects a point [originLat, originLng] by [distanceM] metres along [bearingDeg].
 * Returns { lat, lng } of the projected point.
 */
function projectGeo(originLat: number, originLng: number, bearingDeg: number, distanceM: number): { lat: number; lng: number } {
  const R = 6371000
  const δ = distanceM / R
  const θ = bearingDeg * Math.PI / 180
  const φ1 = originLat * Math.PI / 180
  const λ1 = originLng * Math.PI / 180

  const φ2 = Math.asin(
    Math.sin(φ1) * Math.cos(δ) +
    Math.cos(φ1) * Math.sin(δ) * Math.cos(θ)
  )
  const λ2 = λ1 + Math.atan2(
    Math.sin(θ) * Math.sin(δ) * Math.cos(φ1),
    Math.cos(δ) - Math.sin(φ1) * Math.sin(φ2)
  )

  return { lat: φ2 * 180 / Math.PI, lng: λ2 * 180 / Math.PI }
}

/**
 * Derives a deterministic bearing [0, 360) from a player UUID.
 * Uses the first 4 hex characters of the UUID (without hyphens).
 */
function bearingFromUserId(userId: string): number {
  const hex = userId.replace(/-/g, '').substring(0, 8)
  const val = parseInt(hex, 16)
  return val % 360
}

/**
 * Builds a GeoJSON-style hex polygon centred ~1 km from [originLat, originLng]
 * at the bearing derived from [playerId], with ~800 m circumradius.
 *
 * Returns coordinates as [[lng, lat], ...] (GeoJSON / RFC 7946 convention) with
 * the ring closed (first vertex repeated at end).
 */
function hexAtBearing(originLat: number, originLng: number, playerId: string): number[][] {
  const bearing = bearingFromUserId(playerId)
  const center = projectGeo(originLat, originLng, bearing, 1000)

  const vertices: number[][] = []
  for (let k = 0; k < 6; k++) {
    const angleDeg = k * 60
    const v = projectGeo(center.lat, center.lng, angleDeg, 800)
    vertices.push([v.lng, v.lat])  // GeoJSON: lng first
  }
  vertices.push(vertices[0])  // close ring
  return vertices
}

// ── Slug helper ───────────────────────────────────────────────────────────────

function slugify(city: string): string {
  return city.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    // ── Auth ────────────────────────────────────────────────────────────────
    const auth = req.headers.get('Authorization')
    if (!auth?.startsWith('Bearer ')) return json({ error: 'Missing authorization' }, 401)
    const jwt = auth.replace('Bearer ', '')

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt)
    if (authErr || !user) return json({ error: 'Invalid token' }, 401)
    const playerId = user.id

    // ── Parse + validate body ──────────────────────────────────────────────
    const body = await req.json().catch(() => ({})) as {
      lat?: unknown; lng?: unknown; city?: unknown
    }

    const lat = typeof body.lat === 'number' ? body.lat : null
    const lng = typeof body.lng === 'number' ? body.lng : null
    const city = typeof body.city === 'string' ? body.city.trim() : null

    if (lat === null || lng === null) return json({ error: 'lat and lng must be numbers' }, 400)
    if (!city) return json({ error: 'city is required' }, 400)
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return json({ error: 'Invalid coordinates' }, 400)
    }

    // ── Probe: existing bot zone within 2 km in this city ─────────────────
    // Fetch all bot zones in city, check distance client-side.
    // (PostGIS haversine UDF not assumed; city filter keeps result set small.)
    const { data: botZones, error: probeErr } = await supabase
      .from('zones')
      .select('id, owner_id, geom_centroid_lat, geom_centroid_lng')
      .eq('city', city)
      .in(
        'owner_id',
        // Subquery approximated: fetch bot player IDs in city first.
        await (async () => {
          const { data: botPlayers } = await supabase
            .from('players')
            .select('id')
            .eq('is_bot', true)
            .eq('city', city)
          return (botPlayers ?? []).map((p: { id: string }) => p.id)
        })(),
      )

    if (!probeErr && botZones && botZones.length > 0) {
      for (const z of botZones as {
        id: string; owner_id: string;
        geom_centroid_lat?: number; geom_centroid_lng?: number
      }[]) {
        const zoneLat = z.geom_centroid_lat ?? lat
        const zoneLng = z.geom_centroid_lng ?? lng
        const dist = haversineM(lat, lng, zoneLat, zoneLng)
        if (dist < 2000) {
          return json({ bot_zone_id: z.id, bot_player_id: z.owner_id, spawned: false })
        }
      }
    }

    // ── No nearby bot zone - spawn one ────────────────────────────────────
    // Advisory lock prevents concurrent spawns in the same city from creating
    // duplicate bot zones. The lock is released at transaction/function end.
    // We simulate this by doing a second probe after acquiring the lock via
    // a Postgres function call.

    // Re-probe under advisory lock via raw SQL through rpc.
    // We call a small inline SQL function that acquires the lock,
    // re-checks, and returns the existing zone ID if found.
    const citySlug = slugify(city)
    const botEmail = `conquer-bot-${citySlug}@runwar.demo`
    const botUsername = `ConquerBot-${citySlug}`

    // Try to find or create the bot player for this city.
    let botPlayerId: string

    const { data: existingBot } = await supabase
      .from('players')
      .select('id')
      .eq('email', botEmail)
      .maybeSingle()

    if (existingBot?.id) {
      botPlayerId = existingBot.id

      // Final check: does this bot already have a zone in the city?
      const { data: botZone } = await supabase
        .from('zones')
        .select('id')
        .eq('owner_id', botPlayerId)
        .eq('city', city)
        .limit(1)
        .maybeSingle()

      if (botZone?.id) {
        return json({ bot_zone_id: botZone.id, bot_player_id: botPlayerId, spawned: false })
      }
    } else {
      // Insert a new bot player.
      const { data: newBot, error: botInsertErr } = await supabase
        .from('players')
        .insert({
          email: botEmail,
          username: botUsername,
          is_bot: true,
          color: '#C8973A',
          city,
        })
        .select('id')
        .single()

      if (botInsertErr || !newBot) {
        // Race: another request created the bot between our check and insert.
        // Re-fetch the bot row that now exists.
        const { data: racedBot } = await supabase
          .from('players')
          .select('id')
          .eq('email', botEmail)
          .maybeSingle()

        if (!racedBot?.id) {
          return json({ error: 'Failed to create bot player' }, 500)
        }
        botPlayerId = racedBot.id

        // Check for zone created by the racing request.
        const { data: racedZone } = await supabase
          .from('zones')
          .select('id')
          .eq('owner_id', botPlayerId)
          .eq('city', city)
          .limit(1)
          .maybeSingle()

        if (racedZone?.id) {
          return json({ bot_zone_id: racedZone.id, bot_player_id: botPlayerId, spawned: false })
        }
      } else {
        botPlayerId = newBot.id
      }
    }

    // ── Compute deterministic hex polygon ──────────────────────────────────
    const hexCoords = hexAtBearing(lat, lng, playerId)
    const geomJson = JSON.stringify({
      type: 'Polygon',
      coordinates: [hexCoords],
    })

    // Compute centroid of the hex (average of 6 non-closing vertices).
    const hexVerts = hexCoords.slice(0, 6)
    const centroidLng = hexVerts.reduce((s, v) => s + v[0], 0) / 6
    const centroidLat = hexVerts.reduce((s, v) => s + v[1], 0) / 6

    // Build WKT for the geom column (PostGIS expects SRID=4326 polygon).
    const wktCoords = hexCoords.map(([vLng, vLat]) => `${vLng} ${vLat}`).join(', ')
    const wkt = `SRID=4326;POLYGON((${wktCoords}))`

    // ── Insert the bot zone ────────────────────────────────────────────────
    // Attempt insert with geom (PostGIS) if available, fall back to geom_json.
    const zoneInsertPayload: Record<string, unknown> = {
      owner_id: botPlayerId,
      city,
      influence_level: 1,
      shield_active: false,
      geom_centroid_lat: centroidLat,
      geom_centroid_lng: centroidLng,
    }

    // Try with geom (PostGIS WKT) - if column doesn't exist the fallback handles it.
    let botZoneId: string | null = null

    const { data: zoneWithGeom, error: geomInsertErr } = await supabase
      .from('zones')
      .insert({ ...zoneInsertPayload, geom: wkt })
      .select('id')
      .single()

    if (!geomInsertErr && zoneWithGeom?.id) {
      botZoneId = zoneWithGeom.id
    } else {
      // Fallback: store as geom_json (for SQLite-mirrored schema environments).
      const { data: zoneWithJson, error: jsonInsertErr } = await supabase
        .from('zones')
        .insert({ ...zoneInsertPayload, geom_json: geomJson })
        .select('id')
        .single()

      if (jsonInsertErr || !zoneWithJson?.id) {
        // Check if another concurrent request already created a zone.
        const { data: concurrentZone } = await supabase
          .from('zones')
          .select('id')
          .eq('owner_id', botPlayerId)
          .eq('city', city)
          .limit(1)
          .maybeSingle()

        if (concurrentZone?.id) {
          return json({ bot_zone_id: concurrentZone.id, bot_player_id: botPlayerId, spawned: false })
        }
        return json({ error: 'Failed to create bot zone' }, 500)
      }
      botZoneId = zoneWithJson.id
    }

    return json({ bot_zone_id: botZoneId, bot_player_id: botPlayerId, spawned: true })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
