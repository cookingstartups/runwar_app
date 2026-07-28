// test/widgets/closure_indicator_test.dart
//
// RED phase: ClosureIndicator, ClosureUiState, and ClosureUiKind do not
// exist yet under lib/widgets/closure_indicator.dart or
// lib/providers/run_recorder_provider.dart. Each test below maps to one
// GIVEN/WHEN/THEN in the run-lifecycle-feedback requirements/design.
//
// ClosureIndicator is a pure StatelessWidget that always takes a non-null
// state; the "renders nothing while idle" behavior lives one level up, in
// the HUD's own mount/unmount wiring, and is covered separately in
// test/screens/map_screen_closure_hud_wiring_test.dart (source inspection,
// per this repo's flutter-test-patterns.md convention).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/run_recorder_service.dart';
import 'package:runwar_app/services/territory_service.dart';
import 'package:runwar_app/providers/run_recorder_provider.dart';
import 'package:runwar_app/widgets/closure_indicator.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ClosureIndicator states', () {
    testWidgets('a geometry-gate rejection renders muted try-again copy',
        (tester) async {
      await tester.pumpWidget(_wrap(const ClosureIndicator(
        state: ClosureUiState.gateRejected(GateRejectionReason.areaFloor),
      )));
      await tester.pump();

      expect(find.byType(ClosureIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the session-elapsed wait state shows countdown copy distinct from the gate-rejected copy',
        (tester) async {
      await tester.pumpWidget(_wrap(const ClosureIndicator(
        state: ClosureUiState.wait(12),
      )));
      await tester.pump();

      expect(find.textContaining('12'), findsOneWidget,
          reason: 'the wait state must surface the countdown seconds');
      expect(find.textContaining('LOOP TOO SMALL'), findsNothing,
          reason: 'the wait state must never reuse gate-rejected copy');
    });

    testWidgets('a dispatched, unresolved claim renders a claiming state',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const ClosureIndicator(state: ClosureUiState.claiming())));
      await tester.pump();

      expect(find.textContaining('CLAIMING'), findsOneWidget,
          reason: 'a dispatched-but-unresolved claim must show a pending copy');
    });

    testWidgets('a claimed outcome renders distinctly from a conquered outcome',
        (tester) async {
      await tester.pumpWidget(_wrap(const ClosureIndicator(
        state: ClosureUiState.settled(TerritoryResult.claimed),
      )));
      await tester.pump();
      final claimedText =
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join();

      await tester.pumpWidget(_wrap(const ClosureIndicator(
        state: ClosureUiState.settled(TerritoryResult.conquered),
      )));
      await tester.pump();
      final conqueredText =
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join();

      expect(claimedText, isNot(equals(conqueredText)),
          reason: 'claimed and conquered must render visibly distinct copy');
    });

    testWidgets('a disputed outcome and a failed outcome render distinctly',
        (tester) async {
      await tester.pumpWidget(_wrap(const ClosureIndicator(
        state: ClosureUiState.settled(TerritoryResult.disputed),
      )));
      await tester.pump();
      final disputedText =
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join();

      await tester.pumpWidget(_wrap(const ClosureIndicator(
        state: ClosureUiState.settled(TerritoryResult.failed),
      )));
      await tester.pump();
      final failedText =
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join();

      expect(disputedText, isNot(equals(failedText)),
          reason: 'disputed and failed must render visibly distinct copy');
    });

    testWidgets('all four geometry-gate rejection reasons render without throwing',
        (tester) async {
      for (final reason in GateRejectionReason.values) {
        if (reason == GateRejectionReason.sessionElapsed) continue;
        await tester.pumpWidget(
            _wrap(ClosureIndicator(state: ClosureUiState.gateRejected(reason))));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: '$reason must render without throwing');
      }
    });
  });
}
