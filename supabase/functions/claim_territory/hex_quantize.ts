// supabase/functions/claim_territory/hex_quantize.ts
//
// Server-side TypeScript port of lib/geo/hex_quantize.dart's shared-reference
// hex-grid quantisation. Same grid parameters (pointy-top axial hexes,
// kHexCellCircumradiusM below must stay numerically equal to
// kHexCellCircumradiusM in lib/utils/runwar_constants.dart), same
// equirectangular projection anchored at the global (lat=0, lng=0) origin
// with a per-call reference latitude, same "cell center inside polygon"
// containment rule, same edge-cancellation dissolve. Ported rather than
// shared via a build step because the Dart module lives in the Flutter app
// and this module runs in a Deno edge function - there is no code-sharing
// mechanism between the two runtimes today, so the two copies are kept in
// numeric lockstep by convention (see the doc comment on
// kHexCellCircumradiusM below) rather than by a single source file.
//
// Used by computeZoneSplit (merge_geometry.ts, app-T0587) to snap a
// zone-split cut to the nearest shared-grid cell boundary instead of relying
// on a raw-geometry area floor to reject slivers. Quantising both the
// existing zone's stored ring and the incoming re-run's ring to this same
// grid bounds the snap's displacement to at most one cell's extent
// (circumradiusM) from the true GPS cut, and - critically - makes repeated
// re-splits of the same ground converge on the same cell boundaries instead
// of drifting with each re-run's own GPS noise.

// Must stay numerically equal to kHexCellCircumradiusM in
// lib/utils/runwar_constants.dart. Currently 10 m, PROVISIONAL pending a
// @game-theory pass (same caveat as the Dart constant).
export const kHexCellCircumradiusM = 10.0;

const SQRT3 = 1.7320508075688772;
const LAT_SCALE = 110540.0;

export interface HexCell {
  q: number;
  r: number;
}

function hexCellKey(cell: HexCell): string {
  return `${cell.q},${cell.r}`;
}

interface Pt {
  x: number;
  y: number;
}

interface Bbox {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

function ringBbox(ring: number[][]): Bbox {
  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const [lng, lat] of ring) {
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }
  return { minLat, maxLat, minLng, maxLng };
}

function bboxCenterLat(ring: number[][]): number {
  const b = ringBbox(ring);
  return (b.minLat + b.maxLat) / 2;
}

// Ray-casting point-in-polygon, [lng, lat] pairs. Ring need not be closed.
function pointInPolygon(lng: number, lat: number, ring: number[][]): boolean {
  let inside = false;
  const n = ring.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    const intersects = yi > lat !== yj > lat &&
      lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi;
    if (intersects) inside = !inside;
  }
  return inside;
}

// A local instance of the shared hex grid, parameterised by cell size and
// the equirectangular reference latitude used for this call's projection.
// Mirrors HexGrid in lib/geo/hex_quantize.dart exactly.
class HexGrid {
  readonly circumradiusM: number;
  readonly refLatDeg: number;

  constructor(circumradiusM: number, refLatDeg: number) {
    this.circumradiusM = circumradiusM;
    this.refLatDeg = refLatDeg;
  }

  private get lngScale(): number {
    return 111320.0 * Math.cos((this.refLatDeg * Math.PI) / 180.0);
  }

  private project(lng: number, lat: number): Pt {
    return { x: lng * this.lngScale, y: lat * LAT_SCALE };
  }

  private unproject(p: Pt): [number, number] {
    return [p.x / this.lngScale, p.y / LAT_SCALE]; // [lng, lat]
  }

  private centerXY(cell: HexCell): Pt {
    return {
      x: this.circumradiusM * (SQRT3 * cell.q + (SQRT3 / 2) * cell.r),
      y: this.circumradiusM * (1.5 * cell.r),
    };
  }

  cellAt(lng: number, lat: number): HexCell {
    const p = this.project(lng, lat);
    const qf = ((SQRT3 / 3) * p.x - (1 / 3) * p.y) / this.circumradiusM;
    const rf = ((2.0 / 3.0) * p.y) / this.circumradiusM;
    return roundAxial(qf, rf);
  }

  cellCenter(cell: HexCell): [number, number] {
    return this.unproject(this.centerXY(cell));
  }

