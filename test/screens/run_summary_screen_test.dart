// test/screens/run_summary_screen_test.dart
//
// RED phase: lib/screens/run_summary_screen.dart does not exist yet.
// RunSummaryScreen is a thin Scaffold/SafeArea wrapper handing its
// constructor-provided RunSummary straight through to RunMetricsCard, and
// wiring Close to a pop - it never reads live recorder state itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/models/run_summary.dart';
import 'package:runwar_app/screens/run_summary_screen.dart';
import 'package:runwar_app/widgets/run_metrics_card.dart';

void main() {
  group('RunSummaryScreen', () {
    testWidgets('renders a RunMetricsCard built from the constructor-provided RunSummary',
        (tester) async {
      final summary = RunSummary(
        distanceM: 1000,
        duration: const Duration(minutes: 10),
        claims: const [],
      );

      await tester.pumpWidget(MaterialApp(
        home: RunSummaryScreen(summary: summary),
      ));
      await tester.pump();

      final card = tester.widget<RunMetricsCard>(find.byType(RunMetricsCard));
      expect(card.summary, same(summary),
          reason: 'RunSummaryScreen must hand its own summary straight through, '
              'never reconstruct or read live recorder state');
    });

    testWidgets('tapping Close dismisses the screen and returns to the caller',
        (tester) async {
      final summary = RunSummary(
        distanceM: 1000,
        duration: const Duration(minutes: 10),
        claims: const [],
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RunSummaryScreen(summary: summary),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          );
        }),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(RunSummaryScreen), findsOneWidget);

      await tester.tap(find.textContaining('CLOSE'));
      await tester.pumpAndSettle();

      expect(find.byType(RunSummaryScreen), findsNothing,
          reason: 'Close must dismiss RunSummaryScreen and return to the map');
    });
  });
}
