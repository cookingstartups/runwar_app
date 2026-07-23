// lib/geo/polygon_smoothing.dart
//
// Chaikin corner-cutting for RENDER-ONLY polygon smoothing.
//
// -----------------------------------------------------------------------
// HARD CONSTRAINT - read before calling this from anywhere new
// -----------------------------------------------------------------------
// This function must only ever be called at the point a zone's outline is
// converted into a flutter_map Polygon's `points:` for painting. It must
// NEVER be applied to geometry that is:
//   - passed to computeCapture / detectSelfIntersection in lasso.dart
//   - fed into polygonArea, polygonBboxDiagonalM or any of the four
//     auto-claim gates in run_recorder_service.dart's _scanForAutoClaim
//   - persisted to Supabase, or dispatched in a claim/merge request
//
// Reason: Chaikin corner-cutting is a lossy chord approximation - it always
// cuts area off convex corners, so smoothing stored geometry would silently
// shrink area on every zone and re-tune the 1500 sqm floor, the diagonal
// floor and the compactness ratio out from under the numbers they were
// calibrated against. It would also require the client and the
// claim_territory edge function to run byte-identical smoothing or the two
// sides' claims would desync. None of that is worth it for a purely
// cosmetic fix - see app-T0583.
//
// If a caller ever needs a lighter-weight polygon for payload size rather
// than a nicer-looking one, use Douglas-Peucker instead (drop vertices,
// every survivor stays ON the original path, area drift is bounded by
// epsilon) - not this file.
// -----------------------------------------------------------------------

import 'package:latlong2/latlong.dart';

/// Chaikin corner-cutting on a CLOSED ring (`ring.last` connects back to
/// `ring.first`; the ring must not repeat its first point as its last).
///
/// Each iteration replaces every edge (p0, p1) with two points at [ratio]
/// and (1 - ratio) along that edge, discarding the original vertices. This
/// rounds every corner and roughly quadruples the point count per two
/// iterations. Rings shorter than 3 points, or a non-positive iteration
/// count, are returned unchanged.
List<LatLng> chaikinSmoothClosed(
  List<LatLng> ring, {
  int iterations = 2,
  double ratio = 0.25,
}) {
  if (ring.length < 3 || iterations <= 0) return ring;
  assert(ratio > 0 && ratio < 0.5, 'ratio must keep the two cut points distinct and ordered');

  var pts = ring;
  for (var iter = 0; iter < iterations; iter++) {
    final out = <LatLng>[];
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final p0 = pts[i];
      final p1 = pts[(i + 1) % n];
      out.add(_lerp(p0, p1, ratio));
      out.add(_lerp(p0, p1, 1 - ratio));
    }
    pts = out;
  }
  return pts;
}

LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