  cellCorners(cell: HexCell): [number, number][] {
    const c = this.centerXY(cell);
    const corners: [number, number][] = [];
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 180.0) * (60 * i - 30);
      const x = c.x + this.circumradiusM * Math.cos(angle);
      const y = c.y + this.circumradiusM * Math.sin(angle);
      corners.push(this.unproject({ x, y }));
    }
    return corners;
  }

  // Every hex cell whose CENTER falls inside `ring`, deterministically
  // ordered (r, then q) so identical covered-cell sets always dissolve to
  // the same output regardless of which raw trace produced them.
  coveredCells(ring: number[][]): HexCell[] {
    if (ring.length < 3) return [];
    const bbox = ringBbox(ring);
    const corners: [number, number][] = [
      [bbox.minLng, bbox.minLat],
      [bbox.maxLng, bbox.minLat],
      [bbox.minLng, bbox.maxLat],
      [bbox.maxLng, bbox.maxLat],
    ];
    let minQ = Infinity, maxQ = -Infinity, minR = Infinity, maxR = -Infinity;
    for (const [lng, lat] of corners) {
      const cell = this.cellAt(lng, lat);
      if (cell.q < minQ) minQ = cell.q;
      if (cell.q > maxQ) maxQ = cell.q;
      if (cell.r < minR) minR = cell.r;
      if (cell.r > maxR) maxR = cell.r;
    }
    const margin = 2;
    const out: HexCell[] = [];
    for (let r = minR - margin; r <= maxR + margin; r++) {
      for (let q = minQ - margin; q <= maxQ + margin; q++) {
        const cell = { q, r };
        const [lng, lat] = this.cellCenter(cell);
        if (pointInPolygon(lng, lat, ring)) out.push(cell);
      }
    }
    out.sort((a, b) => (a.r !== b.r ? a.r - b.r : a.q - b.q));
    return out;
  }

  // Dissolves a set of covered cells into the boundary ring(s) of their
  // union, by cancelling every hex edge shared by two covered cells and
  // stitching the surviving (single-owner) edges into closed rings.
  dissolveBoundary(cells: HexCell[]): number[][][] {
    if (cells.length === 0) return [];

    const key = (p: [number, number]) => `${p[1].toFixed(9)},${p[0].toFixed(9)}`;

    const pointByKey = new Map<string, [number, number]>();
    const survivingEdges = new Set<string>();

    for (const cell of cells) {
      const corners = this.cellCorners(cell);
      for (let i = 0; i < 6; i++) {
        const a = corners[i];
        const b = corners[(i + 1) % 6];
        const ka = key(a);
        const kb = key(b);
        pointByKey.set(ka, a);
        pointByKey.set(kb, b);
        const fwd = `${ka}|${kb}`;
        const rev = `${kb}|${ka}`;
        if (survivingEdges.has(rev)) {
          survivingEdges.delete(rev);
        } else {
          survivingEdges.add(fwd);
        }
      }
    }

    const next = new Map<string, string>();
    for (const e of survivingEdges) {
      const [a, b] = e.split('|');
      next.set(a, b);
    }

    const rings: number[][][] = [];
    const visited = new Set<string>();
    for (const startKey of next.keys()) {
      if (visited.has(startKey)) continue;
      const ring: number[][] = [];
      let cur = startKey;
      while (!visited.has(cur)) {
        visited.add(cur);
        ring.push(pointByKey.get(cur)!);
        const nxt = next.get(cur);
        if (nxt === undefined) break;
        cur = nxt;
      }
      if (ring.length >= 3) rings.push(ring);
    }
    return rings;
  }
}

function roundAxial(qf: number, rf: number): HexCell {
  const xf = qf, zf = rf, yf = -xf - zf;
  let rx = Math.round(xf), ry = Math.round(yf), rz = Math.round(zf);
  const xDiff = Math.abs(rx - xf), yDiff = Math.abs(ry - yf), zDiff = Math.abs(rz - zf);
  if (xDiff > yDiff && xDiff > zDiff) {
    rx = -ry - rz;
  } else if (yDiff > zDiff) {
    ry = -rx - rz;
  } else {
    rz = -rx - ry;
  }
  return { q: rx, r: rz };
}

/// The set of hex cells (as a Map keyed by "q,r" for O(1) membership tests)
/// covered by `ring`, at `circumradiusM` resolution and `refLatDeg`
/// reference latitude.
export function coveredCellSet(
  ring: number[][],
  circumradiusM: number,
  refLatDeg: number,
): Map<string, HexCell> {
  const grid = new HexGrid(circumradiusM, refLatDeg);
  const cells = grid.coveredCells(ring);
  const out = new Map<string, HexCell>();
  for (const c of cells) out.set(hexCellKey(c), c);
  return out;
}

/// Cells present in `a` but not in `b` (plain set difference by q,r key).
export function cellSetDifference(
  a: Map<string, HexCell>,
  b: Map<string, HexCell>,
): HexCell[] {
  const out: HexCell[] = [];
  for (const [k, cell] of a) {
    if (!b.has(k)) out.push(cell);
  }
  return out;
}

/// Dissolves `cells` into ring(s) tracing the boundary of their union, at
/// the same grid resolution/reference latitude they were covered at.
export function dissolveCells(
  cells: HexCell[],
  circumradiusM: number,
  refLatDeg: number,
): number[][][] {
  const grid = new HexGrid(circumradiusM, refLatDeg);
  return grid.dissolveBoundary(cells);
}

export { bboxCenterLat };
