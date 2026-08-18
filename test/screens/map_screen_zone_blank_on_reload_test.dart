// test/screens/map_screen_zone_blank_on_reload_test.dart
//
// Asserts zonesAsync.when()'s loading/error branches keep rendering the
// last-good zone list instead of a bare empty list, so a claimed zone does
// not visually vanish on a reload/refetch/transient-error frame.
//
// Uses static source inspection (matching the house style established by
// map_screen_fog_gate_sim_position_test.dart) since MapScreen carries a
// FlutterMap and throws tile-fetch exceptions under widget-test pumping.

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
  group('map_screen.dart zonesAsync.when: keeps last-good zones during reload', () {
    test('loading/error branches do not pass a bare const [] to _buildMap', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final block = _sliceToNextMember(
          src, 'final mapBody = zonesAsync.when(', '// When in mission mode');

      expect(block, isNot(contains('_buildMap(context, center, const []')),
          reason: 'the loading and error branches must render '
              'zonesAsync.valueOrNull ?? const [] (the previously-fetched '
              'zone list) rather than an unconditional const [] - otherwise a '
              'claimed zone disappears on every reload/refetch/transient '
              'error frame');
    });

    test('loading/error branches read zonesAsync.valueOrNull as their zone list source', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final block = _sliceToNextMember(
          src, 'final mapBody = zonesAsync.when(', '// When in mission mode');

      final loadingIdx = block.indexOf('loading: () =>');
      final errorIdx = block.indexOf('error: (e, _) =>');
      expect(loadingIdx, greaterThanOrEqualTo(0));
      expect(errorIdx, greaterThan(loadingIdx));

      final loadingBranch = block.substring(loadingIdx, errorIdx);
      expect(loadingBranch, contains('zonesAsync.valueOrNull'),
          reason: 'loading branch must source its zone list from valueOrNull, not a hardcoded empty list');

      final errorBranch = block.substring(errorIdx);
      expect(errorBranch, contains('zonesAsync.valueOrNull'),
          reason: 'error branch must source its zone list from valueOrNull, not a hardcoded empty list');
      expect(errorBranch, contains('showError: true'),
          reason: 'error branch must still surface the error banner even while retaining last-good zones');
    });
  });
}
