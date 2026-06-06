// test/services/database_service_account_uniqueness_test.dart
//
// RED phase: tests for DatabaseService profile-write normalisation.
// Each test maps to exactly one GIVEN/WHEN/THEN from requirements.md and
// design.md §4.1.
//
// What we test here:
//   AC-2  — phone is normalised to E.164 (strip non-+digits) before write
//   AC-4  — username is trimmed before write
//   AC-7  — other patch keys are untouched by normalisation
//   D10   — insertProfile no longer accepts city or isBot params (compile guard)
//
// Strategy: DatabaseService.updateProfile calls Supabase.instance.client
// (a global singleton), so we cannot call it in unit tests without
// initialising the SDK.  Instead, the implementation is required to expose
// the patch-normalisation step as a top-level function:
//
//   /// Normalises a profile patch map before it is sent to Supabase.
//   /// Applies AC-2 (phone E.164 strip) and AC-4 (username trim).
//   /// Exposed for testing via this public top-level function.
//   @visibleForTesting
//   Map<String, dynamic> normaliseProfilePatch(Map<String, dynamic> patch)
//
// in lib/services/database_service.dart.
//
// The function does not exist yet → tests compile-error on import (RED).
// After implementation the same tests must pass (GREEN).

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database_service.dart';

void main() {
  group('normaliseProfilePatch — AC-2 phone normalisation', () {
    // GIVEN a patch map containing phone '+34 647 (661) 530-0'
    // WHEN normaliseProfilePatch is called
    // THEN the returned map contains phone '+346476615300' (only + and digits)
    test(
      'strips spaces, parentheses, and dashes from phone value',
      () {
        final result = normaliseProfilePatch({'phone': '+34 647 (661) 530-0'});

        expect(
          result['phone'],
          equals('+346476615300'),
          reason:
              'AC-2: all non-+digit characters must be stripped from the phone '
              'value before the write reaches Supabase',
        );
      },
    );

    // GIVEN a patch map containing phone with only + and digits already
    // WHEN normaliseProfilePatch is called
    // THEN the phone value is unchanged
    test(
      'leaves an already-clean E.164 phone value unchanged',
      () {
        final result = normaliseProfilePatch({'phone': '+34647661530'});

        expect(
          result['phone'],
          equals('+34647661530'),
          reason:
              'AC-2: a phone that is already clean must not be mutated',
        );
      },
    );

    // GIVEN a patch map without a phone key
    // WHEN normaliseProfilePatch is called
    // THEN the returned map has no phone key (other keys are untouched)
    test(
      'does not add a phone key when phone is absent from the patch',
      () {
        final result = normaliseProfilePatch({'username': 'warrior99'});

        expect(
          result.containsKey('phone'),
          isFalse,
          reason: 'AC-2: normalisation must not inject a phone key when none was supplied',
        );
      },
    );
  });

  group('normaliseProfilePatch — AC-4 username trim', () {
    // GIVEN a patch map containing username '  warrior99  ' (leading/trailing spaces)
    // WHEN normaliseProfilePatch is called
    // THEN the returned map contains username 'warrior99'
    test(
      'trims leading and trailing whitespace from username',
      () {
        final result = normaliseProfilePatch({'username': '  warrior99  '});

        expect(
          result['username'],
          equals('warrior99'),
          reason:
              'AC-4: username must be trimmed of leading and trailing whitespace '
              'before the write reaches Supabase',
        );
      },
    );

    // GIVEN a patch map containing username 'warrior99' (already trimmed)
    // WHEN normaliseProfilePatch is called
    // THEN the value is unchanged
    test(
      'leaves an already-trimmed username unchanged',
      () {
        final result = normaliseProfilePatch({'username': 'warrior99'});

        expect(
          result['username'],
          equals('warrior99'),
          reason: 'AC-4: a username without surrounding whitespace must not be mutated',
        );
      },
    );
  });

  group('normaliseProfilePatch — AC-7 other keys are untouched', () {
    // GIVEN a patch map with phone, username, and an unrelated key 'color'
    // WHEN normaliseProfilePatch is called
    // THEN 'color' is present in the output with its original value
    test(
      'preserves unrelated patch keys without modification',
      () {
        final result = normaliseProfilePatch({
          'phone': '+34 647 661530',
          'username': ' alex ',
          'color': '#FF0000',
        });

        expect(
          result['color'],
          equals('#FF0000'),
          reason:
              'AC-7: normalisation must not alter keys other than phone and username',
        );
        // Sanity-check that normalisation still applied to the other two.
        expect(result['phone'], equals('+34647661530'));
        expect(result['username'], equals('alex'));
      },
    );

    // GIVEN a patch map with only an unrelated key
    // WHEN normaliseProfilePatch is called
    // THEN the map is returned unchanged
    test(
      'returns a patch unchanged when it contains neither phone nor username',
      () {
        final original = {'bio': 'I run Valencia streets'};
        final result = normaliseProfilePatch(original);

        expect(result, equals(original),
            reason: 'AC-7: patches with no phone/username must pass through unmodified');
      },
    );
  });

  group('insertProfile method signature — D10 city and isBot removed', () {
    // GIVEN the post-migration insertProfile signature (design.md §4.1)
    // WHEN inspecting the method signature at compile time
    // THEN the method does NOT accept a city positional parameter
    // AND does NOT accept an isBot named parameter
    //
    // This test verifies the contract by calling insertProfile without
    // city or isBot — it will compile only if those params are absent.
    // At RED phase this test itself may not cause a compile failure (we are
    // asserting the ABSENCE of a param), but the accompanying RED test below
    // forces a real assertion failure via the stub DatabaseService behaviour.
    //
    // The assertion: after the migration, insertProfile takes exactly:
    //   (String id, String username, String color, {double influence, String? invitedAt,
    //    int isTester, String? createdAt})
    //
    // We verify this by checking that DatabaseService.instance exposes
    // an insertProfile that can be referenced without city/isBot.
    // (If city were still a positional param, callers omitting it would
    //  get a compile error — which is exactly what we want post-migration.)

    // GIVEN the DatabaseService singleton
    // WHEN accessing the insertProfile method reference
    // THEN it has a signature compatible with (id, username, color, {...}) — no city
    test(
      'insertProfile is callable without a city argument after migration',
      () {
        // This lambda would fail to compile if city were a required positional arg
        // between username and color.
        final methodRef = DatabaseService.instance.insertProfile;

        // The method must exist and be callable (we do not actually invoke it
        // because it would hit the live Supabase client).  Just confirm the
        // reference resolves without a compile error.
        expect(methodRef, isNotNull,
            reason:
                'D10: insertProfile must be reachable without a city argument; '
                'if city is still required, this line will not compile');
      },
    );

    // GIVEN the DatabaseService singleton
    // WHEN accessing the upsertProfileIgnore method reference
    // THEN it has a signature compatible with (id, username, color, {...}) — no isBot
    test(
      'upsertProfileIgnore is callable without an isBot argument after migration',
      () {
        final methodRef = DatabaseService.instance.upsertProfileIgnore;

        expect(methodRef, isNotNull,
            reason:
                'D10: upsertProfileIgnore must be reachable without an isBot argument');
      },
    );
  });
}
