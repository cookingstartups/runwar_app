// test/widgets/cancel_run_sheet_test.dart
//
// RED phase: lib/widgets/cancel_run_sheet.dart does not exist yet.
// Locked to Option C (the bottom sheet) - blocking, matching the existing
// DailyMissionsSheet idiom - "Keep Running" dismisses with no state change,
// "Cancel Run" is the only action that invokes the cancel callback.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/widgets/cancel_run_sheet.dart';

Future<void> _openSheet(WidgetTester tester, {required double distanceM}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => CancelRunSheet(currentDistanceM: distanceM, onCancelConfirmed: () {}),
            ),
            child: const Text('open'),
          ),
        ),
      );
    }),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('CancelRunSheet (Option C, locked)', () {
    testWidgets('reads "Cancel This Run?" with Keep Running and Cancel Run actions',
        (tester) async {
      await _openSheet(tester, distanceM: 2400);

      expect(find.textContaining('Cancel This Run?'), findsOneWidget);
      expect(find.textContaining('Keep Running'), findsOneWidget);
      expect(find.textContaining('Cancel Run'), findsOneWidget);
    });

    testWidgets('tapping Keep Running dismisses the sheet without invoking the cancel callback',
        (tester) async {
      var cancelled = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => CancelRunSheet(
                    currentDistanceM: 2400,
                    onCancelConfirmed: () => cancelled = true,
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

      await tester.tap(find.textContaining('Keep Running'));
      await tester.pumpAndSettle();

      expect(cancelled, isFalse,
          reason: 'Keep Running must never invoke the cancel callback');
      expect(find.byType(CancelRunSheet), findsNothing,
          reason: 'Keep Running must dismiss the sheet');
    });

    testWidgets('tapping Cancel Run invokes the cancel callback exactly once',
        (tester) async {
      var cancelCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => CancelRunSheet(
                    currentDistanceM: 2400,
                    onCancelConfirmed: () => cancelCount++,
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

      await tester.tap(find.textContaining('Cancel Run'));
      await tester.pumpAndSettle();

      expect(cancelCount, 1,
          reason: 'Cancel Run must invoke the cancel callback exactly once');
    });
  });
}
