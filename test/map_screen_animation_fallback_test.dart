// test/map_screen_animation_fallback_test.dart
//
// RED phase - R4-AC1 (zonesProvider fallback fetch), R4-AC3 (disputed
// distinct message, regression-lock), R4-AC4 (failed message + reason log).
// Uses static source inspection (flutter-test-patterns.md) since
// _onAutoClaimOutcome lives inside MapScreen (FlutterMap-bearing) and the
// behaviour under test ("does the handler await a fallback fetch / log a
// reason") maps directly to source structure rather than runtime widget
// state.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R4-AC1: zonesProvider(city) fallback fetch before E&U animation', () {
    test('_onAutoClaimOutcome is async (Future<void>), not fire-and-forget void', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('Future<void> _onAutoClaimOutcome('),
          reason: '_onAutoClaimOutcome must become async so it can await the fallback fetch (design.md R4-AC1)');
    });

    test('the outcome handler falls back to zonesRepositoryProvider.fetchByCity when the stream has not emitted', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('_onAutoClaimOutcome(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = src.substring(idx, (idx + 2500).clamp(0, src.length));
      expect(body, contains('hasValue'),
          reason: 'The handler must check whether zonesProvider(city) has already emitted a snapshot');
      expect(body, contains('zonesRepositoryProvider'),
          reason: 'On no prior snapshot, the handler must fetch via zonesRepositoryProvider (not substitute an empty list)');
      expect(body, contains('fetchByCity'),
          reason: 'The fallback fetch must call fetchByCity(city)');
    });
  });

  group('R4-AC3: disputed outcome gets a distinct, non-silent message (regression-lock)', () {
    test('_showResultSnack has a disputed branch distinct from claimed/conquered/failed', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('_showResultSnack(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = src.substring(idx, (idx + 600).clamp(0, src.length));
      expect(body, contains('TerritoryResult.disputed'),
          reason: '_showResultSnack must switch on TerritoryResult.disputed with its own message');
    });
  });

  group('R4-AC4: failed outcome shows a distinct message and logs the reason', () {
    test('the failed branch of _onAutoClaimOutcome logs the reason via ErrorLogService', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('_onAutoClaimOutcome(');
      expect(idx, greaterThanOrEqualTo(0));
      final failedIdx = src.indexOf('TerritoryResult.failed', idx);
      expect(failedIdx, greaterThanOrEqualTo(0));
      final body = src.substring(failedIdx, (failedIdx + 700).clamp(0, src.length));
      expect(body, contains('logClientError'),
          reason: 'The failed branch must log the underlying failure reason via ErrorLogService.logClientError');
      expect(body, contains('reason'),
          reason: 'The logged error must reference the reason string returned by the server/local evaluator');
    });
  });
}
