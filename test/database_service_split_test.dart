// test/database_service_split_test.dart
//
// RED phase: unit tests for Dart behavior changes required by the
// players god-table split.
//
// Strategy:
//   - getProfile / updateTrialState routing: source-inspection of
//     database_service.dart (Supabase cannot be initialised in unit tests).
//   - DailyStreak.fromMap: instantiate directly with constructed Maps.
//
// Tests will be RED because:
//   - database_service.dart still queries players directly (not child tables)
//   - DailyStreak.fromMap reads current_streak, not streak

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/models/daily_mission.dart';

void main() {
  // ---------------------------------------------------------------------------
  // getProfile nested JOIN response flattening
  // Source-inspection: after the split, database_service.dart must reference
  // player_economy, player_progress, player_streaks, and player_trial in
  // the getProfile query (nested select) and must contain a flatten step.
  // ---------------------------------------------------------------------------
  group('getProfile selects from child tables and flattens the nested response', () {
    // GIVEN database_service.dart has been updated for the split
    // WHEN the source is inspected
    // THEN getProfile selects player_economy via a nested Supabase select

    test('database_service.dart getProfile selects player_economy in the query', () {
      final file = File('lib/services/database_service.dart');
      expect(file.existsSync(), isTrue,
          reason: 'lib/services/database_service.dart must exist');
      final source = file.readAsStringSync();

      expect(
        source.contains('player_economy'),
        isTrue,
        reason:
            'getProfile must include player_economy in its Supabase select '
            'so that economy fields (credits, reputation) are returned',
      );
    });

    test('database_service.dart getProfile selects player_progress in the query', () {
      final file = File('lib/services/database_service.dart');
      final source = file.readAsStringSync();

      expect(
        source.contains('player_progress'),
        isTrue,
        reason:
            'getProfile must include player_progress in its Supabase select '
            'so that score and milestone fields are returned',
      );
    });

    test('database_service.dart getProfile selects player_streaks in the query', () {
      final file = File('lib/services/database_service.dart');
      final source = file.readAsStringSync();

      expect(
        source.contains('player_streaks'),
        isTrue,
        reason:
            'getProfile must include player_streaks in its Supabase select '
            'so that streak and freeze fields are returned',
      );
    });

    test('database_service.dart getProfile selects player_trial in the query', () {
      final file = File('lib/services/database_service.dart');
      final source = file.readAsStringSync();

      expect(
        source.contains('player_trial'),
        isTrue,
        reason:
            'getProfile must include player_trial in its Supabase select '
            'so that trial lifecycle fields are returned',
      );
    });

    // GIVEN database_service.dart has been updated for the split
    // WHEN the source is inspected
    // THEN it no longer references 'current_streak' anywhere

    test('database_service.dart no longer references the current_streak column', () {
      final file = File('lib/services/database_service.dart');
      final source = file.readAsStringSync();

      expect(
        source.contains('current_streak'),
        isFalse,
        reason:
            'no query in database_service.dart may reference current_streak '
            'after the split -- streak is the canonical column name',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // updateTrialState routes to child tables
  // ---------------------------------------------------------------------------
  group('updateTrialState routes trial fields to player_trial and streak fields to player_streaks', () {
    // GIVEN database_service.dart has been updated for the split
    // WHEN the source is inspected for updateTrialState
    // THEN it references player_trial for trial_days_remaining writes

    test('database_service.dart updateTrialState references player_trial table', () {
      final file = File('lib/services/database_service.dart');
      expect(file.existsSync(), isTrue,
          reason: 'lib/services/database_service.dart must exist');
      final source = file.readAsStringSync();

      expect(
        source.contains('player_trial'),
        isTrue,
        reason:
            'updateTrialState must route trial_days_remaining to the '
            'player_trial child table, not write to players directly',
      );
    });

    // GIVEN database_service.dart has been updated for the split
    // WHEN the source is inspected for updateTrialState
    // THEN it references player_streaks for streak writes

    test('database_service.dart updateTrialState references player_streaks table', () {
      final file = File('lib/services/database_service.dart');
      final source = file.readAsStringSync();

      expect(
        source.contains('player_streaks'),
        isTrue,
        reason:
            'updateTrialState must route streak fields to the '
            'player_streaks child table, not write to players directly',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // DailyStreak.fromMap reads 'streak' key
  // ---------------------------------------------------------------------------
  group('DailyStreak.fromMap reads the streak key from the supplied map', () {
    // GIVEN a map containing the key 'streak' with value 7
    // WHEN DailyStreak.fromMap is called
    // THEN the resulting DailyStreak has current == 7

    test('fromMap with streak key sets current field to that value', () {
      final map = <String, dynamic>{
        'streak': 7,
        'longest_streak': 10,
        'last_login_at': null,
        'milestones_claimed': <int>[],
        'subscription_tier': 'free',
      };

      final streak = DailyStreak.fromMap(map);

      expect(
        streak.current,
        equals(7),
        reason:
            'DailyStreak.fromMap must read the streak key -- '
            'the post-split player_streaks table uses streak (not current_streak)',
      );
    });

    // GIVEN a map containing ONLY 'current_streak' (old key) but NOT 'streak'
    // WHEN DailyStreak.fromMap is called
    // THEN current is 0 (old key no longer drives the value after the split)

    test('fromMap with only the old current_streak key returns current of 0', () {
      final map = <String, dynamic>{
        'current_streak': 5,
        'longest_streak': 8,
        'last_login_at': null,
        'milestones_claimed': <int>[],
        'subscription_tier': 'free',
      };

      final streak = DailyStreak.fromMap(map);

      expect(
        streak.current,
        equals(0),
        reason:
            'when only current_streak is present but not streak, fromMap must '
            'return 0 for current -- the old key must no longer drive the streak '
            'value after the players god-table split',
      );
    });

    // GIVEN a map containing both streak and current_streak with different values
    // WHEN DailyStreak.fromMap is called
    // THEN current uses the streak value (not current_streak) -- streak takes priority

    test('fromMap prefers streak over current_streak when both keys are present', () {
      final map = <String, dynamic>{
        'streak': 9,
        'current_streak': 3,
        'longest_streak': 10,
        'last_login_at': null,
        'milestones_claimed': <int>[],
        'subscription_tier': 'free',
      };

      final streak = DailyStreak.fromMap(map);

      expect(
        streak.current,
        equals(9),
        reason:
            'when both streak and current_streak are in the map, fromMap must '
            'prefer streak (the canonical post-split key) -- value 9, not 3',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // DailyStreak.fromMap source guard -- no current_streak read in implementation
  // ---------------------------------------------------------------------------
  group('DailyStreak.fromMap source does not read current_streak as the primary key', () {
    // GIVEN daily_mission.dart has been updated for the split
    // WHEN the source is inspected
    // THEN fromMap reads 'streak' (not 'current_streak') as the primary lookup key

    test("daily_mission.dart fromMap reads 'streak' key", () {
      final file = File('lib/models/daily_mission.dart');
      expect(file.existsSync(), isTrue,
          reason: 'lib/models/daily_mission.dart must exist');
      final source = file.readAsStringSync();

      expect(
        source.contains("row['streak']") ||
            source.contains('map[\'streak\']') ||
            source.contains('"streak"'),
        isTrue,
        reason:
            "daily_mission.dart fromMap must read the 'streak' key "
            "from the map -- player_streaks.streak is the canonical column",
      );
    });

    test("daily_mission.dart fromMap does not use current_streak as the primary streak source", () {
      final file = File('lib/models/daily_mission.dart');
      final source = file.readAsStringSync();

      // After the split, current_streak must not appear as a standalone primary
      // lookup. The design allows a fallback form:
      //   (map['streak'] ?? map['current_streak'] ?? 0)
      // but current_streak must come AFTER streak in any fallback chain.
      // The simplest assertion: current_streak must not be the first key read.
      final streakIdx = source.indexOf("row['streak']");
      final currentStreakIdx = source.indexOf("row['current_streak']");

      if (currentStreakIdx != -1 && streakIdx != -1) {
        // Both present -- streak must come first (it is the primary source).
        expect(
          streakIdx < currentStreakIdx,
          isTrue,
          reason:
              "if both 'streak' and 'current_streak' appear in fromMap, "
              "'streak' must be evaluated first (it is the canonical key from "
              'player_streaks after the split)',
        );
      } else if (streakIdx == -1) {
        // No 'streak' key at all -- this is a RED failure.
        fail(
          "daily_mission.dart fromMap must read row['streak'] -- "
          "the key was not found in the source",
        );
      }
      // If only streak and no current_streak, that is also valid.
    });
  });
}
