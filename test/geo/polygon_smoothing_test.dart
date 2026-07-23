// test/geo/polygon_smoothing_test.dart
//
// Render-only Chaikin smoothing (lib/geo/polygon_smoothing.dart). Pure
// geometry - no FlutterMap widget involved, so plain test() is fine (see
// flutter-test-patterns.md "When NOT to use testWidgets for map tests").

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/geo/lasso.dart' show polygonArea;
import 'package:runwar_app/geo/polygon_smoothing.dart';

const double _centerLat = 34.700;
const double _centerLng = 33.000;

LatLng _offsetMetres(LatLng base, double dxM, double dyM) {
  final dLat = dyM / 110540.0;
  final dLng = dxM / (111320.0 * math.cos(base.latitude * math.pi / 180.0));
  return LatLng(base.latitude + dLat, base.longitude + dLng);
}

/// A ~60m square with small per-edge zigzags standing in for GPS jitter -
/// 9 points instead of 4 clean corners, each expressed as a metre offset
/// from a single fixed anchor so the whole ring traces one ragged loop
/// around the nominal square path.
List<LatLng> _jitteryCapturedSquare() {
  const half = 30.0; // metres
  const anchor = LatLng(_centerLat, _centerLng);
  const offsetsM = <List<double>>[
    [-half, -half], [-2, -half + 10], [half, -half],
    [half, 2], [half, half], [-3, half - 8],
    [-half, half], [-half, -3], [-half, -half],
  ];
  return [for (final o in offsetsM) _offsetMetres(anchor, o[0], o[1])];
}

void main() {
  group('chaikinSmoothClosed', () {
    test('returns the ring unchanged for iterations <= 0', () {
      final ring = _jitteryCapturedSquare();
      expect(chaikinSmoothClosed(ring, iterations: 0), same(ring));
    });

    test('returns the ring unchanged for fewer than 3 points', () {
      final ring = [const LatLng(_centerLat, _centerLng), const LatLng(_centerLat, _centerLng + 0.001)];
      expect(chaikinSmoothClosed(ring, iterations: 2), same(ring));
    });

    test('quadruples the point count after 2 iterations', () {
      final ring = _jitteryCapturedSquare();
      final smoothed = chaikinSmoothClosed(ring, iterations: 2);
      expect(smoothed.length, ring.length * 4);
    });

    test('smooths a jittery capture without losing enclosed area meaningfully', () {
      final ring = _jitteryCapturedSquare();
      final rawAreaSqm = polygonArea(ring) * 1e6;
      final smoothed = chaikinSmoothClosed(ring, iterations: 2);
      final smoothedAreaSqm = polygonArea(smoothed) * 1e6;

      // Chaikin corner-cutting always shrinks a convex-ish shape somewhat -
      // that is expected - but it must stay a modest fraction of the raw
      // captured area, not silently erase a big chunk of it.
      expect(smoothedAreaSqm, greaterThan(rawAreaSqm * 0.85));
      expect(smoothedAreaSqm, lessThanOrEqualTo(rawAreaSqm));
    });

    test('is a pure function - does not mutate the input ring', () {
      final ring = _jitteryCapturedSquare();
      final copy = List<LatLng>.of(ring);
      chaikinSmoothClosed(ring, iterations: 2);
      expect(ring, orderedEquals(copy));
    });
  });
}
