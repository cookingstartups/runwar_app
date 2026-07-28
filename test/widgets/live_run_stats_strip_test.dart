// test/widgets/live_run_stats_strip_test.dart
//
// RED phase: lib/widgets/live_run_stats_strip.dart does not exist yet.
// Locked design value: the strip shows distance + elapsed time only - no
// pace or speed value is ever displayed, since instantaneous currentSpeedMps
// is acceptable comet-tail noise but reads as broken as a displayed number.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/widgets/live_run_stats_strip.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('LiveRunStatsStrip', () {
    testWidgets('renders without throwing against the default recorder state',
        (tester) async {
      await tester.pumpWidget(_wrap(const LiveRunStatsStrip()));
      await tester.pump();

      expect(find.byType(LiveRunStatsStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never displays a pace, speed, or per-km value anywhere',
        (tester) async {
      await tester.pumpWidget(_wrap(const LiveRunStatsStrip()));
      await tester.pump();

      expect(find.textContaining('/km'), findsNothing,
          reason: 'the strip must never render a pace value');
      expect(find.textContaining('/mi'), findsNothing);
      expect(find.textContaining('MIN/'), findsNothing);
      expect(find.textContaining('PACE'), findsNothing);
    });
  });

  group('live_run_stats_strip.dart source: no live-speed dependency', () {
    test('the widget never reads currentSpeedMps or an equivalent instantaneous speed field', () {
      final src = File('lib/widgets/live_run_stats_strip.dart').readAsStringSync();
      expect(src, isNot(contains('currentSpeedMps')),
          reason: 'currentSpeedMps must remain the comet tail\'s only consumer - '
              'LiveRunStatsStrip must never surface it as a displayed number');
    });
  });
}
