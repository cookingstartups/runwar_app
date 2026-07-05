// test/services/permission_service_test.dart
//
// RED phase — permission priming.
// Files under test (do not exist yet):
//   lib/services/permission_service.dart — PermissionService, PermKind,
//     classifyMiui, orderMissing
//
// Framework: flutter_test (mirrors project conventions).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runwar_app/services/permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── AC-11: MIUI manufacturer classification ─────────────────────────────
  group('AC-11: classifyMiui matches Xiaomi/Redmi/POCO case-insensitively', () {
    test('matches Xiaomi in any casing', () {
      expect(classifyMiui('Xiaomi'), isTrue);
      expect(classifyMiui('xiaomi'), isTrue);
      expect(classifyMiui('XIAOMI'), isTrue);
    });

    test('matches Redmi and POCO in any casing', () {
      expect(classifyMiui('Redmi'), isTrue);
      expect(classifyMiui('poco'), isTrue);
      expect(classifyMiui('POCO'), isTrue);
    });

    test('returns false for Samsung, empty string, and garbage input', () {
      expect(classifyMiui('Samsung'), isFalse);
      expect(classifyMiui(''), isFalse);
      expect(classifyMiui('###garbage###'), isFalse);
    });
  });

  // ── AC-4 invariant: canonical card ordering ─────────────────────────────
  group('AC-4 invariant: orderMissing enforces location, notifications, battery order', () {
    test('reorders an unordered set into the canonical order', () {
      final result = orderMissing(
          {PermKind.battery, PermKind.location, PermKind.notifications});
      expect(
          result, [PermKind.location, PermKind.notifications, PermKind.battery]);
    });

    test('filters the canonical order down to only the missing subset', () {
      final result = orderMissing({PermKind.battery, PermKind.notifications});
      expect(result, [PermKind.notifications, PermKind.battery]);
    });

    test('returns an empty list when nothing is missing', () {
      expect(orderMissing(<PermKind>{}), isEmpty);
    });
  });

  // ── AC-2: priming lifecycle persistence ─────────────────────────────────
  group('AC-2: isPrimingDone / markPrimingDone round-trip against persisted prefs', () {
    test('isPrimingDone is false before markPrimingDone is ever called', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PermissionService.instance.isPrimingDone(), isFalse);
    });

    test('isPrimingDone is true after markPrimingDone persists the flag', () async {
      SharedPreferences.setMockInitialValues({});
      await PermissionService.instance.markPrimingDone();
      expect(await PermissionService.instance.isPrimingDone(), isTrue);
    });
  });

  // ── AC-3: auto-heal path ─────────────────────────────────────────────────
  group('AC-3: autoCompleteIfAllGranted marks priming done without a card', () {
    // NOTE: missingPermissions() calls real platform channels (Geolocator /
    // permission_handler / device_info_plus) with no DI seam per design.md's
    // explicit Gotcha note. This test exercises the real call path and is
    // expected to require the implementer to add a testable seam to pass
    // meaningfully; AC-3's routing-level behavior is authoritatively covered
    // in test/main/route_guard_test.dart via a full provider override, which
    // needs no platform channel at all.
    test('marks priming done when a live check reports nothing missing', () async {
      SharedPreferences.setMockInitialValues({});
      await PermissionService.instance.autoCompleteIfAllGranted();
      expect(await PermissionService.instance.isPrimingDone(), isTrue);
    });
  });
}
