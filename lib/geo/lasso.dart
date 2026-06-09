import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

// ---------------------------------------------------------------------------
// GPS Lasso — Dart port of geo.ts
// Coordinate convention: LatLng.latitude = lat (index 0 in TS),
//                        LatLng.longitude = lng (index 1 in TS).
// ---------------------------------------------------------------------------

const double _eps = 1e-12;

// ---------------------------------------------------------------------------
// Bounding box helpers
// ---------------------------------------------------------------------------

class BBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const BBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });
}

BBox polygonBbox(List<LatLng> poly) {
  double minLat = double.infinity;
  double maxLat = double.negativeInfinity;
  double minLng = double.infinity;
  double maxLng = double.negativeInfinity;
  for (final p in poly) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  return BBox(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
}

bool pointInBbox(double lat, double lng, BBox bbox) {
  return lat >= bbox.minLat &&
      lat <= bbox.maxLat &&
      lng >= bbox.minLng &&
      lng <= bbox.maxLng;
}

// ---------------------------------------------------------------------------
// polygonArea — shoelace formula with lat/lng → metre projection
// Returns area in km².
// ---------------------------------------------------------------------------

double polygonArea(List<LatLng> poly) {
  final n = poly.length;
  if (n < 3) return 0;
  double sum = 0;
  for (int i = 0; i < n; i++) {
    final p1 = poly[i];
    final p2 = poly[(i + 1) % n];
    final lat1 = p1.latitude;
    final lng1 = p1.longitude;
    final lat2 = p2.latitude;
    final lng2 = p2.longitude;
    final x1 = lng1 * 111320 * math.cos(lat1 * (math.pi / 180));
    final y1 = lat1 * 110540;
    final x2 = lng2 * 111320 * math.cos(lat2 * (math.pi / 180));
    final y2 = lat2 * 110540;
    sum += x1 * y2 - x2 * y1;
  }
  return (sum / 2).abs() / 1e6;
}

// ---------------------------------------------------------------------------
// Sutherland-Hodgman clip by a single directed edge e0→e1
// ---------------------------------------------------------------------------

List<LatLng> _clipByEdge(List<LatLng> poly, LatLng e0, LatLng e1) {
  if (poly.isEmpty) return [];

  bool inside(LatLng p) =>
      (e1.latitude - e0.latitude) * (p.longitude - e0.longitude) -
          (e1.longitude - e0.longitude) * (p.latitude - e0.latitude) >=
      0;

  LatLng intersect(LatLng a, LatLng b) {
    final dLat1 = b.latitude - a.latitude;
    final dLng1 = b.longitude - a.longitude;
    final dLat2 = e1.latitude - e0.latitude;
    final dLng2 = e1.longitude - e0.longitude;
    final denom = dLat1 * dLng2 - dLng1 * dLat2;
    if (denom.abs() < 1e-12) return a;
    final t =
        ((e0.latitude - a.latitude) * dLng2 - (e0.longitude - a.longitude) * dLat2) / denom;
    return LatLng(a.latitude + t * dLat1, a.longitude + t * dLng1);
  }

  final out = <LatLng>[];
  for (int i = 0; i < poly.length; i++) {
    final cur = poly[i];
    final prev = poly[(i + poly.length - 1) % poly.length];
    final curIn = inside(cur);
    final prevIn = inside(prev);
    if (curIn) {
      if (!prevIn) out.add(intersect(prev, cur));
      out.add(cur);
    } else if (prevIn) {
      out.add(intersect(prev, cur));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// polygonIntersection — Sutherland-Hodgman; returns null when empty
// ---------------------------------------------------------------------------

List<LatLng>? polygonIntersection(List<LatLng> a, List<LatLng> b) {
  var result = List<LatLng>.of(a);
  for (int i = 0; i < b.length; i++) {
    result = _clipByEdge(result, b[i], b[(i + 1) % b.length]);
    if (result.isEmpty) return null;
  }
  return result.length >= 3 ? result : null;
}

// ---------------------------------------------------------------------------
// polygonDifference — Sutherland-Hodgman with reversed clip polygon
// ---------------------------------------------------------------------------

List<LatLng> polygonDifference(List<LatLng> subject, List<LatLng> clip) {
  final reversed = List<LatLng>.of(clip).reversed.toList();
  var result = List<LatLng>.of(subject);
  for (int i = 0; i < reversed.length; i++) {
    result = _clipByEdge(result, reversed[i], reversed[(i + 1) % reversed.length]);
    if (result.isEmpty) return [];
  }
  return result;
}

// ---------------------------------------------------------------------------
// pointInPolygon — ray-casting algorithm
// ---------------------------------------------------------------------------

bool pointInPolygon(LatLng pt, List<LatLng> poly) {
  final lat = pt.latitude;
  final lng = pt.longitude;
  bool inside = false;
  int j = poly.length - 1;
  for (int i = 0; i < poly.length; j = i++) {
    final ilat = poly[i].latitude;
    final ilng = poly[i].longitude;
    final jlat = poly[j].latitude;
    final jlng = poly[j].longitude;
    final cross = (ilng > lng) != (jlng > lng) &&
        lat < ((jlat - ilat) * (lng - ilng)) / (jlng - ilng) + ilat;
    if (cross) inside = !inside;
  }
  return inside;
}

// ---------------------------------------------------------------------------
// segmentSegmentIntersection
//
// Parametric segment-segment intersection in lat/lng space (treated as planar
// for short distances < a few km; sufficient for city-scale GPS territory).
// Returns intersection point when t is strictly in (0, 1) and u is in (0, 1].
// Allowing u == 1 means a GPS endpoint that lands exactly on a prior segment
// is detected as a valid lasso closure. Collinear-overlap returns null.
// ---------------------------------------------------------------------------

LatLng? segmentSegmentIntersection(
  LatLng a,
  LatLng b,
  LatLng c,
  LatLng d,
) {
  final r0 = b.latitude - a.latitude;
  final r1 = b.longitude - a.longitude;
  final s0 = d.latitude - c.latitude;
  final s1 = d.longitude - c.longitude;
  final denom = r0 * s1 - r1 * s0;
  if (denom.abs() < _eps) return null; // parallel / collinear
  final t = ((c.latitude - a.latitude) * s1 - (c.longitude - a.longitude) * s0) / denom;
  final u = ((c.latitude - a.latitude) * r1 - (c.longitude - a.longitude) * r0) / denom;
  if (t <= 0 || t >= 1 || u <= 0 || u > 1) return null;
  return LatLng(a.latitude + t * r0, a.longitude + t * r1);
}

// ---------------------------------------------------------------------------
// detectSelfIntersection
//
// Scans the trail for a self-intersection starting from loopStartTrailIndex.
// Only tests the newest segment (k-1 → k) against prior segments
// [loopStartTrailIndex .. k-2]. Anti-backtrack guard is encoded in the
// upper bound (i <= k-2 skips the immediately preceding segment i=k-1).
// Returns { intersectionPoint, intersectingSegmentIdx } or null.
// ---------------------------------------------------------------------------

class SelfIntersection {
  final LatLng intersectionPoint;
  final int intersectingSegmentIdx;

  const SelfIntersection({
    required this.intersectionPoint,
    required this.intersectingSegmentIdx,
  });
}

SelfIntersection? detectSelfIntersection(
  List<LatLng> trailPoints,
  int loopStartTrailIndex,
) {
  final k = trailPoints.length - 1;
  if (k < 2) return null;
  if (loopStartTrailIndex < 1 || k - 1 < loopStartTrailIndex) return null;

  final newA = trailPoints[k - 1];
  final newB = trailPoints[k];

  for (int i = loopStartTrailIndex; i <= k - 2; i++) {
    final segA = trailPoints[i - 1];
    final segB = trailPoints[i];
    final pt = segmentSegmentIntersection(segA, segB, newA, newB);
    if (pt != null) {
      return SelfIntersection(
        intersectionPoint: pt,
        intersectingSegmentIdx: i,
      );
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// computeCapture
//
// Extracts the captured polygon at the moment of self-intersection.
// Polygon: intersectionPoint → trailPoints[intersectingSegmentIdx] → ... → trailPoints[k].
// The transit-pole (everything before intersectingSegmentIdx) is excluded.
// ---------------------------------------------------------------------------

List<LatLng> computeCapture(
  List<LatLng> trailPoints,
  int loopStartTrailIndex, // unused (_); kept for API parity with geo.ts
  int intersectingSegmentIdx,
  LatLng intersectionPoint,
  int k,
) {
  final loop = <LatLng>[intersectionPoint];
  for (int idx = intersectingSegmentIdx; idx <= k; idx++) {
    loop.add(trailPoints[idx]);
  }
  return loop;
}
