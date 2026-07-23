// test/geo/hex_quantize_test.dart
//
// Multi-user geometry convergence (lib/geo/hex_quantize.dart). Pure
// geometry - no FlutterMap widget involved, so plain test() is fine (see
// flutter-test-patterns.md "When NOT to use testWidgets for map tests").

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/geo/hex_quantize.dart';
import 'package:runwar_app/geo/lasso.dart' show polygonArea;

const double _centerLat = 34.700;
const double _centerLng = 33.000;

LatLng _offsetMetres(LatLng base, double dxM, double dyM) {
  final dLat = dyM / 110540.0;
  final dLng = dxM / (111320.0 * math.cos(base.latitude * math.pi / 180.0));
  return LatLng(base.latitude + dLat, base.longitude + dLng);
}

/// Nominal 60m x 60m square (well over kHexCellCircumradiusM's default
/// 10 m, so several cells span it), centered on [center], with each corner
/// nudged by [jitterM] - a stand-in for one device's independent GPS trace
/// of "the same" real block.
List<LatLng> _tracedSquare(LatLng center, List<List<double>> jitterM) {
  const half = 30.0; // metres
  const corners = <List<double>>[
    [-half, -half],
    [half, -half],
    [half, half],
    [-half, half],
  ];
  return [
    for (var i = 0; i < corners.length; i++)
      _offsetMetres(
        center,
        corners[i][0] + jitterM[i][0],
        corners[i][1] + jitterM[i][1],
      ),
  ];
}

void main() {
  const center = LatLng(_centerLat, _centerLng);

  group('quantizePolygonToHexGrid', () {
    test('returns empty for a degenerate (< 3 point) polygon', () {
      expect(
        quantizePolygonToHexGrid([center, _offsetMetres(center, 5, 0)]),
        isEmpty,
      );
    });

    test('two independently-jittered traces of the same real square '
        'converge on the identical quantized ring', () {
      // Two devices, two different small (well under the 10 m cell
      // circumradius) GPS noise patterns around the same nominal square.
      final traceA = _tracedSquare(center, const [
        [-1.5, 0.8], [0.9, -1.2], [-0.6, 1.1], [1.3, -0.4],
      ]);
      final traceB = _tracedSquare(center, const [
        [1.1, -0.7], [-1.4, 0.6], [0.7, -0.9], [-0.8, 1.4],
      ]);

      // Both quantised against the same shared reference latitude - the
      // real multi-device guarantee needs a fixed regional reference, not
      // each capture's own (near-identical but not bit-identical) bbox
      // center. See hex_quantize.dart's module doc.
      final quantizedA = quantizePolygonToHexGrid(traceA, referenceLatitudeDeg: _centerLat);
      final quantizedB = quantizePolygonToHexGrid(traceB, referenceLatitudeDeg: _centerLat);

      expect(quantizedA, isNotEmpty);
      expect(quantizedA.length, quantizedB.length, reason: 'same number of boundary rings');
      for (var i = 0; i < quantizedA.length; i++) {
        expect(quantizedA[i], orderedEquals(quantizedB[i]),
            reason: 'ring $i must be byte-identical between the two traces');
      }
    });

    test('also converges using the auto-derived (per-call bbox center) '
        'reference latitude, since both traces sit at nearly the same spot', () {
      final traceA = _tracedSquare(center, const [
        [-1.0, 1.0], [1.0, -1.0], [-1.0, 1.0], [1.0, -1.0],
      ]);
      final traceB = _tracedSquare(center, const [
        [0.5, -0.5], [-0.5, 0.5], [0.5, -0.5], [-0.5, 0.5],
      ]);

      final quantizedA = quantizePolygonToHexGrid(traceA);
      final quantizedB = quantizePolygonToHexGrid(traceB);

      expect(quantizedA, isNotEmpty);
      expect(quantizedA.length, quantizedB.length);
      for (var i = 0; i < quantizedA.length; i++) {
        expect(quantizedA[i], orderedEquals(quantizedB[i]));
      }
    });

    test('quantized area stays close to the nominal captured area', () {
      final trace = _tracedSquare(center, const [
        [-1.5, 0.8], [0.9, -1.2], [-0.6, 1.1], [1.3, -0.4],
      ]);
      final nominalAreaSqm = polygonArea(trace) * 1e6;

      final quantized = quantizePolygonToHexGrid(trace, referenceLatitudeDeg: _centerLat);
      expect(quantized, isNotEmpty);
      final quantizedAreaSqm = quantized
          .map((ring) => polygonArea(ring) * 1e6)
          .reduce((a, b) => a + b);

      // Hex-grid coverage-by-center is a raster approximation of the true
      // shape; it should land within a generous but bounded band of the
      // original captured area, not silently balloon or collapse it.
      expect(quantizedAreaSqm, greaterThan(nominalAreaSqm * 0.5));
      expect(quantizedAreaSqm, lessThan(nominalAreaSqm * 1.5));
    });
  });

  group('hexCellAt', () {
    test('two nearby points well inside the same cell resolve to the same cell', () {
      final a = hexCellAt(center, referenceLatitudeDeg: _centerLat);
      final b = hexCellAt(_offsetMetres(center, 1.0, 0.5), referenceLatitudeDeg: _centerLat);
      expect(b, equals(a));
    });

    test('points ~10 circumradii apart resolve to different cells', () {
      final a = hexCellAt(center, referenceLatitudeDeg: _centerLat);
      final b = hexCellAt(_offsetMetres(center, 100, 0), referenceLatitudeDeg: _centerLat);
      expect(b, isNot(equals(a)));
    });
  });
}
