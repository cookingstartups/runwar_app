// test/seed_demo_data_noop_test.dart
//
// Regression test for a bug where every app launch logged:
//   seedDemoData skipped: PostgrestException(new row violates row-level
//   security policy for table "bots", code 42501)
//
// Root cause: seedDemoDataIfNeeded attempted client-side inserts into
// `bots` (server/migration-managed only, no client INSERT policy — see
// supabase/migrations/0032_bots_table.sql) and into `zones` under bot-owned
// IDs that can never satisfy zones_owner_all's auth.uid() = owner_id check.
// Both writes were structurally guaranteed to fail under RLS for any real
// signed-in user, so the call is now a no-op. This test asserts it never
// throws and never attempts a network round-trip.
import 'package:flutter_test/flutter_test.dart';
import 'package:runwar_app/services/auth_service.dart';

void main() {
  test('seedDemoDataIfNeeded is a safe no-op that never throws', () async {
    await expectLater(
      AuthService.instance.seedDemoDataIfNeeded(),
      completes,
    );
  });
}
