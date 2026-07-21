import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:runwar_app/utils/runwar_constants.dart';

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

// Bounding-box diagonal in metres for a polygon (or any point set). Shared by
// the vertex-proximity closure fallback below and by RunRecorderService's
// main auto-claim path, so both diagonal gates use the same projection.
double polygonBboxDiagonalM(List<LatLng> poly) {
  final bbox = polygonBbox(poly);
  return _equirectangularDistanceM(
    LatLng(bbox.minLat, bbox.minLng),
    LatLng(bbox.maxLat, bbox.maxLng),
  );
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
// _equirectangularDistanceM — mirrors the cos-lat projection used by polygonArea
// so that the vertex-proximity threshold scales consistently with the area floor.
// Duplicate of the copy in run_recorder_service.dart; duplication accepted
// (see design.md Section C) to keep both files independently testable.
// ---------------------------------------------------------------------------

double _equirectangularDistanceM(LatLng a, LatLng b) {
  const double latM = 110540.0;
  final double lngM = 111320.0 * math.cos((a.latitude + b.latitude) / 2 * (math.pi / 180.0));
  final double dy = (b.latitude - a.latitude) * latM;
  final double dx = (b.longitude - a.longitude) * lngM;
  return math.sqrt(dx * dx + dy * dy);
}

// ---------------------------------------------------------------------------
// trackDistanceM - total run distance
//
// Sums the great-circle (haversine) distance between every consecutive pair
// of points in a recorded track. Uses haversine rather than the
// equirectangular projection above because a run track can span distances
// where the flat-plane approximation drifts noticeably, and distance_m is a
// user-facing, persisted metric rather than an internal proximity threshold.
// ---------------------------------------------------------------------------

double _haversineDistanceM(LatLng a, LatLng b) {
  const double earthRadiusM = 6371000.0;
  final double lat1 = a.latitude * math.pi / 180;
  final double lat2 = b.latitude * math.pi / 180;
  final double dLat = (b.latitude - a.latitude) * math.pi / 180;
  final double dLng = (b.longitude - a.longitude) * math.pi / 180;
  final double sinLat = math.sin(dLat / 2);
  final double sinLng = math.sin(dLng / 2);
  final double h =
      sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
  return earthRadiusM * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Total great-circle distance in metres over consecutive points in [track].
/// Returns 0 for tracks with fewer than two points.
double trackDistanceM(List<LatLng> track) {
  if (track.length < 2) return 0;
  double total = 0;
  for (int i = 1; i < track.length; i++) {
    total += _haversineDistanceM(track[i - 1], track[i]);
  }
  return total;
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

  // True when this hit came from the vertex-proximity fallback rather than a
  // genuine parametric segment/segment crossing. computeCapture uses this to
  // avoid duplicating the leading vertex of the captured polygon.
  final bool isProximityClosure;

  // True when this hit came from the newest trail segment crossing the edge
  // of a zone the runner already owns, rather than a self-crossing of the
  // trail itself. intersectingSegmentIdx has no meaning for this case (there
  // is no earlier trail segment to anchor it to); callers building the
  // captured polygon must use loopStartTrailIndex as the anchor instead.
  final bool isOwnedZoneWall;

  const SelfIntersection({
    required this.intersectionPoint,
    required this.intersectingSegmentIdx,
    this.isProximityClosure = false,
    this.isOwnedZoneWall = false,
  });
}

SelfIntersection? detectSelfIntersection(
  List<LatLng> trailPoints,
  int loopStartTrailIndex, {
  List<List<LatLng>> ownedZoneEdges = const [],
}) {
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

  // Owned-zone-edge wall pass: tests the newest segment against every edge
  // of every ring supplied in ownedZoneEdges (a caller-pushed snapshot of
  // the runner's own zone outlines - this function never reaches for zone
  // data itself). On a hit, the wall's own vertices are never harvested;
  // only the single computed intersection point is returned, so
  // computeCapture's trail-slice output stays trail-only (no borrowed
  // geometry). intersectingSegmentIdx is a -1 sentinel here since there is
  // no earlier trail segment to anchor to - the caller is expected to use
  // loopStartTrailIndex as computeCapture's anchor instead, mirroring a
  // self-closure's own earliest-in-range index.
  for (final ring in ownedZoneEdges) {
    if (ring.length < 2) continue;
    for (int e = 0; e < ring.length; e++) {
      final edgeA = ring[e];
      final edgeB = ring[(e + 1) % ring.length];
      final pt = segmentSegmentIntersection(edgeA, edgeB, newA, newB);
      if (pt != null) {
        return SelfIntersection(
          intersectionPoint: pt,
          intersectingSegmentIdx: -1,
          isOwnedZoneWall: true,
        );
      }
    }
  }

  // Vertex-proximity pass: catches closures where the newest fix lands on
  // or very near a prior trail vertex (e.g. runner returns to exact start point).
  // The strictly-interior parametric guard (t in (0,1)) inside
  // segmentSegmentIntersection silently drops these; we catch them here.
  // Search range matches the segment scan: vertex[loopStartTrailIndex-1]
  // is the first vertex referenced when i = loopStartTrailIndex.
  //
  // A raw distance check alone fires on ordinary consecutive fixes that
  // happen to pass near an old vertex without enclosing anything (a runner
  // crossing a street they walked minutes earlier). Require the candidate
  // closure to also span a minimum number of trail points and a minimum
  // bounding-box diagonal before treating it as a real loop closure.
  for (int vertexIdx = loopStartTrailIndex - 1; vertexIdx <= k - 2; vertexIdx++) {
    if (_equirectangularDistanceM(trailPoints[vertexIdx], newB) <= kProximityTriggerM) {
      if (k - vertexIdx < kMinProximityClosureTrailPoints) continue;
      final candidate = trailPoints.sublist(vertexIdx, k + 1);
      final diagonal = polygonBboxDiagonalM(candidate);
      if (diagonal < kMinProximityClosureDiagonalM) continue;
      return SelfIntersection(
        intersectionPoint: trailPoints[vertexIdx],
        intersectingSegmentIdx: vertexIdx,
        isProximityClosure: true,
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
  int k, {
  bool isProximityClosure = false,
}) {
  // For a proximity closure, intersectionPoint IS trailPoints[intersectingSegmentIdx]
  // (see detectSelfIntersection), so prepending it again would duplicate the
  // leading vertex. Start the polygon at the vertex itself instead.
  final loop = <LatLng>[if (!isProximityClosure) intersectionPoint];
  for (int idx = intersectingSegmentIdx; idx <= k; idx++) {
    loop.add(trailPoints[idx]);
  }
  return loop;
}
