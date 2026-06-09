// test/daily_missions_test.dart
//
// RED phase: tests for daily missions player_id fix and streak provider rewrite.
// Each test maps to exactly one GIVEN/WHEN/THEN from requirements.md.
//
// Strategy:
//   - DatabaseService methods call Supabase.instance.client directly, so they
//     cannot be invoked in unit tests without SDK init.
//     Implementation is required to expose @visibleForTesting constants for the
//     column names and conflict key used in each method so tests can assert the
//     correct values without hitting the network.
//   - DailyStreak.fromMap is pure (no Supabase) and tested directly.
//   - dailyStreakProvider select string is exposed as a @visibleForTesting constant.
//
// @visibleForTesting contracts required from implementation:
//
//   In lib/services/database_service.dart:
//     @visibleForTesting
//     const String kGetDailyMissionsFilterColumn = 'player_id';
//
//     @visibleForTesting
//     const String kUpsertMissionProgressOnConflict = 'player_id,mission_id,date';
//
//     @visibleForTesting
//     const String kUpsertMissionProgressPlayerKey = 'player_id';
//
//     @visibleForTesting
//     const String kUpsertMissionProgressMissionKey = 'mission_id';
//
//   In lib/providers/daily_missions_provider.dart:
//     @visibleForTesting
//     const String kDailyStreakSelectString =
//         'id, player_streaks(streak, longest_streak, last_login_at, milestones_claimed), '
//         'player_economy(subscription_tier)';
//
// These constants do NOT exist yet -> tests fail with compile errors (RED).

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/models/daily_mission.dart';
import 'package:runwar_app/providers/daily_missions_provider.dart'
    show kDailyStreakSelectString;
import 'package:runwar_app/services/database_service.dart'
    show
        kGetDailyMissionsFilterColumn,
        kUpsertMissionProgressOnConflict,
        kUpsertMissionProgressPlayerKey,
        kUpsertMissionProgressMissionKey;

