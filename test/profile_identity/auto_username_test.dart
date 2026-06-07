// test/profile_identity/auto_username_test.dart
//
// RED phase — SDD Profile Identity Redesign.
// Each test maps 1-to-1 with an AC from:
//   infra/meta/specs/runwar/mvp/profile-identity-redesign/requirements.md
//
// Files under test:
//   lib/services/auth_service.dart    — AC-1: Runner_<first6hex> username generation
//   lib/services/database_service.dart — AC-2: upsertProfileIgnore still has ignoreDuplicates
//
// Strategy:
//   AC-1 — pure logic test: derive username string from a UUID using the same
//           formula the implementation will use, assert it matches the pattern.
//           The function `deriveEmailUsername(String id)` is required to be exposed
//           as a top-level @visibleForTesting function in auth_service.dart.
//   AC-2 — source inspection: File.readAsStringSync on database_service.dart
//           to verify `ignoreDuplicates: true` is still present in the
//           upsertProfileIgnore method body.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The function does not yet exist — import will compile-error in RED phase.
import 'package:runwar_app/services/auth_service.dart' show deriveEmailUsername;

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // AC-1  Auto-assigned username matches Runner_<first6hex> pattern
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-1: insertProfile receives Runner_<first6hex> username from signUp', () {
    // GIVEN a new email sign-up where no username has been chosen
    //   AND the user's UUID is "60b224xx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    // WHEN auth_service.signUp() derives the username
    // THEN the derived string equals "Runner_60b224"
    test(
      'derives Runner_60b224 from UUID starting with 60b224',
      () {
        const uuid = '60b224ab-e5f6-4c3d-a1b2-000000000000';
        final result = deriveEmailUsername(uuid);

        expect(
          result,
          equals('Runner_60b224'),
          reason:
              'AC-1: username must equal Runner_ followed by the first 6 hex chars '
              'of the UUID with hyphens stripped',
        );
      },
    );

    // GIVEN any valid UUID
    // WHEN deriveEmailUsername is called
    // THEN the result matches the regex ^Runner_[0-9a-f]{6}$
    test(
      'derived username matches pattern ^Runner_[0-9a-f]{6}\$',
      () {
        const uuid = 'a1b2c3d4-e5f6-4700-8000-000000000000';
        final result = deriveEmailUsername(uuid);

        expect(
          RegExp(r'^Runner_[0-9a-f]{6}$').hasMatch(result),
          isTrue,
          reason:
              'AC-1: username must match ^Runner_[0-9a-f]{6}\$ — '
              'exactly the prefix Runner_ followed by 6 lowercase hex chars',
        );
      },
    );

    // GIVEN the same UUID called twice
    // WHEN deriveEmailUsername is called each time
    // THEN both calls return the same string (deterministic)
    test(
      'username derivation is deterministic — same UUID always produces same result',
      () {
        const uuid = 'dead0000-beef-4000-8000-000000000000';
        final first = deriveEmailUsername(uuid);
        final second = deriveEmailUsername(uuid);

        expect(
          first,
          equals(second),
          reason:
              'AC-1 invariant: the same UUID must always produce the same Runner_* '
              'username — derivation must be deterministic',
        );
      },
    );

    // GIVEN a UUID with upper-case hex characters (as some UUIDs have)
    // WHEN deriveEmailUsername is called
    // THEN the result uses lower-case hex (per Runner_<first6hex> contract)
    test(
      'username hex portion is always lowercase regardless of UUID casing',
      () {
        // UUID whose first 6 chars after hyphen removal are uppercase A-F
        const uuid = 'ABCDEF12-3456-4000-8000-000000000000';
        final result = deriveEmailUsername(uuid);

        expect(
          result,
          equals('Runner_abcdef'),
          reason:
              'AC-1: hex portion of username must be lowercase — '
              'the design spec specifies first6hex (lowercase)',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC-2  upsertProfileIgnore still uses ignoreDuplicates: true (source inspection)
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-2: upsertProfileIgnore in database_service.dart is unchanged', () {
    // GIVEN the feature is implemented
    // WHEN database_service.dart source is inspected
    // THEN ignoreDuplicates: true is present in the upsertProfileIgnore method
    test(
      'upsertProfileIgnore body still contains ignoreDuplicates: true',
      () {
        final file = File('lib/services/database_service.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/services/database_service.dart must exist');

        final content = file.readAsStringSync();

        // Find the upsertProfileIgnore method and verify ignoreDuplicates: true
        // is present within a reasonable span after the method declaration.
        final methodStart = content.indexOf('upsertProfileIgnore');
        expect(methodStart, greaterThan(0),
            reason: 'upsertProfileIgnore must be declared in database_service.dart');

        // Extract the method body — look for ignoreDuplicates within 600 chars
        // after the method declaration (the method is ~20 lines).
        final methodRegion = content.substring(
          methodStart,
          (methodStart + 600).clamp(0, content.length),
        );

        expect(
          methodRegion.contains('ignoreDuplicates: true'),
          isTrue,
          reason:
              'AC-2: upsertProfileIgnore must still pass ignoreDuplicates: true '
              'to the Supabase upsert call — the Google path must be unchanged',
        );
      },
    );

    // GIVEN the feature is implemented
    // WHEN database_service.dart source is inspected
    // THEN the method upsertProfileIgnore still exists (was not deleted or renamed)
    test(
      'upsertProfileIgnore method is still present in database_service.dart',
      () {
        final file = File('lib/services/database_service.dart');
        final content = file.readAsStringSync();

        expect(
          content.contains('Future<void> upsertProfileIgnore'),
          isTrue,
          reason:
              'AC-2: upsertProfileIgnore method must still exist unchanged — '
              'the Google sign-up path depends on it',
        );
      },
    );
  });
}
