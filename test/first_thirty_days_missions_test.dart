// test/first_thirty_days_missions_test.dart
//
// Unit tests for the first-30-days curriculum model/service skeleton
// (rw_app-T0593). Covers the pure unlock-by-day logic and the catalogue's
// completion-hook mapping. Supabase-touching paths (getState) are not
// exercised here, matching this repo's convention for services that call
// Supabase.instance.client directly (see test/daily_missions_test.dart).
//
// Cadence revision (operator directive, 2026-07-24, proposal §7): also
// covers [FirstThirtyDaysMissionsService.dailySeries]/[fullSeries] (the
// daily no-gap cadence fill) and
// [DailyMissionsService.previewSlateForDate] (the pure, DB-free resolution
// path used to fill non-bespoke days).

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/models/day30_mission.dart';
import 'package:runwar_app/services/daily_missions_service.dart';
import 'package:runwar_app/services/first_thirty_days_missions_service.dart';

void main() {
  group('curriculum catalogue', () {
    test('has exactly 12 ordered entries', () {
      expect(FirstThirtyDaysMissionsService.curriculum.length, equals(12));
    });

    test('slots are 1..12 in order', () {
      final slots =
          FirstThirtyDaysMissionsService.curriculum.map((m) => m.slot).toList();
      expect(slots, equals(List.generate(12, (i) => i + 1)));
    });

    test('unlock days are non-decreasing across the curriculum', () {
      final days =
          FirstThirtyDaysMissionsService.curriculum.map((m) => m.day).toList();
      for (var i = 1; i < days.length; i++) {
        expect(days[i], greaterThanOrEqualTo(days[i - 1]),
            reason: 'curriculum must unlock in non-decreasing day order');
      }
    });

    test('slots 1-2 reuse first-mission-onboarding, not new logic', () {
      final slot1 = FirstThirtyDaysMissionsService.curriculum[0];
      final slot2 = FirstThirtyDaysMissionsService.curriculum[1];
      expect(slot1.hook, equals(Day30CompletionHook.firstMissionOnboarding));
      expect(slot1.profileCompletionField, equals('first_mission_completed_at'));
      expect(slot2.hook, equals(Day30CompletionHook.firstMissionOnboarding));
      expect(slot2.profileCompletionField, equals('first_attack_completed_at'));
    });

    test('referral mission lands at slot 7 / day 5, reusing invite_friend', () {
      final referral = FirstThirtyDaysMissionsService.curriculum
          .firstWhere((m) => m.slot == 7);
      expect(referral.day, equals(5));
      expect(referral.hook, equals(Day30CompletionHook.dailyMissionSlug));
      expect(referral.dailyMissionSlug, equals('invite_friend'));
    });

    test('slots 9-11 reuse existing daily-mission slugs as hooks', () {
      final bySlot = {
        for (final m in FirstThirtyDaysMissionsService.curriculum) m.slot: m
      };
      expect(bySlot[9]!.hook, equals(Day30CompletionHook.dailyMissionSlug));
      expect(bySlot[9]!.dailyMissionSlug, equals('defend_zone'));
      expect(bySlot[10]!.hook, equals(Day30CompletionHook.dailyMissionSlug));
      expect(bySlot[10]!.dailyMissionSlug, equals('use_superpower'));
      expect(bySlot[11]!.hook, equals(Day30CompletionHook.dailyMissionSlug));
      expect(bySlot[11]!.dailyMissionSlug, equals('enter_new_zone'));
    });

    test('slots 3-5 are teaching-only with no reward hook', () {
      final teachingSlots = FirstThirtyDaysMissionsService.curriculum
          .where((m) => m.slot >= 3 && m.slot <= 5);
      for (final m in teachingSlots) {
        expect(m.hook, equals(Day30CompletionHook.teachingAcknowledgment));
        expect(m.dailyMissionSlug, isNull);
        expect(m.profileCompletionField, isNull);
        expect(m.milestoneDay, isNull);
      }
    });

    test('slots 8 and 12 reuse the existing milestone system at day 7/30', () {
      final bySlot = {
        for (final m in FirstThirtyDaysMissionsService.curriculum) m.slot: m
      };
      expect(bySlot[8]!.hook, equals(Day30CompletionHook.milestone));
      expect(bySlot[8]!.milestoneDay, equals(7));
      expect(bySlot[8]!.day, equals(7));
      expect(bySlot[12]!.hook, equals(Day30CompletionHook.milestone));
      expect(bySlot[12]!.milestoneDay, equals(30));
      expect(bySlot[12]!.day, equals(30));
    });
  });

  group('dayIndexFor (unlock-by-day pure logic)', () {
    test('returns 0 when trial has not started', () {
      expect(FirstThirtyDaysMissionsService.dayIndexFor(null), equals(0));
    });

    test('returns 0 on the same calendar day as trial start', () {
      final start = DateTime.utc(2026, 7, 1, 8);
      final now = DateTime.utc(2026, 7, 1, 22);
      expect(
        FirstThirtyDaysMissionsService.dayIndexFor(start, now: now),
        equals(0),
      );
    });

    test('returns 5 exactly five calendar days after trial start', () {
      final start = DateTime.utc(2026, 7, 1);
      final now = DateTime.utc(2026, 7, 6);
      expect(
        FirstThirtyDaysMissionsService.dayIndexFor(start, now: now),
        equals(5),
      );
    });

    test('returns 30 at exactly the Day-30 capstone', () {
      final start = DateTime.utc(2026, 6, 1);
      final now = DateTime.utc(2026, 7, 1);
      expect(
        FirstThirtyDaysMissionsService.dayIndexFor(start, now: now),
        equals(30),
      );
    });

    test('clamps negative diffs (clock skew) to 0', () {
      final start = DateTime.utc(2026, 7, 10);
      final now = DateTime.utc(2026, 7, 1);
      expect(
        FirstThirtyDaysMissionsService.dayIndexFor(start, now: now),
        equals(0),
      );
    });
  });

  group('isUnlocked', () {
    const mission = Day30Mission(
      slot: 9,
      day: 10,
      title: "Defend What's Yours",
      teaches: 'Defense / dispute mechanic',
      hook: Day30CompletionHook.dailyMissionSlug,
      dailyMissionSlug: 'defend_zone',
    );

    test('is unlocked once dayIndex reaches the threshold', () {
      expect(FirstThirtyDaysMissionsService.isUnlocked(mission, 10), isTrue);
    });

    test('is unlocked past the threshold', () {
      expect(FirstThirtyDaysMissionsService.isUnlocked(mission, 15), isTrue);
    });

    test('is not unlocked before the threshold', () {
      expect(FirstThirtyDaysMissionsService.isUnlocked(mission, 9), isFalse);
    });
  });

  group('Day30MissionState.isCurrent', () {
    const mission = Day30Mission(
      slot: 3,
      day: 1,
      title: 'Hold the Line',
      teaches: 'Zone influence levels',
      hook: Day30CompletionHook.teachingAcknowledgment,
    );

    test('true when unlocked and not completed', () {
      const state = Day30MissionState(
        mission: mission,
        unlocked: true,
        completed: false,
      );
      expect(state.isCurrent, isTrue);
    });

    test('false when unlocked and completed', () {
      const state = Day30MissionState(
        mission: mission,
        unlocked: true,
        completed: true,
      );
      expect(state.isCurrent, isFalse);
    });

    test('false when locked', () {
      const state = Day30MissionState(
        mission: mission,
        unlocked: false,
        completed: false,
      );
      expect(state.isCurrent, isFalse);
    });
  });

  group('dailySeries (daily-cadence fill, proposal §7)', () {
    test('covers every day 0..21 with no gaps', () {
      final series = FirstThirtyDaysMissionsService.dailySeries();
      final coveredDays = series.map((m) => m.day).toSet();
      for (var day = 0; day <= 21; day++) {
        expect(coveredDays.contains(day), isTrue,
            reason: 'day $day must have a curriculum slot (no gaps allowed)');
      }
    });

    test('bespoke days return the exact original bespoke entries', () {
      final series = FirstThirtyDaysMissionsService.dailySeries();
      final bespokeDays = FirstThirtyDaysMissionsService.curriculum
          .where((m) => m.day <= 21)
          .map((m) => m.day)
          .toSet();

      for (final day in bespokeDays) {
        final entriesForDay = series.where((m) => m.day == day).toList();
        final expectedForDay = FirstThirtyDaysMissionsService.curriculum
            .where((m) => m.day == day)
            .toList();
        expect(entriesForDay.length, equals(expectedForDay.length));
        for (final entry in entriesForDay) {
          expect(entry.bespoke, isTrue);
          expect(entry.hook, isNot(equals(Day30CompletionHook.resolvedDaily)));
        }
      }
    });

    test('non-bespoke days are marked bespoke:false with resolvedDaily hook',
        () {
      final series = FirstThirtyDaysMissionsService.dailySeries();
      final bespokeDays = FirstThirtyDaysMissionsService.curriculum
          .where((m) => m.day <= 21)
          .map((m) => m.day)
          .toSet();

      final nonBespokeDays =
          List.generate(22, (i) => i).where((d) => !bespokeDays.contains(d));

      expect(nonBespokeDays, isNotEmpty,
          reason: 'sanity check: some days must be cadence-fill days');

      for (final day in nonBespokeDays) {
        final entry = series.firstWhere((m) => m.day == day);
        expect(entry.bespoke, isFalse);
        expect(entry.hook, equals(Day30CompletionHook.resolvedDaily));
      }
    });

    test('slots stay unique across the whole series', () {
      final series = FirstThirtyDaysMissionsService.dailySeries();
      final slots = series.map((m) => m.slot).toList();
      expect(slots.toSet().length, equals(slots.length));
    });
  });

  group('fullSeries', () {
    test('includes the Day-30 capstone outside the 21-day core window', () {
      final series = FirstThirtyDaysMissionsService.fullSeries();
      final day30 = series.where((m) => m.day == 30).toList();
      expect(day30.length, equals(1));
      expect(day30.first.hook, equals(Day30CompletionHook.milestone));
      expect(day30.first.milestoneDay, equals(30));
    });

    test('still covers every day 0..21 with no gaps', () {
      final series = FirstThirtyDaysMissionsService.fullSeries();
      final coveredDays = series.map((m) => m.day).toSet();
      for (var day = 0; day <= 21; day++) {
        expect(coveredDays.contains(day), isTrue);
      }
    });
  });

  group('DailyMissionsService.previewSlateForDate (pure resolution path)',
      () {
    test('returns a real, non-empty mission slate for an arbitrary date', () {
      final slate = DailyMissionsService.instance.previewSlateForDate(
        'test-user-1',
        DateTime.utc(2026, 7, 10),
      );
      expect(slate, isNotEmpty);
      expect(slate.first.slug, isNotEmpty);
    });

    test('is deterministic for the same userId + date + streak', () {
      final date = DateTime.utc(2026, 8, 3);
      final first = DailyMissionsService.instance
          .previewSlateForDate('test-user-2', date, streak: 5);
      final second = DailyMissionsService.instance
          .previewSlateForDate('test-user-2', date, streak: 5);
      expect(first.map((m) => m.slug).toList(),
          equals(second.map((m) => m.slug).toList()));
    });

    test('works for a date far in the past (never opened as "today")', () {
      final slate = DailyMissionsService.instance.previewSlateForDate(
        'test-user-3',
        DateTime.utc(2020, 1, 1),
      );
      expect(slate, isNotEmpty);
    });
  });
}
