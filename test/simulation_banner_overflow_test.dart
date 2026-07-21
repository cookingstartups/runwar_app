// test/simulation_banner_overflow_test.dart
//
// SPEC-0144 Part C: SimulationActiveBanner must not overflow its Row on a
// narrow screen (~360dp) when the fixture label plus progress counts plus
// the ABORT affordance exceed available width. No FlutterMap descendant
// here, so none of flutter-test-patterns.md's Timer-teardown guidance
// applies - this is a genuine testWidgets runtime assertion per
// requirements.md section 7 items 8-9.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/providers/run_simulation_provider.dart';
import 'package:runwar_app/widgets/simulation_control_panel.dart';

class _FixedSimulationNotifier extends RunSimulationNotifier {
  _FixedSimulationNotifier(Ref ref, RunSimulationState fixed) : super(ref) {
    state = fixed;
  }
}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required String fixtureLabel,
  required int emittedCount,
  required int totalCount,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runSimulationProvider.overrideWith(
          (ref) => _FixedSimulationNotifier(
            ref,
            RunSimulationState(
              status: SimulationStatus.running,
              fixtureLabel: fixtureLabel,
              emittedCount: emittedCount,
              totalCount: totalCount,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: Scaffold(
            body: SizedBox(
              width: 360,
              child: const SimulationActiveBanner(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SPEC-0144 AC-8: no RenderFlex overflow at narrow width', () {
    testWidgets('a long fixture label at 360dp does not throw a render overflow exception', (tester) async {
      await _pumpBanner(
        tester,
        fixtureLabel: 'Valencia session (2026-07-18) extended replay fixture name',
        emittedCount: 842,
        totalCount: 1200,
      );

      expect(tester.takeException(), isNull,
          reason: 'the banner must degrade gracefully (ellipsis) instead of forcing the Row past '
              'its available 360dp width');
    });
  });

  group('SPEC-0144 AC-9: text truncates, ABORT stays visible', () {
    testWidgets('the fixture-label Text truncates with an ellipsis and ABORT remains hit-testable', (tester) async {
      await _pumpBanner(
        tester,
        fixtureLabel: 'Valencia session (2026-07-18) extended replay fixture name',
        emittedCount: 842,
        totalCount: 1200,
      );

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      final labelText = textWidgets.firstWhere(
        (w) => (w.data ?? '').startsWith('SIMULATION -'),
      );
      expect(labelText.overflow, TextOverflow.ellipsis,
          reason: 'the fixture-label Text must truncate rather than overflow');
      expect(labelText.maxLines, 1);

      expect(find.text('ABORT'), findsOneWidget,
          reason: 'the ABORT affordance must remain visible even when the label truncates');
    });
  });
}
