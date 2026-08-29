// test/geo/douglas_peucker_test.dart
//
// Douglas-Peucker simplification (lib/geo/douglas_peucker.dart). Pure
// geometry - no FlutterMap widget involved, so plain test() is fine (see
// flutter-test-patterns.md "When NOT to use testWidgets for map tests").

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/geo/douglas_peucker.dart';
import 'package:runwar_app/geo/lasso.dart' show polygonArea;
import 'package:runwar_app/utils/runwar_constants.dart' show kDpSimplifyEpsilonM;

const double _centerLat = 34.700;
const double _centerLng = 33.000;

LatLng _offsetMetres(LatLng base, double dxM, double dyM) {
  final dLat = dyM / 110540.0;
  final dLng = dxM / (111320.0 * math.cos(base.latitude * math.pi / 180.0));
  return LatLng(base.latitude + dLat, base.longitude + dLng);
}

void main() {
  group('simplifyDouglasPeucker', () {
    test('returns the input unchanged for fewer than 3 points', () {
      final ring = [
        const LatLng(_centerLat, _centerLng),
        const LatLng(_centerLat, _centerLng + 0.001),
      ];
      expect(simplifyDouglasPeucker(ring), same(ring));
    });

    test('a zigzag with sub-epsilon deviations collapses to its endpoints', () {
      // A near-straight 100 m line with mid-points jittered a few metres off
      // the true path - well under the 10 m epsilon - must collapse to
      // exactly its two endpoints.
      const anchor = LatLng(_centerLat, _centerLng);
      final line = <LatLng>[
        _offsetMetres(anchor, 0, 0),
        _offsetMetres(anchor, 25, 3),
        _offsetMetres(anchor, 50, -4),
        _offsetMetres(anchor, 75, 2),
        _offsetMetres(anchor, 100, 0),
      ];
      final simplified = simplifyDouglasPeucker(line, epsilonM: 10.0);
      expect(simplified.length, 2);
      expect(simplified.first, line.first);
      expect(simplified.last, line.last);
    });

    test('an L-shaped corner with a deviation over epsilon is preserved', () {
      // Straight run of 100 m east, then a hard turn 100 m north - the
      // midpoint's true perpendicular deviation from the straight
      // start-to-end chord is large (tens of metres), well over the 10 m
      // epsilon, so the corner vertex must survive simplification.
      const anchor = LatLng(_centerLat, _centerLng);
      final corner = <LatLng>[
        _offsetMetres(anchor, 0, 0),
        _offsetMetres(anchor, 50, 0),
        _offsetMetres(anchor, 100, 0),
        _offsetMetres(anchor, 100, 50),
        _offsetMetres(anchor, 100, 100),
      ];
      final simplified = simplifyDouglasPeucker(corner, epsilonM: 10.0);
      expect(simplified.length, 3);
      expect(simplified.first, corner.first);
      expect(simplified.last, corner.last);
      expect(simplified[1], corner[2]); // the corner vertex itself
    });

    test('idempotent: simplifying twice yields the same result', () {
      const half = 30.0; // metres
      const anchor = LatLng(_centerLat, _centerLng);
      const offsetsM = <List<double>>[
        [-half, -half], [-2, -half + 10], [half, -half],
        [half, 2], [half, half], [-3, half - 8],
        [-half, half], [-half, -3], [-half, -half],
      ];
      final ring = [for (final o in offsetsM) _offsetMetres(anchor, o[0], o[1])];

      final once = simplifyDouglasPeucker(ring, epsilonM: 10.0);
      final twice = simplifyDouglasPeucker(once, epsilonM: 10.0);
      expect(twice, orderedEquals(once));
    });

    test(
        'a noisy ~100-point block loop reduces to close to 4-8 vertices '
        'while area stays within 10% of the true clean shape', () {
      // A 60 m x 60 m rectangle traced with dense GPS-jitter noise (+/-7 m
      // on both axes) around each of ~100 points along its perimeter.
      const anchor = LatLng(_centerLat, _centerLng);
      const w = 60.0, h = 60.0;
      const perPointsPerEdge = 25;
      final rng = math.Random(7);

      double jitter() => (rng.nextDouble() * 6.0) - 3.0; // +/- 3 m

      final corners = <List<double>>[
        [0, 0],
        [w, 0],
        [w, h],
        [0, h],
      ];
      final noisy = <LatLng>[];
      for (var edge = 0; edge < 4; edge++) {
        final a = corners[edge];
        final b = corners[(edge + 1) % 4];
        for (var i = 0; i < perPointsPerEdge; i++) {
          final t = i / perPointsPerEdge;
          final x = a[0] + (b[0] - a[0]) * t + jitter();
          final y = a[1] + (b[1] - a[1]) * t + jitter();
          noisy.add(_offsetMetres(anchor, x, y));
        }
      }
      expect(noisy.length, 100);

      // Compared against the TRUE clean rectangle's area, not the raw noisy
      // polygon's own area - the raw polygon's area is itself jittery (its
      // vertices wander off the true edge), so it is not a stable baseline.
      // What matters is that simplification recovers something close to the
      // shape the runner actually ran, not that it merely preserves
      // whatever noise happened to be in the raw capture.
      const trueAreaSqm = w * h;
      final simplified = simplifyDouglasPeucker(noisy, epsilonM: kDpSimplifyEpsilonM);
      final simplifiedAreaSqm = polygonArea(simplified) * 1e6;

      expect(simplified.length, greaterThanOrEqualTo(4));
      expect(simplified.length, lessThanOrEqualTo(8));

      final areaDriftFraction =
          (simplifiedAreaSqm - trueAreaSqm).abs() / trueAreaSqm;
      expect(areaDriftFraction, lessThan(0.1));
    });

    test('is a pure function - does not mutate the input list', () {
      const anchor = LatLng(_centerLat, _centerLng);
      final ring = [
        _offsetMetres(anchor, 0, 0),
        _offsetMetres(anchor, 25, 3),
        _offsetMetres(anchor, 50, -4),
        _offsetMetres(anchor, 75, 2),
        _offsetMetres(anchor, 100, 0),
      ];
      final copy = List<LatLng>.of(ring);
      simplifyDouglasPeucker(ring, epsilonM: 10.0);
      expect(ring, orderedEquals(copy));
    });
  });
}
