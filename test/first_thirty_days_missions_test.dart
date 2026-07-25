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
//
// Day-21 paywall + curriculum revision: capstone moves to day 21 (was 30),
// "Map the City" moves to day 17 (was 21), three new bespoke entries land
// at day 8/19/20. Day 19 ships as a reserved, honestly-incomplete stub
// (pveZoneDefense) -- the real PvE attack mechanic is a separate follow-up
// track, out of scope here.

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/models/day30_mission.dart';
import 'package:runwar_app/services/daily_missions_service.dart';
import 'package:runwar_app/services/first_thirty_days_missions_service.dart';
import 'package:runwar_app/utils/runwar_constants.dart';

void main() {
  group('curriculum catalogue', () {
    test('has exactly 15 ordered entries after the day-21 revision', () {
      expect(FirstThirtyDaysMissionsService.curriculum.length, equals(15));
    });

    test('slots stay unique across the whole curriculum', () {
      final slots =
          FirstThirtyDaysMissionsService.curriculum.map((m) => m.slot).toList();
      expect(slots.toSet().length, equals(slots.length),
          reason: 'no two curriculum entries may share a slot number');
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

    test('slot 8 still reuses the existing Day-7 milestone system', () {
      final bySlot = {
        for (final m in FirstThirtyDaysMissionsService.curriculum) m.slot: m
      };
      expect(bySlot[8]!.hook, equals(Day30CompletionHook.milestone));
      expect(bySlot[8]!.milestoneDay, equals(7));
      expect(bySlot[8]!.day, equals(7));
    });
  });

  group('R6-AC1: capstone day moves from 30 to 21', () {
    test('capstone entry (slot 12) day equals kFirstThirtyDaysCapstoneDay, '
        'not 30', () {
      final capstone = FirstThirtyDaysMissionsService.curriculum
          .firstWhere((m) => m.slot == 12);
      expect(capstone.day, equals(kFirstThirtyDaysCapstoneDay));
      expect(capstone.day, equals(21));
    });
  });

  group('R5-AC1: capstone completion decoupled from the streak-milestone '
      'system', () {
    test('capstone entry uses teachingAcknowledgment, not milestone', () {
      final capstone = FirstThirtyDaysMissionsService.curriculum
          .firstWhere((m) => m.slot == 12);
      expect(capstone.hook, equals(Day30CompletionHook.teachingAcknowledgment),
          reason: 'capstone completion must not read milestonesClaimed / '
              'Clock C');
      expect(capstone.milestoneDay, isNull,
          reason: 'milestoneDay is no longer relevant once the hook stops '
              'being milestone');
    });
  });

  group('R6-AC2: "Map the City" day moves from 21 to 17', () {
    test('slot 11 day equals 17, dailyMissionSlug unchanged', () {
      final mapTheCity = FirstThirtyDaysMissionsService.curriculum
          .firstWhere((m) => m.slot == 11);
      expect(mapTheCity.day, equals(17));
      expect(mapTheCity.hook, equals(Day30CompletionHook.dailyMissionSlug));
      expect(mapTheCity.dailyMissionSlug, equals('enter_new_zone'));
    });
  });

  group('R6-AC3: new bespoke entries at Day 8, Day 19, Day 20', () {
    test('exactly one entry exists at each of day 8, 19, and 20', () {
      final curriculum = FirstThirtyDaysMissionsService.curriculum;
      expect(curriculum.where((m) => m.day == 8).length, equals(1));
      expect(curriculum.where((m) => m.day == 19).length, equals(1));
      expect(curriculum.where((m) => m.day == 20).length, equals(1));
    });

    test('the three new entries use slots that do not collide with slots '
        '1-12', () {
      final newSlots = FirstThirtyDaysMissionsService.curriculum
          .where((m) => m.day == 8 || m.day == 19 || m.day == 20)
          .map((m) => m.slot)
          .toSet();
      expect(newSlots.length, equals(3));
      for (final slot in newSlots) {
        expect(slot, greaterThan(12),
            reason: 'new entries must not renumber any existing slot 1-12');
      }
    });
  });

  group('R2-AC1/AC2: Day-8 "since unlock day" qualifier', () {
    test('Day-8 entry reuses invite_friend with the qualifier set', () {
      final day8 = FirstThirtyDaysMissionsService.curriculum
          .firstWhere((m) => m.day == 8);
      expect(day8.hook, equals(Day30CompletionHook.dailyMissionSlug));
      expect(day8.dailyMissionSlug, equals('invite_friend'));
      expect(day8.slugCompletionSinceUnlockDay, isTrue,
          reason: 'Day-8 must only count a referral completed on/after '
              'calendar day 8, not any historical invite_friend completion');
    });

    test('pre-existing dailyMissionSlug entries keep the unqualified '
        '"any historical completion" default', () {
      final curriculum = FirstThirtyDaysMissionsService.curriculum;
      final unqualifiedSlugs = {
        'streak_check_in',
        'defend_zone',
        'use_superpower',
        'enter_new_zone',
      };
      // Day-5 "Bring a Rival" also reuses invite_friend but must stay
      // unqualified -- distinguished from Day-8 by day, not slug alone.
      final day5 = curriculum.firstWhere((m) => m.day == 5);
      expect(day5.dailyMissionSlug, equals('invite_friend'));
      expect(day5.slugCompletionSinceUnlockDay, isFalse,
          reason: 'Day-5\'s own completion must remain unaffected by the '
              'Day-8 qualifier');

      for (final slug in unqualifiedSlugs) {
        final entry =
            curriculum.firstWhere((m) => m.dailyMissionSlug == slug);
        expect(entry.slugCompletionSinceUnlockDay, isFalse,
            reason: '$slug\'s entry must keep today\'s unqualified '
                '"any historical completion" semantics (regression lock)');
      }
    });
  });

  group('R4-AC1: Day-20 "Unite Your Empire" uses teachingAcknowledgment', () {
    test('Day-20 entry matches Day-4\'s completion pattern', () {
      final day20 = FirstThirtyDaysMissionsService.curriculum
          .firstWhere((m) => m.day == 20);
      expect(day20.hook, equals(Day30CompletionHook.teachingAcknowledgment));
    });
  });

  group('Day-19 stub: unlocks on schedule, no completion hook wired yet '
      '(R3 out of scope, R6-AC3 in scope)', () {
    test('Day-19 entry uses the reserved pveZoneDefense hook', () {
      final day19 = FirstThirtyDaysMissionsService.curriculum
          .firstWhere((m) => m.day == 19);
      expect(day19.hook, equals(Day30CompletionHook.pveZoneDefense));
    });

    test('Day-19 unlocks at dayIndex 19 like any other curriculum entry', () {
      final day19 = FirstThirtyDaysMissionsService.curriculum
          .firstWhere((m) => m.day == 19);
      expect(FirstThirtyDaysMissionsService.isUnlocked(day19, 19), isTrue);
      expect(FirstThirtyDaysMissionsService.isUnlocked(day19, 18), isFalse);
    });
  });

  group('R8-AC1: shared kFirstThirtyDaysCapstoneDay constant', () {
    test('dailyCadenceThroughDay resolves to the shared constant, not an '
        'independent literal', () {
      expect(FirstThirtyDaysMissionsService.dailyCadenceThroughDay,
          equals(kFirstThirtyDaysCapstoneDay));
      expect(kFirstThirtyDaysCapstoneDay, equals(21));
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

  group('fullSeries (R6-AC4: capstone at day == 21, exactly once)', () {
    test('includes the capstone exactly once at day 21, not duplicated or '
        'dropped by the append clause\'s strict ">" filter', () {
      final series = FirstThirtyDaysMissionsService.fullSeries();
      final day21Entries = series.where((m) => m.day == 21).toList();
      expect(day21Entries.length, equals(1),
          reason: 'day 21 must resolve to exactly one entry: the capstone, '
              'not also a resolvedDaily filler');
      expect(day21Entries.first.bespoke, isTrue);
      expect(day21Entries.first.hook,
          equals(Day30CompletionHook.teachingAcknowledgment));
    });

    test('no longer produces a day-30 entry at all (capstone moved inside '
        'the window)', () {
      final series = FirstThirtyDaysMissionsService.fullSeries();
      expect(series.where((m) => m.day == 30), isEmpty,
          reason: 'the append clause (day > dailyCadenceThroughDay) must '
              'contribute zero entries once no curriculum entry has a day '
              'greater than 21');
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
