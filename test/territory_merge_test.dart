// test/territory_merge_test.dart
//
// RED phase - R3-AC1, R3-AC3 (edge case): the persistent-render adjacency
// grouping helper described in design.md section 5
// (map_screen.dart's `_groupAdjacentZones`) does not exist yet. Per
// design.md's own note ("kept as its own small helper so widget tests can
// assert grouping independent of rendering"), this test assumes the
// implementer exposes it as a top-level, test-only seam named
// `groupAdjacentZonesForTesting`, following this codebase's existing
// `...ForTesting` seam convention (run_recorder_service.dart).
//
// Assumed contract (test-only seam, not yet implemented):
//   List<List<Zone>> groupAdjacentZonesForTesting(List<Zone> zones)
// Takes ALL zones for one owner (any status) and returns the connected
// adjacency groups formed from the `owned`-status subset only (disputed
// zones never join a group and never bridge two owned zones together -
// R3-AC1 invariant).
//
// This import/symbol does not exist in map_screen.dart today, so every test
// below fails to compile ("groupAdjacentZonesForTesting isn't defined")
// until the implementation lands - the expected RED state.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/screens/map_screen.dart' show groupAdjacentZonesForTesting;
import 'package:runwar_app/services/database/models/zone.dart';

// A ~40m-side square, in the Valencia area (lat ~39.47), starting at the
// given (lat, lng) origin. Degree/metre conversion mirrors the constants
// used by run_recorder_service.dart's _equirectangularDistanceM.
List<LatLng> _squareAt(double lat0, double lng0) {
  const dLat = 0.0003618; // ~40 m north-south
  const dLng = 0.0004657; // ~40 m east-west at lat 39.47
  return [
    LatLng(lat0, lng0),
    LatLng(lat0, lng0 + dLng),
    LatLng(lat0 + dLat, lng0 + dLng),
    LatLng(lat0 + dLat, lng0),
  ];
}

Zone _zone(String id, String ownerId, List<LatLng> pts, {ZoneStatus status = ZoneStatus.owned}) =>
    Zone(id: id, ownerId: ownerId, city: 'valencia', influenceLevel: 1, status: status, points: pts);

void main() {
  group('render-time adjacency grouping - same-owner union (R3)', () {
    // GIVEN two same-owner zones sharing an edge (gap == 0, genuinely touching)
    // WHEN groupAdjacentZonesForTesting groups them
    // THEN they collapse into a single group
    test('two touching same-owner zones group into one', () {
      final z1 = _zone('z1', 'p1', _squareAt(39.470000, 33.000000));
      // z2 starts exactly where z1's right edge ends -> shared edge, gap == 0.
      final z2 = _zone('z2', 'p1', _squareAt(39.470000, 33.000466));

      final groups = groupAdjacentZonesForTesting([z1, z2]);

      expect(groups, hasLength(1),
          reason: 'Two zones sharing an edge must collapse into one render group');
      expect(groups.single, hasLength(2));
    });

    // GIVEN two same-owner zones ~200 m apart (well beyond any adjacency tolerance)
    // WHEN groupAdjacentZonesForTesting groups them
    // THEN they remain two independent groups
    test('two same-owner zones ~200 m apart do not group', () {
      final z1 = _zone('z1', 'p1', _squareAt(39.470000, 33.000000));
      // +200 m of longitude gap beyond z1's right edge.
      final z2 = _zone('z2', 'p1', _squareAt(39.470000, 33.002794));

      final groups = groupAdjacentZonesForTesting([z1, z2]);

      expect(groups, hasLength(2),
          reason: 'Zones ~200 m apart must never be treated as adjacent');
    });

    // GIVEN Z1-Z2 are touching and Z2-Z3 are touching, but Z1-Z3 do not touch directly
    // WHEN groupAdjacentZonesForTesting groups them
    // THEN all three collapse into a single connected group (transitive closure)
    test('three zones chained by pairwise adjacency collapse into one group', () {
      final z1 = _zone('z1', 'p1', _squareAt(39.470000, 33.000000));
      final z2 = _zone('z2', 'p1', _squareAt(39.470000, 33.000466));
      final z3 = _zone('z3', 'p1', _squareAt(39.470000, 33.000932));

      final groups = groupAdjacentZonesForTesting([z1, z2, z3]);

      expect(groups, hasLength(1),
          reason: 'Adjacency must be evaluated transitively across the whole chain');
      expect(groups.single, hasLength(3));
    });

    // GIVEN a disputed zone sits between two touching owned zones
    // WHEN groupAdjacentZonesForTesting groups them
    // THEN the disputed zone never joins a group and never bridges the two owned zones
    test('a disputed zone between two owned zones does not join or bridge them', () {
      final owned1 = _zone('o1', 'p1', _squareAt(39.470000, 33.000000));
      final disputed = _zone('d1', 'p1', _squareAt(39.470000, 33.000466), status: ZoneStatus.disputed);
      final owned2 = _zone('o2', 'p1', _squareAt(39.470000, 33.000932));

      final groups = groupAdjacentZonesForTesting([owned1, disputed, owned2]);

      final groupIds = groups.map((g) => g.map((z) => z.id).toSet()).toList();
      expect(groupIds.any((ids) => ids.contains('o1') && ids.contains('o2')), isFalse,
          reason: 'A disputed zone must never bridge two owned zones into one group');
      expect(groups.every((g) => g.every((z) => z.status == ZoneStatus.owned)), isTrue,
          reason: 'Disputed zones must never appear in an owned-zone render group');
    });
  });
}