void main() {
  // ---------------------------------------------------------------------------
  // getDailyMissions filter column
  // ---------------------------------------------------------------------------

  group('getDailyMissions cache filter column', () {
    // GIVEN a player whose progress rows have player_id = 'abc-123' and user_id = NULL
    // WHEN getDailyMissions is called
    // THEN the query filters by 'player_id' not 'user_id'
    test('filters daily_mission_progress by player_id not user_id', () {
      expect(
        kGetDailyMissionsFilterColumn,
        equals('player_id'),
        reason: 'getDailyMissions must use player_id; user_id is NULL on all '
            'live rows, so filtering on user_id always returns empty',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // upsertMissionProgress payload keys and onConflict
  // ---------------------------------------------------------------------------

  group('upsertMissionProgress payload uses player_id not user_id', () {
    // GIVEN a row map: { 'player_id': 'abc-123', 'slug': 'claim_one_zone', ... }
    // WHEN upsertMissionProgress builds the payload
    // THEN the player identifier key sent to Supabase is 'player_id'
    test('player identifier key in upsert payload is player_id', () {
      expect(
        kUpsertMissionProgressPlayerKey,
        equals('player_id'),
        reason: 'upsert payload must use player_id; sending user_id would '
            'reference a nullable legacy column',
      );
    });
  });

  group('upsertMissionProgress payload resolves mission_id not slug', () {
    // GIVEN a row map containing 'slug': 'claim_one_zone'
    // WHEN upsertMissionProgress builds the payload for Supabase
    // THEN the payload key for the definition reference is 'mission_id' (INT FK)
    // AND 'slug' is stripped before the write
    test('definition reference key in upsert payload is mission_id not slug', () {
      expect(
        kUpsertMissionProgressMissionKey,
        equals('mission_id'),
        reason: 'live daily_mission_progress has an INT FK mission_id; '
            'slug is stripped before write and used only for definition lookup',
      );
    });
  });

  group('upsertMissionProgress uses correct onConflict constraint', () {
    // GIVEN an upsert to daily_mission_progress
    // WHEN onConflict is specified
    // THEN it is 'player_id,mission_id,date' matching the live UNIQUE constraint
    // AND it is NOT 'user_id,date,slug' which does not exist on the live table
    test('onConflict string matches live UNIQUE(player_id,mission_id,date)', () {
      expect(
        kUpsertMissionProgressOnConflict,
        equals('player_id,mission_id,date'),
        reason: 'UNIQUE(player_id,mission_id,date) is the live constraint from '
            '0027_daily_missions.sql; the old user_id,date,slug does not exist',
      );
    });

    test('onConflict string does not reference the legacy user_id,date,slug', () {
      expect(
        kUpsertMissionProgressOnConflict,
        isNot(contains('user_id')),
        reason: 'user_id,date,slug constraint never existed; referencing it '
            'causes PostgREST to throw on every upsert call',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // dailyStreakProvider select string
  // ---------------------------------------------------------------------------

  group('dailyStreakProvider uses nested join on player_streaks and player_economy', () {
    // GIVEN a player with player_id = 'abc-123'
    // WHEN dailyStreakProvider resolves the query
    // THEN the select string joins player_streaks and player_economy
    // AND does NOT reference players.current_streak (dropped by migration 0044)
    test('select string includes player_streaks nested join', () {
      expect(
        kDailyStreakSelectString,
        contains('player_streaks('),
        reason: 'streak data moved to player_streaks after BL-02; '
            'querying players.current_streak always returns NULL',
      );
    });

    test('select string includes player_economy nested join', () {
      expect(
        kDailyStreakSelectString,
        contains('player_economy('),
        reason: 'subscription_tier lives in player_economy since migration 0035',
      );
    });

    test('select string does not reference dropped players.current_streak column', () {
      expect(
        kDailyStreakSelectString,
        isNot(contains('current_streak')),
        reason: 'migration 0044 dropped current_streak from players table; '
            'querying it causes a PostgREST column-not-found error',
      );
    });

    test('select string reads streak from player_streaks sub-map', () {
      expect(
        kDailyStreakSelectString,
        contains('streak'),
        reason: 'dailyStreakProvider must request streak from player_streaks',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // DailyStreak.fromMap - nested join shape (Map)
  // ---------------------------------------------------------------------------

  group('DailyStreak.fromMap flattens nested join Map shape', () {
    // GIVEN a Supabase nested-join row with player_streaks and player_economy as Maps
    // WHEN DailyStreak.fromMap is called
    // THEN current, longest, lastLoginAt, milestonesClaimed, subscriptionTier
    //      are all read from the nested sub-maps
    test('reads streak from player_streaks nested Map', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': {
          'streak': 7,
          'longest_streak': 14,
          'last_login_at': '2026-06-09T08:00:00.000Z',
          'milestones_claimed': [3, 7],
        },
        'player_economy': {'subscription_tier': 'pro'},
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.current, equals(7),
          reason: 'current must come from player_streaks.streak not players.current_streak');
    });

    test('reads longest from player_streaks nested Map', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': {
          'streak': 7,
          'longest_streak': 14,
          'last_login_at': '2026-06-09T08:00:00.000Z',
          'milestones_claimed': [3, 7],
        },
        'player_economy': {'subscription_tier': 'pro'},
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.longest, equals(14),
          reason: 'longest must come from player_streaks.longest_streak');
    });

    test('reads milestonesClaimed from player_streaks nested Map', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': {
          'streak': 7,
          'longest_streak': 14,
          'last_login_at': '2026-06-09T08:00:00.000Z',
          'milestones_claimed': [3, 7],
        },
        'player_economy': {'subscription_tier': 'pro'},
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.milestonesClaimed, equals([3, 7]),
          reason: 'milestonesClaimed must come from player_streaks sub-map');
    });

    test('reads subscriptionTier from player_economy nested Map', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': {
          'streak': 7,
          'longest_streak': 14,
          'last_login_at': '2026-06-09T08:00:00.000Z',
          'milestones_claimed': [3, 7],
        },
        'player_economy': {'subscription_tier': 'pro'},
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.subscriptionTier, equals('pro'),
          reason: 'subscriptionTier must come from player_economy sub-map');
    });

    test('reads lastLoginAt from player_streaks nested Map', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': {
          'streak': 7,
          'longest_streak': 14,
          'last_login_at': '2026-06-09T08:00:00.000Z',
          'milestones_claimed': [3, 7],
        },
        'player_economy': {'subscription_tier': 'pro'},
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.lastLoginAt, equals(DateTime.parse('2026-06-09T08:00:00.000Z')),
          reason: 'lastLoginAt must come from player_streaks.last_login_at');
    });
  });

  // ---------------------------------------------------------------------------
  // DailyStreak.fromMap - nested join shape (List - Supabase 1:1 quirk)
  // ---------------------------------------------------------------------------

  group('DailyStreak.fromMap flattens nested join List shape', () {
    // GIVEN Supabase returns player_streaks as a 1-element List (1:1 join quirk)
    // WHEN DailyStreak.fromMap is called
    // THEN it handles the List shape and extracts values from the first element
    test('reads streak from player_streaks nested as a one-element List', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': [
          {
            'streak': 5,
            'longest_streak': 10,
            'last_login_at': '2026-06-08T09:00:00.000Z',
            'milestones_claimed': <int>[],
          }
        ],
        'player_economy': [
          {'subscription_tier': 'free'}
        ],
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.current, equals(5),
          reason: 'must unwrap List<Map> returned by Supabase 1:1 join quirk');
    });

    test('reads subscriptionTier from player_economy nested as a one-element List', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': [
          {
            'streak': 5,
            'longest_streak': 10,
            'last_login_at': null,
            'milestones_claimed': <int>[],
          }
        ],
        'player_economy': [
          {'subscription_tier': 'premium'}
        ],
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.subscriptionTier, equals('premium'),
          reason: 'must unwrap List<Map> for player_economy 1:1 join quirk');
    });
  });

  // ---------------------------------------------------------------------------
  // DailyStreak.fromMap - null nested sub-maps (new player, no streak row yet)
  // ---------------------------------------------------------------------------

  group('DailyStreak.fromMap returns defaults when nested sub-maps are null', () {
    // GIVEN player_streaks is null (new player, backfill not run)
    // WHEN DailyStreak.fromMap is called
    // THEN returns DailyStreak with current=0, longest=0, subscriptionTier='free'
    test('returns current=0 when player_streaks is null', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': null,
        'player_economy': null,
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.current, equals(0),
          reason: 'new player has no player_streaks row; must default to 0');
    });

    test('returns longest=0 when player_streaks is null', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': null,
        'player_economy': null,
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.longest, equals(0),
          reason: 'new player has no player_streaks row; must default to 0');
    });

    test('returns subscriptionTier=free when player_economy is null', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': null,
        'player_economy': null,
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.subscriptionTier, equals('free'),
          reason: 'new player has no player_economy row; must default to free');
    });

    test('returns empty milestonesClaimed when player_streaks is null', () {
      final row = {
        'id': 'abc-123',
        'player_streaks': null,
        'player_economy': null,
      };

      final streak = DailyStreak.fromMap(row);

      expect(streak.milestonesClaimed, isEmpty,
          reason: 'new player has no streak row; milestones must default to empty');
    });
  });
}
