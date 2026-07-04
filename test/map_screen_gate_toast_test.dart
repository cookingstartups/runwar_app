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
      final idx = src.indexOf('_onGateRejected(');
      final body = src.substring(idx, (idx + 800).clamp(0, src.length));
      expect(body, contains('showSnackBar'),
          reason: '_onGateRejected must surface a SnackBar/toast to the operator');
    });

    test('_onGateRejected switches on both GateRejectionReason values with distinct messages', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('_onGateRejected(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = src.substring(idx, (idx + 800).clamp(0, src.length));
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
}
