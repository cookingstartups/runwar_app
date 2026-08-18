// test/screens/map_screen_owner_zone_always_visible_test.dart
//
// Asserts a zone owned by the current user always renders regardless of fog
// state (AC-E5), and that when fogCenters is empty only owned zones remain
// visible (the amended AC-E5 contract - closes the previous
// fogCenters.isEmpty ? zones : ... fail-open inconsistency against
// _isRevealedByFog's own fail-closed contract).
//
// Uses static source inspection (matching the house style established by
// map_screen_fog_gate_sim_position_test.dart) since MapScreen carries a
// FlutterMap and throws tile-fetch exceptions under widget-test pumping. A
// second, behavioral confirmation lives in
// test/integration/claim_zone_persistence_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sliceToNextMember(String src, String startMarker, String endMarker) {
  final start = src.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0),
      reason: 'Landmark not found: "$startMarker". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  final end = src.indexOf(endMarker, start);
  expect(end, greaterThan(start),
      reason: 'Landmark not found after "$startMarker": "$endMarker". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  return src.substring(start, end);
}

void main() {
  group('map_screen.dart visibleZones: owner-always-visible guard (AC-E5)', () {
    test('the visibleZones construction bypasses fog gating for zones owned by the current user', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final block = _sliceToNextMember(
          src, 'final visibleZones = zones.where', '.toList();');

      expect(block, contains('z.ownerId == userId'),
          reason: 'visibleZones must render zones owned by the current user '
              'regardless of fog-reveal state - the current gate has no '
              'owner-based bypass and filters an unrevealed owned zone out '
              'unconditionally');
    });

    test('the visibleZones construction no longer short-circuits to "all zones" when fogCenters is empty', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final block = _sliceToNextMember(
          src, 'final visibleZones', ';');

      expect(block, isNot(contains('fogCenters.isEmpty\n        ? zones')),
          reason: 'an empty fogCenters must no longer make every zone '
              'visible (fail-open) - only owned zones should remain visible, '
              'matching _isRevealedByFog\'s own fail-closed invariant '
              '(amended AC-E5 contract)');
    });
  });
}
