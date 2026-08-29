// lib/geo/douglas_peucker.dart
//
// Douglas-Peucker polyline simplification, used to reduce a closed GPS
// capture loop to its geometrically significant vertices before that loop
// is persisted as a zone's stored geometry - see kDpSimplifyEpsilonM's doc
// comment in lib/utils/runwar_constants.dart for the full contract (single
// epsilon, mirrored server-side in
// supabase/functions/_shared/geometry.ts's simplifyRingDouglasPeucker).
//
// Unlike lib/geo/polygon_smoothing.dart's Chaikin corner-cutting (a lossy
// chord approximation - see that file's own hard-constraint comment), every
// surviving vertex here stays exactly ON the original path and area drift
// is bounded by epsilon, which is why this is the algorithm that file's own
// doc comment names as the safe choice for a lighter-weight polygon that
// still feeds gates and storage.
//
// Both language implementations must stay structurally identical: the same
// equirectangular projection around the ring's own centroid (not per-point
// latitude, so a single flat projection is used for the whole ring's
// perpendicular-distance test), the same recursive splitting rule, and the
// same epsilon constant name pointing at its mirror.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../utils/runwar_constants.dart' show kDpSimplifyEpsilonM;

/// Simplifies [points] (an open polyline - first and last vertex are always
/// kept) with the Ramer-Douglas-Peucker algorithm, treating [epsilonM] as a
/// perpendicular-distance tolerance in metres.
///
/// Distances are computed on an equirectangular projection centred on the
/// ring's own centroid latitude, not on raw lat/lng degrees - a degree of
/// longitude shrinks with latitude, so an unprojected epsilon would not mean
/// the same physical distance at different latitudes.
///
/// Idempotent: simplifying an already-simplified ring with the same epsilon
/// returns the same vertex set, since every remaining segment's max
/// perpendicular deviation is already <= epsilon.
///
/// Returns [points] unchanged when it has fewer than 3 vertices - nothing to
/// simplify.
List<LatLng> simplifyDouglasPeucker(
  List<LatLng> points, {
  double epsilonM = kDpSimplifyEpsilonM,
}) {
  if (points.length < 3) return points;

  final n = points.length;
  final centerLat =
      points.map((p) => p.latitude).reduce((a, b) => a + b) / n;
  final cosLat = math.cos(centerLat * math.pi / 180.0);

  final proj = <math.Point<double>>[
    for (final p in points)
      math.Point<double>(p.longitude * 111320.0 * cosLat, p.latitude * 110540.0),
  ];

  final keep = List<bool>.filled(n, false);
  keep[0] = true;
  keep[n - 1] = true;
  _dpRecurse(proj, 0, n - 1, epsilonM, keep);

  return [for (var i = 0; i < n; i++) if (keep[i]) points[i]];
}

void _dpRecurse(
  List<math.Point<double>> pts,
  int first,
  int last,
  double epsilonM,
  List<bool> keep,
) {
  if (last <= first + 1) return;

  var maxDist = -1.0;
  var maxIdx = -1;
  for (var i = first + 1; i < last; i++) {
    final d = _perpendicularDistance(pts[i], pts[first], pts[last]);
    if (d > maxDist) {
      maxDist = d;
      maxIdx = i;
    }
  }

  if (maxDist > epsilonM) {
    keep[maxIdx] = true;
    _dpRecurse(pts, first, maxIdx, epsilonM, keep);
    _dpRecurse(pts, maxIdx, last, epsilonM, keep);
  }
}

/// Perpendicular distance (metres, on the projected plane) from [p] to the
/// infinite line through [a] and [b] - the standard Douglas-Peucker measure,
/// not clamped to the [a, b] segment.
double _perpendicularDistance(
  math.Point<double> p,
  math.Point<double> a,
  math.Point<double> b,
) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  if (dx == 0 && dy == 0) {
    return math.sqrt(math.pow(p.x - a.x, 2) + math.pow(p.y - a.y, 2));
  }
  final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy);
  final projX = a.x + t * dx;
  final projY = a.y + t * dy;
  return math.sqrt(math.pow(p.x - projX, 2) + math.pow(p.y - projY, 2));
}
