// test/services/territory_service_carved_hole_test.dart
//
// RED phase: territory_service.dart carries a second, independent copy of
// the outline parser (private, static). It has the identical hole-dropping
// bug as zone.dart's _parseOutlines - a Polygon's interior ring (or a
// MultiPolygon member's interior ring) is silently flattened to its outer
// boundary because the parser only ever reads coordsRaw[0] / poly[0]. This
// file proves that bug through the parser's new test-only public entry
// point, parseOutlinesForTest, which changes no behavior - it only exposes
// the existing private parser to a test.
//
// This second copy has no independent test coverage today: it is private
// with no pure public entry point, so a single-site fix on zone.dart alone
// would leave this sibling still broken, exactly the failure mode this
// coverage exists to catch.

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/territory_service.dart';

// Same donut fixture shape as zone_carved_hole_test.dart: a 10x10 exterior
// square with a 4x4 interior square hole. GeoJSON coordinate order is
// [lng, lat].
const _outerRing = [
  [0.0, 0.0],
  [0.0, 10.0],
  [10.0, 10.0],
  [10.0, 0.0],
  [0.0, 0.0],
];

const _holeRing = [
  [3.0, 3.0],
  [3.0, 7.0],
  [7.0, 7.0],
  [7.0, 3.0],
  [3.0, 3.0],
];

void main() {
  group('TerritoryService._parseOutlines carved-hole survival', () {
    test('a Polygon with an interior ring today loses the hole through this parser', () {
      final geomJson =
          '{"type":"Polygon","coordinates":[${_ring(_outerRing)},${_ring(_holeRing)}]}';

      final outlines = TerritoryService.parseOutlinesForTest(geomJson);

      // The exterior still parses (this part already works today).
      expect(outlines, isNotEmpty,
          reason: 'the exterior ring must still parse - this is not what is being fixed here');
      expect(outlines.first.length, _outerRing.length,
          reason: 'the exterior ring must be parsed point-for-point');

      // The behavioral proof: this parser returns exactly one outline for a
      // Polygon (its `Polygon` branch reads only coordsRaw[0]), so a second
      // ring representing the carved hole never survives at all. Once the
      // parser becomes ring-set aware, an interior ring must be observable
      // in the returned outlines - today it is not, so this fails.
      expect(outlines.length, greaterThan(1),
          reason: 'a Polygon carrying an interior ring must surface a second '
              'ring for the hole through this parser too - today it reads '
              'only coordinates[0] and the hole is silently dropped, so '
              'exactly one outline (the exterior) comes back');
    });

    test('a MultiPolygon member carrying an interior ring today loses the hole through this parser', () {
      final geomJson =
          '{"type":"MultiPolygon","coordinates":[[${_ring(_outerRing)},${_ring(_holeRing)}]]}';

      final outlines = TerritoryService.parseOutlinesForTest(geomJson);

      expect(outlines, isNotEmpty,
          reason: 'the exterior member ring must still parse');
      expect(outlines.length, greaterThan(1),
          reason: 'a MultiPolygon member with an interior ring must also '
              'surface that hole through this parser - the MultiPolygon '
              'branch reads only poly[0] per member today, dropping every '
              'interior ring the same way the Polygon branch does, so '
              'exactly one outline (the exterior member) comes back');
    });

    test('a Polygon with no interior ring yields exactly one outline (non-regression)', () {
      final geomJson = '{"type":"Polygon","coordinates":[${_ring(_outerRing)}]}';

      final outlines = TerritoryService.parseOutlinesForTest(geomJson);

      expect(outlines.length, 1,
          reason: 'a plain single-ring zone must not spuriously report a hole through this parser');
    });
  });
}

String _ring(List<List<double>> ring) {
  final pts = ring.map((p) => '[${p[0]},${p[1]}]').join(',');
  return '[$pts]';
}
