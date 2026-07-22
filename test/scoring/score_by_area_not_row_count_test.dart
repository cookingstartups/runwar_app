// test/scoring/score_by_area_not_row_count_test.dart
//
// Regression test for the invariant: a player's score/standing tracks the
// TOTAL AREA they occupy, never the NUMBER of zone rows that area happens
// to be split across. A rival slicing a piece out of the middle of an
// owned holding turns one zone row into two (or more); that split must
// never change the player's occupied-area total or any figure derived
// additively from it, as long as the combined area is unchanged.
//
// Files under test:
//   lib/services/territory_service.dart — TerritoryService.polygonAreaKm2
//   lib/services/database/models/zone.dart — Zone.fromGeoJsonRow
//   lib/providers/territory_provider.dart — playerTerritoryKm2Provider
//     (the player-facing occupied-area total; this test exercises its exact
//     row-summation loop directly, since the provider itself is wired to a
//     live Supabase client with no dependency-injection seam suitable for a
//     unit test)
//
// Coverage:
//   1. Occupied-area total: one row vs several rows summing to the same
//      total area produce the exact same total.
//   2. Passive-income accrual shape (influence * area * elapsedHours,
//      territory_service.dart accruePassiveIncome): summed per row, equal
//      influence and equal elapsed time across rows must yield the same
//      total earned regardless of row count for the same total area.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/database/models/zone.dart';
import 'package:runwar_app/services/territory_service.dart' show TerritoryService;

/// Builds a raw zones-table row map (GeoJSON Polygon, [lon, lat] order) the
/// same shape Zone.fromGeoJsonRow expects, for an axis-aligned rectangle.
Map<String, dynamic> _rectRow({
  required String id,
  required double lat0,
  required double lat1,
  required double lon0,
  required double lon1,
  int influenceLevel = 1,
}) {
  final ring = [
    [lon0, lat0],
    [lon1, lat0],
    [lon1, lat1],
    [lon0, lat1],
    [lon0, lat0],
  ];
  return {
    'id': id,
    'owner_id': 'p1',
    'city': 'valencia',
    'influence_level': influenceLevel,
    'status': 'owned',
    'geom_json': jsonEncode({'type': 'Polygon', 'coordinates': [ring]}),
  };
}

/// Mirrors playerTerritoryKm2Provider's exact summation loop
/// (lib/providers/territory_provider.dart): sum polygonAreaKm2 over every
/// row's parsed points. This is the player-facing occupied-area total.
double _occupiedAreaKm2(List<Map<String, dynamic>> rows) {
  var total = 0.0;
  for (final r in rows) {
    total += TerritoryService.polygonAreaKm2(Zone.fromGeoJsonRow(r).points);
  }
  return total;
}

/// Mirrors territory_service.dart's accruePassiveIncome formula
/// (influence * areaKm2 * elapsedHours), summed additively per row.
double _passiveIncomeEarned(
  List<Map<String, dynamic>> rows,
  double elapsedHours,
) {
  var total = 0.0;
  for (final r in rows) {
    final zone = Zone.fromGeoJsonRow(r);
    final areaKm2 = TerritoryService.polygonAreaKm2(zone.points);
    total += zone.influenceLevel * areaKm2 * elapsedHours;
  }
  return total;
}

