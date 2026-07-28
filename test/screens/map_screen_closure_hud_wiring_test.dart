// test/screens/map_screen_closure_hud_wiring_test.dart
//
// RED phase - source inspection, not testWidgets, per this repo's
// flutter-test-patterns.md ("When NOT to use testWidgets for map tests"):
// map_screen.dart contains FlutterMap, and these assertions map directly to
// source structure (does the HUD gate ClosureIndicator's construction on a
// null check; does the stop branch push RunSummaryScreen; does cancel route
// through a confirmation gate) rather than to runtime rendering.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _mapScreenSrc() => File('lib/screens/map_screen.dart').readAsStringSync();

void main() {
  group('ClosureIndicator mounts only while an active closure event exists', () {
    test('map_screen.dart watches closureUiStateProvider', () {
      expect(_mapScreenSrc(), contains('closureUiStateProvider'),
          reason: 'map_screen.dart must watch the unified closure signal');
    });

    test('ClosureIndicator is constructed only when closureState is not null', () {
      final src = _mapScreenSrc();
      expect(src, contains('ClosureIndicator('),
          reason: 'map_screen.dart must construct ClosureIndicator somewhere');
      final idx = src.indexOf('ClosureIndicator(');
      // The construction must be preceded, on the same conditional expression,
      // by a null check on the closure state - never unconditionally rendered
      // merely because recording is true (no idle chip, Locked Design Value 19).
      final precedingChunk = src.substring((idx - 200).clamp(0, idx), idx);
      expect(precedingChunk, contains('!= null'),
          reason: 'ClosureIndicator must never mount unconditionally while '
              'recording - only when an active closure event exists');
    });
  });

  group('LiveRunStatsStrip sits directly beneath ClosureIndicator, never above it', () {
    test('LiveRunStatsStrip is referenced after ClosureIndicator in the same HUD block', () {
      final src = _mapScreenSrc();
      final closureIdx = src.indexOf('ClosureIndicator(');
      final stripIdx = src.indexOf('LiveRunStatsStrip(');
      expect(closureIdx, greaterThanOrEqualTo(0));
      expect(stripIdx, greaterThan(closureIdx),
          reason: 'LiveRunStatsStrip must be positioned beneath ClosureIndicator, '
              'never above it in source/layout order');
    });
  });

  group('RunSummaryScreen auto-push happens only from stopRun, never cancelRun', () {
    test('the stop branch pushes RunSummaryScreen', () {
      final src = _mapScreenSrc();
      expect(src, contains('RunSummaryScreen('),
          reason: 'map_screen.dart must push RunSummaryScreen somewhere');
    });

    test('the cancel path never pushes RunSummaryScreen', () {
      final src = _mapScreenSrc();
      final cancelIdx = src.indexOf('_confirmCancelRun');
      expect(cancelIdx, greaterThanOrEqualTo(0),
          reason: 'a cancel-confirmation gate must exist ahead of cancelRun()');
      final cancelBody = src.substring(
        cancelIdx,
        (src.indexOf('\n\n', cancelIdx + 1)).clamp(cancelIdx, src.length),
      );
      expect(cancelBody, isNot(contains('RunSummaryScreen(')),
          reason: 'a cancelled run must never auto-push RunSummaryScreen');
    });
  });

  group('cancel-run confirmation gate blocks cancelRun() until confirmed', () {
    test('the FAB long-press path routes through a confirmation sheet, not a direct cancelRun() call', () {
      final src = _mapScreenSrc();
      expect(src, contains('_confirmCancelRun'),
          reason: 'the cancel entry point must route through a confirmation gate '
              'before invoking cancelRun() (R6, Option C, locked)');
    });

    test('CancelRunSheet is the widget shown by the confirmation gate', () {
      final src = _mapScreenSrc();
      expect(src, contains('CancelRunSheet'),
          reason: 'the locked Option C bottom sheet widget must be wired in');
    });
  });
}
