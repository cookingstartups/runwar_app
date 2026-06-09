// test/profile_identity/migration_test.dart
//
// RED phase — SDD Profile Identity Redesign.
// Each test maps 1-to-1 with an AC from:
//   infra/meta/specs/runwar/mvp/profile-identity-redesign/requirements.md
//
// Files under test (via source inspection):
//   supabase/migrations/0034_add_bio_avatar.sql — AC-12
//   lib/services/auth_service.dart              — AC-13
//
// Strategy: File.readAsStringSync source inspection only.
// All tests use plain test() — no widget inflation.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // AC-12  Migration 0034_add_bio_avatar.sql adds bio and avatar_url with IF NOT EXISTS
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-12: migration 0034_add_bio_avatar.sql adds bio and avatar_url', () {
    // GIVEN the feature is implemented
    // WHEN supabase/migrations/0034_add_bio_avatar.sql is checked for existence
    // THEN the file exists
    test(
      'supabase/migrations/0034_add_bio_avatar.sql exists',
      () {
        final file = File('supabase/migrations/0034_add_bio_avatar.sql');

        expect(
          file.existsSync(),
          isTrue,
          reason:
              'AC-12: migration file 0034_add_bio_avatar.sql must be created — '
              'it is the hard prerequisite for ProfileEditScreen to save bio/avatar_url',
        );
      },
    );

    // GIVEN 0034_add_bio_avatar.sql exists
    // WHEN the source is inspected
    // THEN it contains "bio TEXT" in an ADD COLUMN IF NOT EXISTS clause
    test(
      '0034_add_bio_avatar.sql adds bio TEXT with IF NOT EXISTS',
      () {
        final file = File('supabase/migrations/0034_add_bio_avatar.sql');
        expect(file.existsSync(), isTrue,
            reason: 'supabase/migrations/0034_add_bio_avatar.sql must exist for AC-12 to be verified');

        final content = file.readAsStringSync();

        expect(
          content.contains('bio TEXT') || content.contains('bio text'),
          isTrue,
          reason:
              'AC-12: migration must add a bio TEXT column to the players table',
        );

        expect(
          content.toUpperCase().contains('IF NOT EXISTS'),
          isTrue,
          reason:
              'AC-12: migration must use ADD COLUMN IF NOT EXISTS — '
              'ensures the migration is idempotent and safe on repeated application',
        );
      },
    );

    // GIVEN 0034_add_bio_avatar.sql exists
    // WHEN the source is inspected
    // THEN it contains "avatar_url TEXT" in an ADD COLUMN IF NOT EXISTS clause
    test(
      '0034_add_bio_avatar.sql adds avatar_url TEXT with IF NOT EXISTS',
      () {
        final file = File('supabase/migrations/0034_add_bio_avatar.sql');
        expect(file.existsSync(), isTrue,
            reason: 'supabase/migrations/0034_add_bio_avatar.sql must exist for AC-12 to be verified');

        final content = file.readAsStringSync();

        expect(
          content.contains('avatar_url TEXT') || content.contains('avatar_url text'),
          isTrue,
          reason:
              'AC-12: migration must add an avatar_url TEXT column to the players table',
        );
      },
    );

    // GIVEN 0034_add_bio_avatar.sql exists
    // WHEN the source is inspected
    // THEN it does NOT contain any UPDATE statement (no row data must be changed)
    test(
      '0034_add_bio_avatar.sql contains no UPDATE statements (AC-13 invariant)',
      () {
        final file = File('supabase/migrations/0034_add_bio_avatar.sql');
        expect(file.existsSync(), isTrue,
            reason: 'supabase/migrations/0034_add_bio_avatar.sql must exist for AC-12 to be verified');

        final content = file.readAsStringSync().toUpperCase();

        // No UPDATE statement — migration must only add columns, never mutate data.
        expect(
          content.contains('\nUPDATE ') || content.contains(' UPDATE '),
          isFalse,
          reason:
              'AC-12/AC-13: migration must not contain UPDATE statements — '
              'existing player data (username, color) must remain untouched',
        );
      },
    );

    // GIVEN 0034_add_bio_avatar.sql exists
    // WHEN the source is inspected
    // THEN it targets the players table
    test(
      '0034_add_bio_avatar.sql targets the players table',
      () {
        final file = File('supabase/migrations/0034_add_bio_avatar.sql');
        expect(file.existsSync(), isTrue,
            reason: 'supabase/migrations/0034_add_bio_avatar.sql must exist for AC-12 to be verified');

        final content = file.readAsStringSync().toLowerCase();

        expect(
          content.contains('players'),
          isTrue,
          reason:
              'AC-12: migration must alter the players table — '
              'bio and avatar_url are player profile fields',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC-13  auth_service.dart upsertProfileIgnore call is unchanged
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-13: auth_service.dart upsertProfileIgnore call is unchanged', () {
    // GIVEN the feature is implemented
    // WHEN lib/services/auth_service.dart source is inspected
    // THEN upsertProfileIgnore is still called with a displayName-derived username
    test(
      'auth_service.dart still calls upsertProfileIgnore with displayName-derived username',
      () {
        final file = File('lib/services/auth_service.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/services/auth_service.dart must exist');

        final content = file.readAsStringSync();

        expect(
          content.contains('upsertProfileIgnore'),
          isTrue,
          reason:
              'AC-13: upsertProfileIgnore must still be called in auth_service.dart '
              'for the Google sign-in path',
        );

        // The Google path derives username from displayName.toUpperCase()
        // or falls back to 'RUNNER-<shortId>' (both are valid)
        final hasDisplayNameDerivation =
            content.contains('displayName') || content.contains('RUNNER-');

        expect(
          hasDisplayNameDerivation,
          isTrue,
          reason:
              'AC-13: the Google sign-in username derivation must still use '
              'displayName.toUpperCase() or the RUNNER-<shortId> fallback — '
              'the upsertProfileIgnore call site must be byte-for-byte unchanged',
        );
      },
    );

    // GIVEN the feature is implemented
    // WHEN lib/services/auth_service.dart source is inspected for the signUp method
    // THEN the signUp call to insertProfile now passes a Runner_<hex> username
    //      (not the empty string '' that existed before the feature)
    test(
      'auth_service.dart signUp no longer passes empty string username to insertProfile',
      () {
        final file = File('lib/services/auth_service.dart');
        final content = file.readAsStringSync();

        // The old call was: insertProfile(id, '', '#FF7A00', ...)
        // After implementation: insertProfile(id, username, color, ...)
        // where username starts with 'Runner_'
        // We verify the old empty-string call pattern is gone.
        expect(
          content.contains("insertProfile(\n        id,\n        '',") ||
              content.contains("insertProfile(id, '',"),
          isFalse,
          reason:
              'AC-13: the signUp call to insertProfile must no longer pass '
              "an empty string '' as username — it must pass a Runner_<hex> value",
        );
      },
    );

    // GIVEN the feature is implemented
    // WHEN lib/services/auth_service.dart source is inspected
    // THEN the signUp method contains a Runner_ prefix derivation
    test(
      "auth_service.dart signUp contains Runner_ username derivation",
      () {
        final file = File('lib/services/auth_service.dart');
        final content = file.readAsStringSync();

        expect(
          content.contains("Runner_"),
          isTrue,
          reason:
              "AC-13/AC-1: signUp must derive a Runner_<first6hex> username — "
              "the prefix 'Runner_' must appear in the email sign-up path",
        );
      },
    );
  });
}
