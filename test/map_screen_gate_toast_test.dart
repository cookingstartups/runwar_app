// test/map_screen_gate_toast_test.dart
//
// RED phase - R1-AC1, R1-AC2 (UI wiring): the gate-rejection toast handler
// does not exist yet in map_screen.dart. Per flutter-test-patterns.md
// ("When NOT to use testWidgets for map tests" - AC verification that maps
// directly to source structure), this uses static source inspection rather
// than pumping MapScreen (which contains FlutterMap and would require
// mocking 5+ Riverpod providers just to reach initState).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Slices from [startMarker] up to (not including) the next occurrence of
/// [endMarker] - the real boundary of the member being inspected, not a
/// guessed character count. Fails loudly, naming the missing landmark,
/// instead of silently reading whatever text happens to sit at a fixed
/// offset.
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
  group('R1 gate-rejection toast wiring in map_screen.dart', () {
    test('_gateRejectionSub subscribes to gateRejections in initState (before build)', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('gateRejections'),
          reason: 'map_screen.dart must subscribe to RunRecorderNotifier.gateRejections');
      final subIdx = src.indexOf('gateRejections');
      final buildIdx = src.indexOf('Widget build(');
      expect(subIdx, lessThan(buildIdx),
          reason: 'The gateRejections subscription must be registered in initState, not inside build()');
    });

    test('_onGateRejected handler exists and shows a SnackBar', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('_onGateRejected'),
          reason: '_onGateRejected must exist as the gateRejections listener callback');
      final body = _sliceToNextMember(src, '_onGateRejected(', 'void _showResultSnack(BuildContext context, ClaimOutcome outcome) {');
      expect(body, contains('showSnackBar'),
          reason: '_onGateRejected must surface a SnackBar/toast to the operator');
    });

    test('_onGateRejected switches on both GateRejectionReason values with distinct messages', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, '_onGateRejected(', 'void _showResultSnack(BuildContext context, ClaimOutcome outcome) {');
      expect(body, contains('GateRejectionReason.areaFloor'),
          reason: 'Area-floor rejection must be handled with a distinct message (R1-AC1)');
      expect(body, contains('GateRejectionReason.sessionElapsed'),
          reason: 'Session-elapsed rejection must be handled with a distinct message (R1-AC2)');
    });

    test('_gateRejectionSub is cancelled in dispose()', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('_gateRejectionSub?.cancel()'),
          reason: 'The gate-rejection subscription must be cancelled in dispose() to avoid leaks');
    });
  });

  // ===========================================================================
  // SPEC-0143 scenario 11: the sessionElapsed toast copy changes to convey
  // that a loop closure was captured and deferred, not generic encouragement.
  // The other four gate toasts stay byte-for-byte unchanged.
  // ===========================================================================

  group('sessionElapsed toast copy conveys a captured, deferred claim', () {
    test('the old generic-encouragement string is gone', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, isNot(contains("'Keep running - claims unlock after 1 min'")),
          reason: 'The old sessionElapsed toast read as generic encouragement, not as a '
              'signal that a specific loop closure was captured and deferred');
    });

    test('a new sessionElapsed string is present, conveying capture and automatic claim', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('GateRejectionReason.sessionElapsed =>');
      expect(idx, greaterThanOrEqualTo(0),
          reason: 'The sessionElapsed switch arm must still exist');
      final line = src.substring(idx, src.indexOf('\n', idx));
      expect(line, isNot(contains('Keep running')),
          reason: 'The sessionElapsed arm must no longer read as generic encouragement');
      expect(line.toLowerCase(), anyOf(contains('captured'), contains('automatic')),
          reason: 'The new copy must convey that a specific closure was captured and will '
              'claim automatically, not that the operator needs to keep moving');
    });

    test('the four other gate toast strings stay byte-for-byte unchanged', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains("GateRejectionReason.areaFloor => 'Loop too small - min 200 m²'"));
      expect(src, contains("GateRejectionReason.diagonalFloor => 'Loop too small - run a wider path'"));
      expect(src, contains("GateRejectionReason.compactness => 'Loop too thin - run a wider path'"));
      expect(src, contains("GateRejectionReason.pathLength => 'Loop too short - keep running'"));
    });
  });
}
