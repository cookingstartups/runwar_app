// supabase/functions/_shared/geometry.ts
// Douglas-Peucker ring simplification, mirroring
// lib/geo/douglas_peucker.dart's simplifyDouglasPeucker exactly (the same
// equirectangular projection centred on the ring's own centroid latitude,
// the same recursive splitting rule, the same epsilon constant - see
// constants.ts's DP_SIMPLIFY_EPSILON_M) so client and server produce
// identical simplified vertex sets for the same raw GPS loop.

/// Simplifies [ring] (a [lng, lat] point list, treated as an open polyline -
/// the first and last vertex are always kept) with the Ramer-Douglas-Peucker
/// algorithm, using [epsilonM] as a perpendicular-distance tolerance in
/// metres.
///
/// Idempotent: simplifying an already-simplified ring with the same epsilon
/// returns the same vertex set, since every remaining segment's max
/// perpendicular deviation is already <= epsilon.
///
/// Returns [ring] unchanged when it has fewer than 3 points - nothing to
/// simplify.
export function simplifyRingDouglasPeucker(ring: number[][], epsilonM: number): number[][] {
  const n = ring.length;
  if (n < 3) return ring;

  let sumLat = 0;
  for (const [, lat] of ring) sumLat += lat;
  const centerLat = sumLat / n;
  const cosLat = Math.cos(centerLat * Math.PI / 180);

  const proj: [number, number][] = ring.map(([lng, lat]) => [lng * 111320 * cosLat, lat * 110540]);

  const keep = new Array<boolean>(n).fill(false);
  keep[0] = true;
  keep[n - 1] = true;
  dpRecurse(proj, 0, n - 1, epsilonM, keep);

  const out: number[][] = [];
  for (let i = 0; i < n; i++) {
    if (keep[i]) out.push(ring[i]);
  }
  return out;
}

function dpRecurse(
  pts: [number, number][],
  first: number,
  last: number,
  epsilonM: number,
  keep: boolean[],
): void {
  if (last <= first + 1) return;

  let maxDist = -1;
  let maxIdx = -1;
  for (let i = first + 1; i < last; i++) {
    const d = perpendicularDistance(pts[i], pts[first], pts[last]);
    if (d > maxDist) {
      maxDist = d;
      maxIdx = i;
    }
  }

  if (maxDist > epsilonM) {
    keep[maxIdx] = true;
    dpRecurse(pts, first, maxIdx, epsilonM, keep);
    dpRecurse(pts, maxIdx, last, epsilonM, keep);
  }
}

// Perpendicular distance (metres, on the projected plane) from [p] to the
// infinite line through [a] and [b] - the standard Douglas-Peucker measure,
// not clamped to the [a, b] segment.
function perpendicularDistance(
  p: [number, number],
  a: [number, number],
  b: [number, number],
): number {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  if (dx === 0 && dy === 0) {
    return Math.hypot(p[0] - a[0], p[1] - a[1]);
  }
  const t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy);
  const projX = a[0] + t * dx;
  const projY = a[1] + t * dy;
  return Math.hypot(p[0] - projX, p[1] - projY);
}
