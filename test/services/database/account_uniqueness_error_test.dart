// test/services/database/account_uniqueness_error_test.dart
//
// RED phase: each test maps to exactly one GIVEN/WHEN/THEN from
// requirements.md (AC-5, AC-6, AC-7) and design.md §4.5.
//
// Tests will FAIL against the stub in
//   lib/services/database/account_uniqueness_error.dart
// which returns null unconditionally, causing AC-5/AC-6 assertion tests to
// fail with 'Expected: ... Actual: <null>'.
// That is the expected RED failure — NOT a compile error.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:runwar_app/services/database/account_uniqueness_error.dart';

void main() {
  group('accountUniquenessMessage', () {
    // ── AC-5 ──────────────────────────────────────────────────────────────────

    // GIVEN a PostgrestException with code 23505 and message containing
    //   'players_phone_unique'
    // WHEN accountUniquenessMessage is called
    // THEN returns "This phone number is already linked to another account."
    test(
      'returns phone-duplicate message for 23505 on players_phone_unique constraint',
      () {
        final error = PostgrestException(
          message: 'duplicate key value violates unique constraint '
              '"players_phone_unique"',
          code: '23505',
          details: 'Key (phone)=(+34647661530) already exists.',
        );

        final result = accountUniquenessMessage(error);

        expect(
          result,
          equals('This phone number is already linked to another account.'),
          reason:
              'AC-5: phone unique violation must produce the phone error message',
        );
      },
    );

    // ── AC-6 ──────────────────────────────────────────────────────────────────

    // GIVEN a PostgrestException with code 23505 and message containing
    //   'players_username_unique'
    // WHEN accountUniquenessMessage is called
    // THEN returns "This username is already taken. Please choose another."
    test(
      'returns username-duplicate message for 23505 on players_username_unique constraint',
      () {
        final error = PostgrestException(
          message: 'duplicate key value violates unique constraint '
              '"players_username_unique"',
          code: '23505',
          details: 'Key (username)=(alex) already exists.',
        );

        final result = accountUniquenessMessage(error);

        expect(
          result,
          equals('This username is already taken. Please choose another.'),
          reason:
              'AC-6: username unique violation must produce the username error message',
        );
      },
    );

    // ── AC-7 — wrong constraint name ─────────────────────────────────────────

    // GIVEN a PostgrestException with code 23505 but a different constraint name
    // WHEN accountUniquenessMessage is called
    // THEN returns null (the caller handles it generically)
    test(
      'returns null for 23505 on an unrelated constraint',
      () {
        final error = PostgrestException(
          message: 'duplicate key value violates unique constraint '
              '"some_other_table_unique"',
          code: '23505',
          details: 'Key (some_col)=(some_value) already exists.',
        );

        final result = accountUniquenessMessage(error);

        expect(
          result,
          isNull,
          reason:
              'AC-7: 23505 on a different constraint must NOT produce a known message',
        );
      },
    );

    // ── AC-7 — wrong Postgres code ────────────────────────────────────────────

    // GIVEN a PostgrestException with a non-uniqueness error code (e.g. 42501
    //   — insufficient_privilege)
    // WHEN accountUniquenessMessage is called
    // THEN returns null
    test(
      'returns null for a PostgrestException with a non-uniqueness error code',
      () {
        final error = PostgrestException(
          message: 'permission denied for table players',
          code: '42501',
        );

        final result = accountUniquenessMessage(error);

        expect(
          result,
          isNull,
          reason:
              'AC-7: only code 23505 should route to uniqueness messages; '
              '42501 must return null',
        );
      },
    );

    // ── AC-7 — generic Exception (not PostgrestException) ────────────────────

    // GIVEN a plain Exception (e.g. a network error)
    // WHEN accountUniquenessMessage is called
    // THEN returns null
    test(
      'returns null for a non-PostgrestException error',
      () {
        final error = Exception('network timeout');

        final result = accountUniquenessMessage(error);

        expect(
          result,
          isNull,
          reason:
              'AC-7: non-PostgrestException must always return null',
        );
      },
    );

    // ── AC-7 — null input ────────────────────────────────────────────────────

    // GIVEN null is passed as the error
    // WHEN accountUniquenessMessage is called
    // THEN returns null (does not throw)
    test(
      'returns null when called with null',
      () {
        final result = accountUniquenessMessage(null);

        expect(
          result,
          isNull,
          reason: 'AC-7: null input must return null without throwing',
        );
      },
    );

    // ── Constraint-name in details field only ────────────────────────────────

    // GIVEN a PostgrestException where the constraint name appears in details
    //   rather than in message
    // WHEN accountUniquenessMessage is called
    // THEN still returns the correct phone message (design §4.5 concatenates both)
    test(
      'returns phone message when constraint name appears only in details field',
      () {
        final error = PostgrestException(
          message: 'ERROR: 23505',
          code: '23505',
          details: 'players_phone_unique',
        );

        final result = accountUniquenessMessage(error);

        expect(
          result,
          equals('This phone number is already linked to another account.'),
          reason:
              'design §4.5: concatenates message+details so constraint name in '
              'details alone is sufficient',
        );
      },
    );
  });
}
