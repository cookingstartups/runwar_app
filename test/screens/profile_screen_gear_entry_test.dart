// test/screens/profile_screen_gear_entry_test.dart
//
// Covers the new gear icon entry point added to ProfileScreen's AppBar
// actions, positioned after the existing "Edit" text button, and confirms
// no other existing ProfileScreen content is removed by the change.
// Source-inspection, mirroring paywall_day21_sweep_test.dart's convention
// for asserting presence/order of literals in a widget file.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('gear icon entry point', () {
    test('profile_screen.dart references SettingsScreen as a push destination',
        () {
      final content = _read('lib/screens/profile_screen.dart');
      expect(content.contains('SettingsScreen'), isTrue,
          reason: 'A gear action must push SettingsScreen');
    });

    test('the SettingsScreen reference appears after the Edit text button',
        () {
      final content = _read('lib/screens/profile_screen.dart');
      final editIdx = content.indexOf("'Edit'");
      final settingsIdx = content.indexOf('SettingsScreen');
      expect(editIdx, greaterThan(-1), reason: 'Edit button must still exist');
      expect(settingsIdx, greaterThan(editIdx),
          reason: 'Gear action must come after Edit in AppBar.actions order');
    });

    test('a gear-style icon button is present in the actions block', () {
      final content = _read('lib/screens/profile_screen.dart');
      expect(
        content.contains('Icons.settings') ,
        isTrue,
        reason: 'AppBar.actions must include a settings/gear icon button',
      );
    });
  });

  group('existing ProfileScreen content is untouched', () {
    test('username, LOG OUT, referral, and reputation content still present',
        () {
      final content = _read('lib/screens/profile_screen.dart');
      expect(content.contains('LOG OUT'), isTrue,
          reason: 'Logout button must remain on ProfileScreen');
      expect(content.contains('REPUTATION'), isTrue,
          reason: 'Reputation row must remain unchanged');
      expect(content.contains('ZONES OWNED'), isTrue,
          reason: 'Zones-owned count must remain unchanged');
      expect(content.contains('_ReferralSection'), isTrue,
          reason: 'Referral section must remain unchanged');
    });
  });
}
