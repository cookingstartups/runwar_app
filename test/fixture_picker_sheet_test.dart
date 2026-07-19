// test/fixture_picker_sheet_test.dart
//
// Coverage for the fixture picker sheet content itself, under the app's
// real theme (buildTheme()). A prior regression only showed up when the
// sheet was rendered with the app-wide ElevatedButtonThemeData in place:
// simulation_chip_hit_test.dart's MaterialApp had no theme set, so it never
// exercised the ambient minimumSize the real app applies to every
// ElevatedButton, and the sheet appeared to work there while it threw a
// layout assertion and rendered blank (scrim only, no content) on device.
// This test pumps the sheet exactly as MapScreen composes it - real
// theme, real bundled fixture list - and asserts the fixture row is
// present and its START button is actually tappable without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/theme.dart';
import 'package:runwar_app/widgets/simulation_control_panel.dart';

void main() {
  testWidgets(
    'the fixture picker sheet lists the bundled fixture as a selectable '
    'row under the real app theme, with no layout exceptions',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildTheme(),
            home: const Scaffold(
              backgroundColor: Colors.black,
              body: SimulationLauncherChip(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('SIM'), findsOneWidget);

      await tester.tap(find.text('SIM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The sheet itself must have rendered content, not just the scrim.
      expect(find.text('REPLAY SIMULATION'), findsOneWidget,
          reason: 'the sheet must show its header text, not render blank '
              'behind the modal scrim');
      expect(find.text('Valencia session (2026-07-18)'), findsOneWidget,
          reason: 'the bundled fixture (loaded via the same '
              'kBundledSimulationFixtures list the app uses) must appear '
              'as a selectable row');

      final startButton = find.widgetWithText(ElevatedButton, 'START');
      expect(startButton, findsOneWidget,
          reason: 'the fixture row must expose a tappable START control');

      // No exception (in particular, no ListTile "Trailing widget consumes
      // the entire tile width" layout assertion) must have fired while
      // building or laying out the sheet.
      expect(tester.takeException(), isNull);

      // Tapping START must not throw either - it pops the sheet and kicks
      // off the simulation start sequence.
      await tester.tap(startButton);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
