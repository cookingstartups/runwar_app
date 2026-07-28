// test/screens/settings_screen_structure_test.dart
//
// Covers the new SettingsScreen shell: the four fixed-order sections
// (Preferences, Account, Support, About) and the explicit absence of any
// logout affordance (logout stays on ProfileScreen only). Source-inspection
// is used here, matching this repo's established convention for screens that
// touch Supabase-backed providers and cannot be pumped without a live client
// (see database_service_split_test.dart).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('SettingsScreen renders four sections in fixed order', () {
    test('lib/screens/settings_screen.dart exists and defines SettingsScreen',
        () {
      final content = _read('lib/screens/settings_screen.dart');
      expect(content.contains('class SettingsScreen'), isTrue,
          reason: 'SettingsScreen widget class must be defined');
    });

    test('section titles appear in the order Preferences, Account, Support, About',
        () {
      final content = _read('lib/screens/settings_screen.dart');
      final upper = content.toUpperCase();
      final prefsIdx = upper.indexOf('PREFERENCES');
      final accountIdx = upper.indexOf('ACCOUNT');
      final supportIdx = upper.indexOf('SUPPORT');
      final aboutIdx = upper.indexOf('ABOUT');

      expect(prefsIdx, greaterThan(-1), reason: 'Preferences section missing');
      expect(accountIdx, greaterThan(-1), reason: 'Account section missing');
      expect(supportIdx, greaterThan(-1), reason: 'Support section missing');
      expect(aboutIdx, greaterThan(-1), reason: 'About section missing');

      expect(prefsIdx < accountIdx, isTrue,
          reason: 'Preferences must appear before Account');
      expect(accountIdx < supportIdx, isTrue,
          reason: 'Account must appear before Support');
      expect(supportIdx < aboutIdx, isTrue,
          reason: 'Support must appear before About');
    });
  });

  group('SettingsScreen has no logout affordance', () {
    test('settings_screen.dart contains no LOG OUT text or signOut call', () {
      final content = _read('lib/screens/settings_screen.dart');
      expect(content.toUpperCase().contains('LOG OUT'), isFalse,
          reason: 'Settings must not duplicate the profile logout row');
      expect(content.contains('signOut'), isFalse,
          reason: 'Settings must never call authProvider.notifier.signOut');
    });
  });
}
