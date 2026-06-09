// test/players_split_migration_test.dart
//
// RED phase: source-inspection tests for the players god-table split migrations.
// Each test reads a migration SQL file as a string and asserts the presence of
// required DDL patterns. Tests will be RED until the migration files are written.
//
// Strategy: File.readAsStringSync source inspection only.
// All tests use plain test() inside group() blocks -- no widget inflation.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Migration 0035 -- player_economy table
  // ---------------------------------------------------------------------------
  group('migration 0035 creates player_economy table', () {
    const path = 'supabase/migrations/0035_player_economy.sql';

    test('migration file 0035 exists', () {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$path must exist -- it creates the player_economy child table',
      );
    });

    test('0035 contains CREATE TABLE IF NOT EXISTS player_economy', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('CREATE TABLE IF NOT EXISTS player_economy'),
        isTrue,
        reason:
            '0035 must use CREATE TABLE IF NOT EXISTS player_economy for idempotency',
      );
    });

    test('0035 contains REFERENCES players(id) ON DELETE CASCADE', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('REFERENCES players(id) ON DELETE CASCADE'),
        isTrue,
        reason:
            '0035 must define the FK with ON DELETE CASCADE so deleting a player '
            'automatically removes the economy row',
      );
    });

    test('0035 enables RLS with ENABLE ROW LEVEL SECURITY', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.toUpperCase().contains('ENABLE ROW LEVEL SECURITY'),
        isTrue,
        reason:
            '0035 must call ENABLE ROW LEVEL SECURITY on player_economy -- '
            'only service-role connections may write to this table',
      );
    });

    test('0035 contains a backfill INSERT from players', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.toUpperCase().contains('INSERT INTO') &&
            sql.toLowerCase().contains('player_economy'),
        isTrue,
        reason:
            '0035 must backfill one player_economy row per existing players row',
      );
    });

    test('0035 contains a count assertion after backfill', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      // Design §B.1 mandates a DO $$ block that compares expected vs actual COUNT
      expect(
        sql.toUpperCase().contains('COUNT(*)'),
        isTrue,
        reason:
            '0035 must include a COUNT(*) assertion after the backfill INSERT '
            'to guarantee one row per player (design §B.1)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0036 -- player_progress table
  // ---------------------------------------------------------------------------
  group('migration 0036 creates player_progress table', () {
    const path = 'supabase/migrations/0036_player_progress.sql';

    test('migration file 0036 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it creates the player_progress child table');
    });

    test('0036 contains CREATE TABLE IF NOT EXISTS player_progress', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('CREATE TABLE IF NOT EXISTS player_progress'),
        isTrue,
        reason: '0036 must create player_progress with IF NOT EXISTS for idempotency',
      );
    });

    test('0036 contains a score column (renamed from influence_total)', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('score'),
        isTrue,
        reason:
            '0036 must define a score column -- influence_total is renamed to score '
            'per the confirmed decision in requirements.md',
      );
    });

    test('0036 backfills score from players.influence_total', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('influence_total'),
        isTrue,
        reason:
            '0036 must reference influence_total in the backfill SELECT to populate score',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0037 -- player_streaks table
  // ---------------------------------------------------------------------------
  group('migration 0037 creates player_streaks table', () {
    const path = 'supabase/migrations/0037_player_streaks.sql';

    test('migration file 0037 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it creates the player_streaks child table');
    });

    test('0037 contains CREATE TABLE IF NOT EXISTS player_streaks', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('CREATE TABLE IF NOT EXISTS player_streaks'),
        isTrue,
        reason: '0037 must create player_streaks with IF NOT EXISTS for idempotency',
      );
    });

    test('0037 contains a streak column definition', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('streak'),
        isTrue,
        reason:
            '0037 must define a streak column -- this is the canonical streak column name',
      );
    });

    test('0037 does NOT define a column named current_streak', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      // The CREATE TABLE block should not have current_streak as a column name.
      // We check by looking for "current_streak" as a column definition token.
      // The backfill SELECT may reference players.current_streak (old column), so
      // we only assert that the column is not in the CREATE TABLE block itself.
      final createBlock = _extractCreateTableBlock(sql, 'player_streaks');
      expect(
        createBlock.contains('current_streak'),
        isFalse,
        reason:
            '0037 must NOT add a current_streak column to player_streaks -- '
            'streak is the canonical name; current_streak is being dropped (AC-3)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0038 -- player_trial table
  // ---------------------------------------------------------------------------
  group('migration 0038 creates player_trial table', () {
    const path = 'supabase/migrations/0038_player_trial.sql';

    test('migration file 0038 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it creates the player_trial child table');
    });

    test('0038 contains CREATE TABLE IF NOT EXISTS player_trial', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('CREATE TABLE IF NOT EXISTS player_trial'),
        isTrue,
        reason: '0038 must create player_trial with IF NOT EXISTS for idempotency',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0039 -- player_devices table
  // ---------------------------------------------------------------------------
  group('migration 0039 creates player_devices table with composite PK', () {
    const path = 'supabase/migrations/0039_player_devices.sql';

    test('migration file 0039 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it creates the player_devices child table');
    });

    test('0039 contains CREATE TABLE IF NOT EXISTS player_devices', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('CREATE TABLE IF NOT EXISTS player_devices'),
        isTrue,
        reason: '0039 must create player_devices with IF NOT EXISTS for idempotency',
      );
    });

    test('0039 defines PRIMARY KEY (player_id, device_token) composite key', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(
        sql.contains('PRIMARY KEY (player_id, device_token)') ||
            sql.contains('PRIMARY KEY(player_id, device_token)'),
        isTrue,
        reason:
            '0039 must define a composite PRIMARY KEY (player_id, device_token) -- '
            'this is a 1:N table so a single-column PK is incorrect (AC-5)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0040 -- apply_credit_delta RPC rewrite
  // ---------------------------------------------------------------------------
  group('migration 0040 rewrites apply_credit_delta to use player_economy', () {
    const path = 'supabase/migrations/0040_apply_credit_delta_rewrite.sql';

    test('migration file 0040 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it rewrites apply_credit_delta to use player_economy');
    });

    test('0040 references apply_credit_delta function name', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('apply_credit_delta'),
        isTrue,
        reason: '0040 must create or replace the apply_credit_delta function',
      );
    });

    test('0040 references player_economy table (not players.credits)', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('player_economy'),
        isTrue,
        reason:
            '0040 must rewrite apply_credit_delta to UPDATE player_economy.credits '
            'instead of players.credits',
      );
    });

    test('0040 uses IF NOT FOUND to detect missing player_economy row', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.toUpperCase().contains('IF NOT FOUND'),
        isTrue,
        reason:
            '0040 must use IF NOT FOUND (not "IF new_balance IS NULL") to detect '
            'a missing player_economy row and raise an exception (design §B.2)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0041 -- complete_first_mission_tx RPC rewrite
  // ---------------------------------------------------------------------------
  group('migration 0041 rewrites complete_first_mission_tx to use child tables', () {
    const path = 'supabase/migrations/0041_complete_first_mission_tx_rewrite.sql';

    test('migration file 0041 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it rewrites complete_first_mission_tx');
    });

    test('0041 references complete_first_mission_tx function name', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('complete_first_mission_tx'),
        isTrue,
        reason: '0041 must create or replace complete_first_mission_tx',
      );
    });

    test('0041 references player_progress table', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('player_progress'),
        isTrue,
        reason:
            '0041 must read and write player_progress.first_mission_completed_at '
            'instead of the same column on players',
      );
    });

    test('0041 references player_streaks table', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('player_streaks'),
        isTrue,
        reason:
            '0041 must write player_streaks.streak_started_at '
            'instead of players.streak_started_at',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0042 -- players_and_bots view rewrite
  // ---------------------------------------------------------------------------
  group('migration 0042 rewrites players_and_bots view to source score from player_progress', () {
    const path = 'supabase/migrations/0042_players_and_bots_view_rewrite.sql';

    test('migration file 0042 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it rewrites the players_and_bots view');
    });

    test('0042 references players_and_bots view name', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('players_and_bots'),
        isTrue,
        reason: '0042 must drop and recreate the players_and_bots view',
      );
    });

    test('0042 joins player_progress to source score', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync();
      expect(
        sql.contains('player_progress'),
        isTrue,
        reason:
            '0042 must LEFT JOIN player_progress to source score '
            'instead of returning the literal 0 constant',
      );
    });

    test('0042 uses COALESCE for score to handle players without a progress row', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync().toUpperCase();
      expect(
        sql.contains('COALESCE'),
        isTrue,
        reason:
            '0042 must use COALESCE(pp.score, 0) so that a player with no '
            'player_progress row still appears in the view with score = 0 (AC-8)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0043 -- signup trigger
  // ---------------------------------------------------------------------------
  group('migration 0043 creates signup trigger on players', () {
    const path = 'supabase/migrations/0043_signup_trigger.sql';

    test('migration file 0043 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it creates the AFTER INSERT trigger on players');
    });

    test('0043 creates an AFTER INSERT trigger on players', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync().toUpperCase();
      expect(
        sql.contains('AFTER INSERT ON PLAYERS'),
        isTrue,
        reason:
            '0043 must define an AFTER INSERT trigger on the players table so that '
            'every new player gets default child rows atomically (AC-9)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Migration 0044 -- drop moved columns from players
  // ---------------------------------------------------------------------------
  group('migration 0044 drops moved columns from players', () {
    const path = 'supabase/migrations/0044_players_cleanup.sql';

    test('migration file 0044 exists', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist -- it drops the 20 moved columns from players');
    });

    test('0044 drops credits column with DROP COLUMN IF EXISTS', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync().toUpperCase();
      expect(
        sql.contains('DROP COLUMN IF EXISTS CREDITS'),
        isTrue,
        reason:
            '0044 must DROP COLUMN IF EXISTS credits -- '
            'IF EXISTS makes the migration idempotent (design §B.5)',
      );
    });

    test('0044 drops current_streak column with DROP COLUMN IF EXISTS', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path must exist before this content check runs');
      final sql = file.readAsStringSync().toUpperCase();
      expect(
        sql.contains('DROP COLUMN IF EXISTS CURRENT_STREAK'),
        isTrue,
        reason:
            '0044 must DROP COLUMN IF EXISTS current_streak -- '
            'this redundant column is being permanently removed (AC-10)',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Helper: extracts the CREATE TABLE block for a given table name from raw SQL.
// Returns an empty string if the block cannot be found.
// Used by the current_streak column assertion to avoid false positives from
// comments or backfill SELECT statements that reference the old column name.
// ---------------------------------------------------------------------------
String _extractCreateTableBlock(String sql, String tableName) {
  final start = sql.indexOf('CREATE TABLE');
  if (start == -1) return '';
  // Find the matching closing paren/semicolon of the CREATE TABLE statement.
  final end = sql.indexOf(';', start);
  if (end == -1) return sql.substring(start);
  return sql.substring(start, end + 1);
}
