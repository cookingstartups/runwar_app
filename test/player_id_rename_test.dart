// test/player_id_rename_test.dart
//
// Source-inspection tests that verify the player_id -> user_id rename is
// complete across Dart lib/, migration files, rollback SQL, and edge functions.
// All tests are RED on current main and must be GREEN after the rename PR lands.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // No player_id string anywhere in lib/ (full Dart codebase scan)
  // ---------------------------------------------------------------------------
  group('lib/ contains no player_id references', () {
    test('grep player_id in lib/ returns no matches', () async {
      final result = await Process.run(
        'grep',
        ['-rn', 'player_id', 'lib/'],
      );
      final stdout = (result.stdout as String).trim();
      expect(
        result.exitCode,
        equals(1),
        reason:
            'grep exits 1 when no matches are found. '
            'Exit code ${result.exitCode} means player_id references still exist in lib/.',
      );
      expect(
        stdout,
        isEmpty,
        reason:
            'grep output must be empty. '
            'Remaining references:\n$stdout',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // outbox_aware_writer uses user_id in onConflict string
  // ---------------------------------------------------------------------------
  group('outbox_aware_writer uses user_id in dedup conflict target', () {
    const path = 'lib/services/outbox_aware_writer.dart';

    test('onConflict string contains session_id,ts,user_id', () {
      final src = File(path).readAsStringSync();
      expect(
        src,
        contains('session_id,ts,user_id'),
        reason:
            '$path must use onConflict: \'session_id,ts,user_id\' '
            'so the dedup unique index (rebuilt in migration 0050) is satisfied.',
      );
    });

    test('onConflict string does not contain session_id,ts,player_id', () {
      final src = File(path).readAsStringSync();
      expect(
        src,
        isNot(contains('session_id,ts,player_id')),
        reason:
            '$path must NOT reference the old dedup key session_id,ts,player_id — '
            'that index is dropped by migration 0050 and replaced with user_id.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // run_recorder_service does not write player_id in run payloads
  // ---------------------------------------------------------------------------
  group('run_recorder_service does not write player_id in run payloads', () {
    const path = 'lib/services/run_recorder_service.dart';

    test('source does not contain player_id: uid dual-write', () {
      final src = File(path).readAsStringSync();
      expect(
        src,
        isNot(contains("'player_id': uid")),
        reason:
            '$path must not dual-write player_id: uid. '
            'The PR #39 dual-write must be removed; user_id is the sole identifier.',
      );
    });

    test('source does not contain player_id: userId dual-write', () {
      final src = File(path).readAsStringSync();
      expect(
        src,
        isNot(contains("'player_id': userId")),
        reason:
            '$path must not dual-write player_id: userId. '
            'Only user_id should be written after migration 0050.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0050 file exists, is atomic, and rebuilds gps_samples_dedup
  // ---------------------------------------------------------------------------
  group('migration 0050 unification file is correct', () {
    const path =
        'supabase/migrations/0050_player_id_to_user_id_unification.sql';

    test('migration file 0050 exists', () {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$path must exist — it is the single atomic rename migration.',
      );
    });

    test('0050 is wrapped in BEGIN/COMMIT transaction', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql,
        contains('BEGIN;'),
        reason:
            '0050 must open a transaction with BEGIN; '
            'so any failure rolls back the entire rename atomically.',
      );
      expect(
        sql,
        contains('COMMIT;'),
        reason:
            '0050 must close the transaction with COMMIT; '
            'so schema state transitions atomically.',
      );
    });

    test('0050 rebuilds gps_samples_dedup index with user_id', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql,
        contains('gps_samples_dedup'),
        reason:
            '0050 must recreate the gps_samples_dedup unique index '
            '— the old index on player_id is dropped and a new one on user_id is created.',
      );
      expect(
        sql,
        contains('user_id'),
        reason:
            '0050 must reference user_id in the rebuilt gps_samples_dedup index definition.',
      );
    });

    test('0050 does not use CREATE INDEX CONCURRENTLY', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before content check runs');
      final sql = file.readAsStringSync().toUpperCase();
      expect(
        sql,
        isNot(contains('CREATE INDEX CONCURRENTLY')),
        reason:
            '0050 must NOT use CREATE INDEX CONCURRENTLY — '
            'CONCURRENTLY causes an implicit commit which breaks the atomic transaction.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Rollback migration exists and mirrors the rename
  // ---------------------------------------------------------------------------
  group('rollback migration 0050 exists and is a true mirror', () {
    const path = 'supabase/migrations/0050_rollback.sql';

    test('rollback file 0050_rollback.sql exists', () {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '$path must exist — rollback SQL must be authored alongside 0050 '
            'per the deployment spec rollback plan.',
      );
    });

    test('rollback contains RENAME COLUMN user_id TO player_id', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql,
        contains('RENAME COLUMN user_id TO player_id'),
        reason:
            '$path must reverse each rename with '
            'RENAME COLUMN user_id TO player_id — '
            'this proves it is a true mirror and not a stub.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Edge functions contain no player_id references
  // ---------------------------------------------------------------------------
  group('edge functions contain no player_id references', () {
    const functions = [
      'supabase/functions/claim_drop/index.ts',
      'supabase/functions/spend_credits_on_power/index.ts',
      'supabase/functions/submit_challenge_outcome/index.ts',
      'supabase/functions/anticheat_score/index.ts',
      'supabase/functions/earn_superpower/index.ts',
      'supabase/functions/record_daily_login/index.ts',
      'supabase/functions/ctf_join/index.ts',
      'supabase/functions/ctf_claim_win/index.ts',
    ];

    for (final fnPath in functions) {
      test('$fnPath does not contain player_id', () {
        final src = File(fnPath).readAsStringSync();
        expect(
          src,
          isNot(contains('player_id')),
          reason:
              '$fnPath must not reference player_id after the edge-function PR. '
              'All references must be renamed to user_id.',
        );
      });
    }
  });
}
