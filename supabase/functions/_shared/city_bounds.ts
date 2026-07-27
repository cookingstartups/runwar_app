// supabase/functions/_shared/city_bounds.ts
// Reads city bounding box from app_config with a 60 s warm-invocation cache.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export interface CityBounds {
  city:  string
  north: number
  south: number
  east:  number
  west:  number
}

const cache    = new Map<string, { bounds: CityBounds; loadedAt: number }>()
const TTL_MS   = 60_000   // 60 s warm-invocation cache

export async function loadCityBounds(
  supabase: SupabaseClient,
  city: string,
): Promise<CityBounds> {
  const hit = cache.get(city)
  if (hit && Date.now() - hit.loadedAt < TTL_MS) return hit.bounds

  const keys = [
    `city_bounds_n_${city}`,
    `city_bounds_s_${city}`,
    `city_bounds_e_${city}`,
    `city_bounds_w_${city}`,
  ]
  const { data, error } = await supabase
    .from('app_config')
    .select('key, value')
    .in('key', keys)
  if (error) throw new Error(`loadCityBounds(${city}): ${error.message}`)

  const map = new Map<string, string>()
  for (const row of data ?? []) map.set(row.key as string, row.value as string)
  for (const k of keys) {
    if (!map.has(k)) throw new Error(`loadCityBounds(${city}): missing config ${k}`)
  }

  const bounds: CityBounds = {
    city,
    north: Number(map.get(`city_bounds_n_${city}`)!),
    south: Number(map.get(`city_bounds_s_${city}`)!),
    east:  Number(map.get(`city_bounds_e_${city}`)!),
    west:  Number(map.get(`city_bounds_w_${city}`)!),
  }
  cache.set(city, { bounds, loadedAt: Date.now() })
  return bounds
}