void main() {
  group('score follows occupied area, not the number of zone rows', () {
    // A single rectangle near Valencia, lat band 39.470..39.480, spanning
    // 0.10 degrees of longitude. Its combined area is the reference total.
    const lat0 = 39.470;
    const lat1 = 39.480;
    const lon0 = -0.40;
    const lon1 = -0.30;

    test(
      'one row vs the same area split into two rows: identical occupied-area total',
      () {
        final oneRow = [
          _rectRow(id: 'whole', lat0: lat0, lat1: lat1, lon0: lon0, lon1: lon1),
        ];

        // Same lat band, split at the midpoint longitude: the combined
        // width of the two pieces exactly equals the whole rectangle's
        // width, so the combined area exactly equals the whole area.
        const lonMid = (lon0 + lon1) / 2;
        final twoRows = [
          _rectRow(id: 'left', lat0: lat0, lat1: lat1, lon0: lon0, lon1: lonMid),
          _rectRow(id: 'right', lat0: lat0, lat1: lat1, lon0: lonMid, lon1: lon1),
        ];

        final totalOneRow = _occupiedAreaKm2(oneRow);
        final totalTwoRows = _occupiedAreaKm2(twoRows);

        // Both totals derive from the exact same rectangular geometry, just
        // partitioned differently; the shoelace formula is linear in the
        // longitude span at a fixed latitude band, so the two totals must
        // match to floating-point summation noise only (not to any
        // approximation in the scoring rule itself).
        expect(
          totalTwoRows,
          closeTo(totalOneRow, totalOneRow * 1e-9),
          reason:
              'Splitting the same occupied area across two zone rows must '
              'not change the player-facing occupied-area total. A change '
              'here means score is leaking row-count instead of tracking '
              'area.',
        );
      },
    );

    test(
      'one row vs the same area split into three rows: identical occupied-area total',
      () {
        final oneRow = [
          _rectRow(id: 'whole', lat0: lat0, lat1: lat1, lon0: lon0, lon1: lon1),
        ];

        const third = (lon1 - lon0) / 3;
        final threeRows = [
          _rectRow(id: 'a', lat0: lat0, lat1: lat1, lon0: lon0, lon1: lon0 + third),
          _rectRow(id: 'b', lat0: lat0, lat1: lat1, lon0: lon0 + third, lon1: lon0 + 2 * third),
          _rectRow(id: 'c', lat0: lat0, lat1: lat1, lon0: lon0 + 2 * third, lon1: lon1),
        ];

        final totalOneRow = _occupiedAreaKm2(oneRow);
        final totalThreeRows = _occupiedAreaKm2(threeRows);

        expect(
          totalThreeRows,
          closeTo(totalOneRow, totalOneRow * 1e-9),
          reason:
              'A rival cutting a holding into three pieces must not change '
              'the occupied-area total, only whichever pieces change owner.',
        );
      },
    );

    test(
      'passive-income accrual: same total area, same influence level, same elapsed time '
      'earns the same credits whether held as one row or split across rows',
      () {
        const level = 5;
        const elapsedHours = 2.0;

        final oneRow = [
          _rectRow(
            id: 'whole',
            lat0: lat0,
            lat1: lat1,
            lon0: lon0,
            lon1: lon1,
            influenceLevel: level,
          ),
        ];

        const lonMid = (lon0 + lon1) / 2;
        final twoRows = [
          _rectRow(
            id: 'left',
            lat0: lat0,
            lat1: lat1,
            lon0: lon0,
            lon1: lonMid,
            influenceLevel: level,
          ),
          _rectRow(
            id: 'right',
            lat0: lat0,
            lat1: lat1,
            lon0: lonMid,
            lon1: lon1,
            influenceLevel: level,
          ),
        ];

        final earnedOneRow = _passiveIncomeEarned(oneRow, elapsedHours);
        final earnedTwoRows = _passiveIncomeEarned(twoRows, elapsedHours);

        expect(
          earnedTwoRows,
          closeTo(earnedOneRow, earnedOneRow * 1e-9),
          reason:
              'Passive income is influence * area * elapsedHours summed per '
              'row. At equal influence level across the split rows this must '
              'equal the same formula applied once to the whole area - '
              'splitting a holding must never inflate or deflate income.',
        );
      },
    );

    // Sanity check the fixture itself is non-degenerate, so a regression
    // that zeroes out polygonAreaKm2 cannot make the equality checks above
    // pass vacuously (0.0 == 0.0).
    test('fixture rectangle has non-zero area (equality checks above are not vacuous)', () {
      final area = TerritoryService.polygonAreaKm2([
        const LatLng(lat0, lon0),
        const LatLng(lat0, lon1),
        const LatLng(lat1, lon1),
        const LatLng(lat1, lon0),
      ]);
      expect(area, greaterThan(0.0));
      // Rough sanity bound using the same formula the implementation uses,
      // just to catch a gross unit error (e.g. km vs m) rather than pin an
      // exact figure this test does not otherwise depend on.
      const latRad = ((lat0 + lat1) / 2) * math.pi / 180;
      final expected = (lon1 - lon0).abs() * (lat1 - lat0).abs() * 111.32 * 111.32 * math.cos(latRad);
      expect(area, closeTo(expected, expected * 0.01));
    });
  });
}
