// test/migrations/migration_0070_zones_realtime_test.dart
//
// SQL-level file existence/content check for AC-C1 (no Dart runtime test
// exists for Realtime delivery itself in this codebase - matches 0045's own
// precedent, per design.md §10). Mirrors
// supabase/migrations/0045_player_economy_realtime.sql's structure: sets
// REPLICA IDENTITY FULL and idempotently adds the table to
// supabase_realtime.
//
// RED today: 0070_zones_realtime.sql does not exist yet.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('migration 0070: enables Realtime on zones (AC-C1)', () {
    test('0070_zones_realtime.sql exists in supabase/migrations', () {
      final file = File('supabase/migrations/0070_zones_realtime.sql');
      expect(file.existsSync(), isTrue,
          reason: 'migration 0070_zones_realtime.sql must exist to enable Realtime delivery for zones');
    });

    test('sets zones to REPLICA IDENTITY FULL', () {
      final file = File('supabase/migrations/0070_zones_realtime.sql');
      if (!file.existsSync()) {
        fail('0070_zones_realtime.sql does not exist yet (expected RED today)');
      }
      final sql = file.readAsStringSync();
      expect(sql, contains('ALTER TABLE zones REPLICA IDENTITY FULL'),
          reason: 'RLS-filtered subscribers need the full row payload, matching 0045\'s rationale');
    });

    test('idempotently adds public.zones to the supabase_realtime publication', () {
      final file = File('supabase/migrations/0070_zones_realtime.sql');
      if (!file.existsSync()) {
        fail('0070_zones_realtime.sql does not exist yet (expected RED today)');
      }
      final sql = file.readAsStringSync();
      expect(sql, contains("pubname = 'supabase_realtime'"),
          reason: 'the idempotency guard must check pg_publication_tables for existing membership, mirroring 0045');
      expect(sql, contains("tablename = 'zones'"));
      expect(sql, contains('ALTER PUBLICATION supabase_realtime ADD TABLE public.zones'));
    });
  });
}
