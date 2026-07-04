// test/services/legacy_permission_guards_test.dart
//
// RED phase — permission priming.
// Source-inspection tests (flutter-test-patterns.md §2/§"When NOT to use
// testWidgets"): these ACs are "does the refactored call site route through
// PermissionService?", verified structurally rather than by exercising real
// platform channels, per design.md's explicit no-DI-seam Gotcha for this
// service surface.
//
// Files under test (do not exist in refactored form yet):
//   lib/screens/map_screen.dart              — _initLocation, FAB battery tap
//   lib/services/fcm_service.dart            — init()
//   lib/services/battery_optimization_service.dart — requestOnce()
//   lib/providers/run_recorder_provider.dart — NotificationGateway.fireDispute
//   lib/providers/permission_priming_provider.dart — Android-only gate

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── AC-10: map_screen.dart location becomes a no-op-if-granted guard ───
  group('AC-10: map_screen location guard reads PermissionService instead of requesting', () {
    test('_initLocation consults PermissionService before starting the position stream',
        () {
      final content = File('lib/screens/map_screen.dart').readAsStringSync();
      final start = content.indexOf('_initLocation');
      expect(start, greaterThan(-1), reason: '_initLocation must still exist');
      final body = content.substring(start, content.length);
      expect(body.contains('PermissionService.instance.isLocationGranted'), isTrue,
          reason: '_initLocation must consult PermissionService.isLocationGranted, '
              'not call Geolocator.requestPermission directly on mount');
    });

    test('revoked-after-priming late guard renders LocationDeniedGate on the map',
        () {
      final content = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(content.contains('LocationDeniedGate'), isTrue,
          reason: 'MapScreen must reuse LocationDeniedGate for the revoked-location '
              'late guard (AC-10 revoked scenario)');
    });
  });

  // ── AC-10: FcmService.init becomes a no-op-if-granted guard ─────────────
  group('AC-10: FcmService.init consults PermissionService before requesting', () {
    test('init() checks isNotificationsGranted before calling requestPermission', () {
      final content = File('lib/services/fcm_service.dart').readAsStringSync();
      expect(content.contains('PermissionService.instance.isNotificationsGranted'),
          isTrue,
          reason: 'FcmService.init must gate its requestPermission call through '
              'PermissionService.isNotificationsGranted');
    });
  });

  // ── AC-10: BatteryOptimizationService.requestOnce becomes a guard ───────
  group('AC-10: BatteryOptimizationService.requestOnce consults PermissionService', () {
    test('requestOnce reads PermissionService rather than its own prompted flag', () {
      final content =
          File('lib/services/battery_optimization_service.dart').readAsStringSync();
      expect(content.contains('PermissionService'), isTrue,
          reason: 'requestOnce must delegate its granted/asked checks to PermissionService');
      expect(content.contains('battery_opt_prompted'), isFalse,
          reason: 'The private battery_opt_prompted flag must be retired per AC-1 '
              '(no duplicate grant-tracking flags)');
    });
  });

  // ── AC-10: NotificationGateway.fireDispute becomes a guard ──────────────
  group('AC-10: NotificationGateway.fireDispute consults PermissionService', () {
    test('fireDispute reads PermissionService instead of the in-memory cache', () {
      final content =
          File('lib/providers/run_recorder_provider.dart').readAsStringSync();
      expect(content.contains('PermissionService.instance.isNotificationsGranted'),
          isTrue,
          reason: 'fireDispute must gate on PermissionService.isNotificationsGranted');
      expect(content.contains('_permissionGranted'), isFalse,
          reason: 'The in-memory _permissionGranted cache must be retired per AC-1');
    });

    test('NotificationGateway is promoted from private to a public class', () {
      final content =
          File('lib/providers/run_recorder_provider.dart').readAsStringSync();
      expect(content.contains('class NotificationGateway'), isTrue,
          reason: 'NotificationGateway must be public so PermissionService can reuse it');
      expect(content.contains('class _NotificationGateway'), isFalse,
          reason: 'The old private _NotificationGateway declaration must be gone');
    });
  });

  // ── Android-only platform gate ───────────────────────────────────────────
  group('Android-only behavioral gate: priming never applies on iOS', () {
    test('permission_priming_provider short-circuits to an empty list on iOS', () {
      final src = File('lib/providers/permission_priming_provider.dart');
      expect(src.existsSync(), isTrue,
          reason: 'permission_priming_provider.dart must exist');
      final content = src.readAsStringSync();
      expect(content.contains('Platform.isAndroid'), isTrue,
          reason: 'The gate provider must check Platform.isAndroid before doing any work');
    });

    test('PermissionService.missingPermissions is gated on Android', () {
      final content =
          File('lib/services/permission_service.dart').readAsStringSync();
      expect(content.contains('Platform.isAndroid'), isTrue,
          reason: 'missingPermissions must short-circuit to [] on iOS per design.md');
    });
  });
}
