// test/widgets/first_30_days_stepper_test.dart
//
// Covers the operator-chosen hybrid design ("Option E") for the
// first-30-days curriculum HUD stepper (rw_app-T0593):
//   ~/AIOS/infra/meta/specs/runwar/first-30-days-missions/mockups/stepper-mockup-v1.html#e
//
//   1. Default/collapsed state renders Variant A's dot row.
//   2. Tapping it opens Variant B's bottom sheet, with the current mission
//      highlighted — including a resolved-daily filler day, which must
//      render Day30MissionState.displayTitle (the resolved mission's real
//      title), never the generic bespoke==false fallback copy.
//   3. While the sheet is open, the HUD swaps to Variant C's segmented bar.
//   4. Closing the sheet reverts the HUD to Variant A's dot row.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/models/day30_mission.dart';
import 'package:runwar_app/models/daily_mission.dart';
import 'package:runwar_app/providers/first_thirty_days_missions_provider.dart';
import 'package:runwar_app/theme.dart';
import 'package:runwar_app/widgets/first_30_days_stepper.dart';

import '../_helpers/test_container.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _userId = 'player-first30-1';

Day30Mission _bespokeMission({
  required int slot,
  required int day,
  required String title,
}) =>
    Day30Mission(
      slot: slot,
      day: day,
      title: title,
      teaches: 'teaches something',
      hook: Day30CompletionHook.teachingAcknowledgment,
      bespoke: true,
    );

Day30Mission _fillerMission({required int slot, required int day}) =>
    Day30Mission(
      slot: slot,
      day: day,
      title: "Today's Challenge",
      teaches: "Complete one of today's missions",
      hook: Day30CompletionHook.resolvedDaily,
      bespoke: false,
    );

/// Two completed bespoke days, one resolved-daily "current" filler day
/// (with its real content already resolved), and one locked upcoming day.
List<Day30MissionState> _fixtureStates() {
  const resolvedMission = DailyMission(
    slug: 'run_2km',
    title: 'Run 2 km Today',
    mechanic: 'distance running',
    rewardCredits: 50,
    targetValue: 2000,
    weight: 1,
    isHard: false,
  );

  return [
    Day30MissionState(
      mission: _bespokeMission(slot: 1, day: 0, title: 'Claim Your First Territory'),
      unlocked: true,
      completed: true,
    ),
    Day30MissionState(
      mission: _bespokeMission(slot: 3, day: 1, title: 'Hold the Line'),
      unlocked: true,
      completed: true,
    ),
    // The current mission: an unlocked, incomplete, resolved-daily filler
    // day — must render via displayTitle ("Run 2 km Today"), not the
    // generic "Today's Challenge" fallback copy.
    Day30MissionState(
      mission: _fillerMission(slot: 13, day: 2),
      unlocked: true,
      completed: false,
      resolvedMission: resolvedMission,
    ),
    Day30MissionState(
      mission: _bespokeMission(slot: 5, day: 3, title: 'Know the Rules'),
      unlocked: false,
      completed: false,
    ),
  ];
}

Widget _wrap(Widget child, {required ProviderContainer container}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(backgroundColor: kBg, body: child),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('First30DaysStepper', () {
    testWidgets('default/collapsed state renders the Variant A dot row',
        (tester) async {
      final container = makeTestContainer(overrides: [
        firstThirtyDaysMissionsProvider(_userId)
            .overrideWith((_) async => _fixtureStates()),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const First30DaysStepper(userId: _userId), container: container),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('first30_stepper_dot_row')), findsOneWidget,
          reason: 'collapsed HUD must show the minimalist dot row');
      expect(find.byKey(const Key('first30_stepper_segmented_bar')), findsNothing,
          reason: 'the segmented bar must not render until the sheet opens');
    });

    testWidgets(
        'tapping opens the mission-list sheet with the resolved filler day '
        'highlighted, showing its resolved displayTitle', (tester) async {
      final container = makeTestContainer(overrides: [
        firstThirtyDaysMissionsProvider(_userId)
            .overrideWith((_) async => _fixtureStates()),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const First30DaysStepper(userId: _userId), container: container),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('first30_stepper_tap_target')));
      await tester.pumpAndSettle();

      // The sheet is open and lists the resolved daily mission's real
      // title, not the generic "Today's Challenge" fallback.
      expect(find.text('Run 2 km Today'), findsOneWidget,
          reason: 'sheet must render displayTitle for a resolved-daily '
              'filler day, not the raw bespoke==false fallback title');
      expect(find.text("Today's Challenge"), findsNothing,
          reason: 'the generic fallback copy must never render once the '
              'entry has a resolvedMission');

      // That resolved entry is the current (unlocked, incomplete) mission —
      // it must be the highlighted row.
      final activeRow = find.byKey(const Key('first30_sheet_active_row'));
      expect(activeRow, findsOneWidget,
          reason: 'exactly one row must be highlighted as the active mission');
      expect(
        find.descendant(of: activeRow, matching: find.text('Run 2 km Today')),
        findsOneWidget,
        reason: 'the highlighted row must be the resolved filler day, not a '
            'bespoke completed/locked entry',
      );
    });

    testWidgets(
        'HUD swaps to the Variant C segmented bar while the sheet is open, '
        'then reverts to the Variant A dot row once it closes', (tester) async {
      final container = makeTestContainer(overrides: [
        firstThirtyDaysMissionsProvider(_userId)
            .overrideWith((_) async => _fixtureStates()),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const First30DaysStepper(userId: _userId), container: container),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('first30_stepper_tap_target')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('first30_stepper_segmented_bar')), findsOneWidget,
          reason: 'the HUD element must switch to the segmented-bar styling '
              'for the duration the sheet is open');
      expect(find.byKey(const Key('first30_stepper_dot_row')), findsNothing,
          reason: 'the dot row must not render while the sheet is open');

      // Dismiss the sheet by tapping the modal barrier.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('first30_stepper_dot_row')), findsOneWidget,
          reason: 'the HUD must revert to the dot row once the sheet closes');
      expect(find.byKey(const Key('first30_stepper_segmented_bar')), findsNothing,
          reason: 'the segmented bar must not remain after the sheet closes');
    });
  });
}
