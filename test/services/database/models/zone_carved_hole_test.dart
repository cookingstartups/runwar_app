// test/services/database/models/zone_carved_hole_test.dart
//
// RED phase: a shielded overlap carved into a rival's claim is stored
// server-side as a Polygon with an interior ring (a hole). Zone.fromGeoJsonRow
// and its private _parseOutlines helper today take only coordsRaw[0] / poly[0]
// per member, which silently flattens a donut shape to its outer boundary -
// the hole is dropped on parse. These tests fail until the parser is made
// ring-set aware and threads interior rings through into Zone.holeOutlines.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/database/models/zone.dart';

// A simple square donut: a 10x10 exterior square with a 4x4 interior square
// hole centred inside it. Coordinates are GeoJSON order [lng, lat].
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

Map<String, dynamic> _row(Map<String, dynamic> geom) => {
      'id': 'zone-1',
      'owner_id': 'player-b',
      'city': 'Valencia',
      'influence_level': 2,
      'status': 'owned',
      'geom_json': geom,
    };

void main() {
  group('Zone.fromGeoJsonRow carved-hole survival', () {
    test('a Polygon with an interior ring keeps the hole in Zone.holeOutlines', () {
      final geom = {
        'type': 'Polygon',
        'coordinates': [_outerRing, _holeRing],
      };

      final zone = Zone.fromGeoJsonRow(_row(geom));

      // The exterior must still be intact (this part already works today).
      expect(zone.points, isNotEmpty,
          reason: 'the exterior ring must still parse - this is not what is being fixed here');

      // This is the behavioral proof: today _parseOutlines only ever reads
      // coordsRaw[0], so a carved hole never reaches Zone.holeOutlines at all.
      expect(zone.holeOutlines, isNotEmpty,
          reason: 'a Polygon carrying an interior ring must surface it via '
              'Zone.holeOutlines - today the parser reads only coordinates[0] '
              'and the hole is silently dropped');

      expect(zone.holeOutlines.first.length, _holeRing.length,
          reason: 'the carved hole ring must be parsed point-for-point, not truncated or empty');

      // Spot-check the actual coordinates made it through in the right order
      // (LatLng is lat,lng; GeoJSON rings are lng,lat).
      final firstHolePoint = zone.holeOutlines.first.first;
      expect(firstHolePoint.latitude, closeTo(_holeRing.first[1], 1e-9));
      expect(firstHolePoint.longitude, closeTo(_holeRing.first[0], 1e-9));
    });

    test('a MultiPolygon member carrying an interior ring surfaces it too', () {
      final geom = {
        'type': 'MultiPolygon',
        'coordinates': [
          [_outerRing, _holeRing],
        ],
      };

      final zone = Zone.fromGeoJsonRow(_row(geom));

      expect(zone.holeOutlines, isNotEmpty,
          reason: 'a MultiPolygon member with an interior ring must also surface '
              'its hole via Zone.holeOutlines - the MultiPolygon branch of '
              '_parseOutlines reads only poly[0] per member today, dropping '
              'every interior ring the same way the Polygon branch does');
    });

    test('a Polygon with no interior ring yields an empty hole list (non-regression)', () {
      final geom = {
        'type': 'Polygon',
        'coordinates': [_outerRing],
      };

      final zone = Zone.fromGeoJsonRow(_row(geom));

      expect(zone.holeOutlines, isEmpty,
          reason: 'a plain single-ring zone must not spuriously report a hole');
    });
  });
}
