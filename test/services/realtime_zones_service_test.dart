// test/services/realtime_zones_service_test.dart
//
// Regression tests for RealtimeZonesService._normalise — verifies that
// influence_level (not the stale 'score' column) drives the 'influence' output.

import 'package:flutter_test/flutter_test.dart';
import 'package:runwar_app/services/realtime_zones_service.dart';

void main() {
  group('RealtimeZonesService._normalise', () {
    final service = RealtimeZonesService.instance;

    // GIVEN a row with influence_level set to 8
    // WHEN _normalise is called
    // THEN 'influence' in the output equals 8.0
    test('row with influence_level:8 → output influence == 8.0', () {
      final input = <String, dynamic>{
        'id': 'zone-001',
        'owner_id': 'owner-abc',
        'city': 'Valencia',
        'influence_level': 8,
        'status': 'owned',
        'geom_json': '{"type":"Polygon","coordinates":[[]]}',
        'shield_active': false,
        'shield_expires_at': null,
        'dispute_expires_at': null,
        'created_at': '2026-06-01T00:00:00Z',
        'updated_at': '2026-06-01T00:00:00Z',
      };

      final result = service.normaliseForTest(input);

      expect(result['influence'], equals(8.0),
          reason: 'influence_level 8 must map to influence 8.0');
    });

    // GIVEN a row without an influence_level key
    // WHEN _normalise is called
    // THEN 'influence' in the output defaults to 1.0
    test('row without influence_level → output influence defaults to 1.0', () {
      final input = <String, dynamic>{
        'id': 'zone-002',
        'owner_id': 'owner-xyz',
        'city': 'Madrid',
        'status': 'owned',
        'geom_json': '{"type":"Polygon","coordinates":[[]]}',
        'shield_active': false,
        'shield_expires_at': null,
        'dispute_expires_at': null,
        'created_at': '2026-06-01T00:00:00Z',
        'updated_at': '2026-06-01T00:00:00Z',
      };

      final result = service.normaliseForTest(input);

      expect(result['influence'], equals(1.0),
          reason: 'missing influence_level must default to 1.0');
    });
  });
}
