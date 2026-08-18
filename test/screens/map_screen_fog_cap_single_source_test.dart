// test/screens/map_screen_fog_cap_single_source_test.dart
//
// Asserts _FogLayer's build method no longer applies its own independent
// 200-point cap - decimation/capping must live exactly once, in
// userRunPointsProvider (AC-E4/D4), so the zone-visibility gate (fogCenters)
// and the fog paint layer (_FogLayer) can never disagree about which points
// drive fog reveal.

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
  group('_FogLayer: single shared decimation/cap source (AC-E4/D4)', () {
    test('_FogLayer.build does not re-derive historicalPoints via its own 200-cap slice', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(
          src, 'Widget build(BuildContext context, WidgetRef ref) {', 'return CustomPaint(');

      expect(body, isNot(contains('runPoints.length > 200')),
          reason: '_FogLayer must not apply an independent 200-point cap - '
              'userRunPointsProvider already returns an already-decimated, '
              'already-capped list (decimateAndCapFogPoints), so a second cap '
              'here duplicates the single source of truth AC-E4/D4 requires');
      expect(body, isNot(contains('.sublist(0, 200)')),
          reason: '_FogLayer must not slice runPoints down to 200 itself - '
              'the cap must live exactly once, in the shared provider');
    });

    test('_FogLayer.build feeds runPoints directly into the historical centers loop', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(
          src, 'Widget build(BuildContext context, WidgetRef ref) {', 'return CustomPaint(');

      expect(body, contains('for (final pt in runPoints)'),
          reason: 'the historical-points loop must iterate runPoints directly '
              '(already decimated/capped upstream), not a re-derived local '
              'variable like historicalPoints');
    });
  });
}
