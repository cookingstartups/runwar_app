// test/main/deactivation_gate_test.dart
//
// Covers the new account-deactivation gate in main.dart's _RouteGuard,
// slotted immediately after the auth gate and before the phone-linked gate.
// Source-inspection, mirroring route_guard_test.dart's own AC-11 style
// checks for gate wiring that is awkward to exercise as a full widget pump
// (this gate depends on a live Supabase-backed provider).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('accountDeactivationProvider exists and queries pending requests', () {
    test('main.dart defines accountDeactivationProvider', () {
      final content = _read('lib/main.dart');
      expect(content.contains('accountDeactivationProvider'), isTrue);
    });

    test('the provider filters on account_deletion_requests status=pending', () {
      final content = _read('lib/main.dart');
      final idx = content.indexOf('accountDeactivationProvider');
      expect(idx, greaterThan(-1),
          reason: 'accountDeactivationProvider must be defined first');
      final end = (idx + 800).clamp(0, content.length);
      final tail = content.substring(idx, end);
      expect(tail.contains('account_deletion_requests'), isTrue);
      expect(tail.contains("'pending'"), isTrue);
    });
  });

  group('the deactivation gate sits after auth and before phone-linked', () {
    test('AccountDeactivatedScreen is referenced between the auth gate and '
        'the phone-linked gate comment', () {
      final content = _read('lib/main.dart');
      final gate0Idx = content.indexOf('Gate 0');
      final gate1Idx = content.indexOf('Gate 1');
      final screenIdx = content.indexOf('AccountDeactivatedScreen');

      expect(gate0Idx, greaterThan(-1), reason: 'Gate 0 (auth) must exist');
      expect(gate1Idx, greaterThan(-1),
          reason: 'Gate 1 (phone-linked) must exist');
      expect(screenIdx, greaterThan(-1),
          reason: 'AccountDeactivatedScreen must be referenced in _RouteGuard');
      expect(screenIdx > gate0Idx && screenIdx < gate1Idx, isTrue,
          reason: 'The deactivation gate must be evaluated after auth and '
              'before phone-linked, not anywhere else in the gate order');
    });
  });

  group('resume re-check wiring', () {
    test('didChangeAppLifecycleState invalidates accountDeactivationProvider',
        () {
      final content = _read('lib/main.dart');
      final resumeIdx = content.indexOf('didChangeAppLifecycleState');
      expect(resumeIdx, greaterThan(-1));
      final tail = content.substring(resumeIdx);
      expect(tail.contains('accountDeactivationProvider'), isTrue,
          reason: 'A deactivated-mid-session user must be re-checked on '
              'foreground resume, same as the existing trial gate');
    });
  });
}
