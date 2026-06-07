// test/profile_identity/gate3_test.dart
//
// RED phase — SDD Profile Identity Redesign.
// Each test maps 1-to-1 with an AC from:
//   infra/meta/specs/runwar/mvp/profile-identity-redesign/requirements.md
//
// Files under test (via source inspection):
//   lib/main.dart  — AC-3: Gate 3 no longer checks username.isEmpty
//                  — AC-4: SignUpFlow import and usage removed
//
// Strategy: source inspection with File.readAsStringSync.
// Using plain test() not testWidgets() to avoid FlutterMap tile errors
// that fire hundreds of HTTP-400 in the fake-async test environment.
// Pattern mirrors test/main/route_guard_test.dart §AC-11 source checks.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // AC-3  Gate 3 routes on profile == null only — username.isEmpty removed
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-3: Gate 3 no longer checks username.isEmpty', () {
    // GIVEN the feature is implemented
    // WHEN lib/main.dart source is inspected
    // THEN the string "username.isEmpty" does not appear anywhere in the file
    test(
      'main.dart does not contain username.isEmpty',
      () {
        final file = File('lib/main.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/main.dart must exist');

        final content = file.readAsStringSync();

        expect(
          content.contains('username.isEmpty'),
          isFalse,
          reason:
              'AC-3: the Gate 3 condition must not reference username.isEmpty — '
              'routing must be based solely on profile == null',
        );
      },
    );

    // GIVEN the feature is implemented
    // WHEN lib/main.dart source is inspected
    // THEN "profile == null" (or "profile == null") is still present as the Gate 3 guard
    test(
      'main.dart still contains a profile == null guard for Gate 3',
      () {
        final file = File('lib/main.dart');
        final content = file.readAsStringSync();

        // Accept any of the valid null-check patterns:
        //   profile == null
        //   profile == null
        //   (profile == null)
        final hasNullGuard = content.contains('profile == null') ||
            content.contains('if (profile == null)');

        expect(
          hasNullGuard,
          isTrue,
          reason:
              'AC-3: Gate 3 must still guard on profile == null to handle the '
              'case where the database fetch failed for an authenticated user',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC-4  sign_up_flow.dart deleted; no import or usage remains
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-4: SignUpFlow and sign_up_flow.dart are fully removed', () {
    // GIVEN the feature is merged
    // WHEN lib/screens/onboarding/sign_up_flow.dart is checked for existence
    // THEN the file does not exist
    test(
      'lib/screens/onboarding/sign_up_flow.dart has been deleted',
      () {
        final file = File('lib/screens/onboarding/sign_up_flow.dart');

        expect(
          file.existsSync(),
          isFalse,
          reason:
              'AC-4: sign_up_flow.dart must be deleted — the file must not exist '
              'after the feature is merged',
        );
      },
    );

    // GIVEN the feature is merged
    // WHEN lib/main.dart source is inspected
    // THEN no import of sign_up_flow is present
    test(
      'main.dart does not import sign_up_flow',
      () {
        final file = File('lib/main.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/main.dart must exist');

        final content = file.readAsStringSync();

        expect(
          content.contains('sign_up_flow'),
          isFalse,
          reason:
              'AC-4: main.dart must not import sign_up_flow.dart after deletion',
        );
      },
    );

    // GIVEN the feature is merged
    // WHEN lib/main.dart source is inspected
    // THEN "SignUpFlow" does not appear as a class reference
    test(
      'main.dart does not reference the SignUpFlow class',
      () {
        final file = File('lib/main.dart');
        final content = file.readAsStringSync();

        expect(
          content.contains('SignUpFlow'),
          isFalse,
          reason:
              'AC-4: no call site, widget instantiation, or import of SignUpFlow '
              'must remain in main.dart after the class is deleted',
        );
      },
    );
  });
}
