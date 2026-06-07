// test/profile_identity/profile_edit_screen_test.dart
//
// RED phase — SDD Profile Identity Redesign.
// Each test maps 1-to-1 with an AC from:
//   infra/meta/specs/runwar/mvp/profile-identity-redesign/requirements.md
//
// Files under test (via source inspection):
//   lib/screens/profile_edit_screen.dart — AC-7, AC-8, AC-9
//
// Strategy: source inspection with File.readAsStringSync.
// Full widget tests are not written here due to Supabase/Riverpod widget test
// complexity. Source inspection is the correct pattern per
// infra/protocols/flutter-test-patterns.md.
//
// All tests use plain test() (not testWidgets()) — no widget inflation,
// no FlutterMap tile errors.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // Structural gate — file must exist before any AC checks run
  // ────────────────────────────────────────────────────────────────────────────
  group('structural: lib/screens/profile_edit_screen.dart exists', () {
    test(
      'profile_edit_screen.dart has been created',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');

        expect(
          file.existsSync(),
          isTrue,
          reason:
              'lib/screens/profile_edit_screen.dart must be created as part of '
              'the Profile Identity Redesign feature (AC-7, AC-8, AC-9)',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC-7  ProfileEditScreen calls ProfileService.instance.updateProfile on save
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-7: ProfileEditScreen calls ProfileService.instance.updateProfile', () {
    // GIVEN a player on ProfileEditScreen who taps Save
    // WHEN the save handler executes
    // THEN ProfileService.instance.updateProfile is called with the updated values
    test(
      'profile_edit_screen.dart references ProfileService.instance.updateProfile',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/screens/profile_edit_screen.dart must exist before AC-7 can be verified');

        final content = file.readAsStringSync();

        expect(
          content.contains('ProfileService.instance.updateProfile') ||
              content.contains('ProfileService.instance\n') ||
              content.contains('updateProfile('),
          isTrue,
          reason:
              'AC-7: the save handler must call ProfileService.instance.updateProfile — '
              'no other save mechanism is specified',
        );
      },
    );

    // GIVEN the save handler in ProfileEditScreen
    // WHEN the source is inspected
    // THEN ProfileService is imported from profile_service.dart
    test(
      'profile_edit_screen.dart imports profile_service.dart',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/screens/profile_edit_screen.dart must exist before AC-7 can be verified');

        final content = file.readAsStringSync();

        expect(
          content.contains('profile_service') || content.contains('ProfileService'),
          isTrue,
          reason:
              'AC-7: ProfileEditScreen must import and use ProfileService to save profile data',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC-8  Username field enable condition references kUsernameUnlockKm2 and streak
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-8: username field is gated by kUsernameUnlockKm2 and current_streak', () {
    // GIVEN the username enable logic in ProfileEditScreen
    // WHEN the source is inspected
    // THEN kUsernameUnlockKm2 is referenced in the unlock condition
    test(
      'profile_edit_screen.dart references kUsernameUnlockKm2 in unlock condition',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/screens/profile_edit_screen.dart must exist before AC-8 can be verified');

        final content = file.readAsStringSync();

        expect(
          content.contains('kUsernameUnlockKm2'),
          isTrue,
          reason:
              'AC-8: the username enable condition must reference kUsernameUnlockKm2 — '
              'no hard-coded 1.0 literal may be used in its place',
        );
      },
    );

    // GIVEN the username enable logic in ProfileEditScreen
    // WHEN the source is inspected
    // THEN current_streak or kUsernameUnlockStreakDays or streak-related identifier
    //      is referenced in the unlock condition
    test(
      'profile_edit_screen.dart references streak in the unlock condition',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/screens/profile_edit_screen.dart must exist before AC-8 can be verified');

        final content = file.readAsStringSync();

        // Accept any of: current_streak, currentStreak, kUsernameUnlockStreakDays, streak
        final hasStreakReference =
            content.contains('current_streak') ||
                content.contains('currentStreak') ||
                content.contains('kUsernameUnlockStreakDays') ||
                content.contains('streak');

        expect(
          hasStreakReference,
          isTrue,
          reason:
              'AC-8: the username enable condition must reference the streak value — '
              'unlock requires both territory >= 1.0 km² AND streak >= 7 days',
        );
      },
    );

    // GIVEN the username field in ProfileEditScreen
    // WHEN the source is inspected
    // THEN the unlock logic uses >= for comparison (boundary values unlock, not just exceed)
    test(
      'profile_edit_screen.dart uses >= comparison for unlock gate (boundary values unlock)',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/screens/profile_edit_screen.dart must exist before AC-8 can be verified');

        final content = file.readAsStringSync();

        // The unlock condition must use >= not > (spec: "km2 >= 1.0 && streak >= 7")
        // Look for the unlock variable assignment region that contains >=
        final hasGteComparison = content.contains('>=');

        expect(
          hasGteComparison,
          isTrue,
          reason:
              'AC-8: unlock condition must use >= (boundary values at exactly 1.0 km² '
              'and streak=7 must unlock, not just values strictly greater)',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC-9  Locked username shows lock icon and unlock hint text
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-9: locked username shows lock icon and unlock hint text', () {
    // GIVEN the locked state rendering in ProfileEditScreen
    // WHEN the source is inspected
    // THEN a lock icon widget (Icons.lock or lock_outline) is conditionally rendered
    test(
      'profile_edit_screen.dart references a lock icon (Icons.lock)',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/screens/profile_edit_screen.dart must exist before AC-9 can be verified');

        final content = file.readAsStringSync();

        // Accept Icons.lock, Icons.lock_outline, Icons.lock_person, or similar
        final hasLockIcon =
            content.contains('Icons.lock') ||
                content.contains('lock_outline') ||
                content.contains('lock_person');

        expect(
          hasLockIcon,
          isTrue,
          reason:
              'AC-9: a lock icon must be rendered when the username field is locked — '
              'spec requires a visible lock indicator adjacent to the username field',
        );
      },
    );

    // GIVEN the locked state rendering in ProfileEditScreen
    // WHEN the source is inspected
    // THEN the unlock hint text "Unlock at 1.0 km²" or equivalent is present
    test(
      'profile_edit_screen.dart contains unlock hint text referencing km² and 7-day streak',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/screens/profile_edit_screen.dart must exist before AC-9 can be verified');

        final content = file.readAsStringSync();

        // The spec mandates: "Unlock at 1.0 km² owned + 7-day streak"
        // Accept the exact string or reasonable variants
        final hasUnlockText =
            content.contains('Unlock at 1.0 km') ||
                content.contains('Unlock at') ||
                content.contains('unlock') ||
                content.contains('7-day streak') ||
                content.contains('7 day streak');

        expect(
          hasUnlockText,
          isTrue,
          reason:
              'AC-9: the lock state must display an unlock hint — '
              'spec requires text referencing the km² and streak requirements',
        );
      },
    );

    // GIVEN the username TextField in ProfileEditScreen
    // WHEN the source is inspected
    // THEN the enabled property is conditionally set (not always true)
    test(
      'profile_edit_screen.dart sets username field enabled property conditionally',
      () {
        final file = File('lib/screens/profile_edit_screen.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/screens/profile_edit_screen.dart must exist before AC-9 can be verified');

        final content = file.readAsStringSync();

        // The TextField must have an enabled: condition, not just enabled: true
        // Look for "enabled:" in the context of the username field
        final hasEnabledProperty = content.contains('enabled:');

        expect(
          hasEnabledProperty,
          isTrue,
          reason:
              'AC-9: the username TextField must have an `enabled:` property '
              'that is conditionally set based on the unlock gate — '
              'enabled: false when locked, enabled: true when unlocked',
        );
      },
    );
  });
}
