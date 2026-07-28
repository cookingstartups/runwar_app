// test/screens/settings_preferences_test.dart
//
// Covers the Preferences section: the units segmented control persisted via
// DatabaseService.getPref/setPref, and the three real notification channel
// toggles (push, streak reminder, run tracking). Source-inspection, since
// getPref/setPref hit Supabase.instance.client directly and cannot be
// exercised without a live client in this test environment (see
// database_service_split_test.dart for the same escape hatch).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('units preference persists through the existing prefs primitives', () {
    test('settings_screen.dart calls DatabaseService getPref and setPref', () {
      final content = _read('lib/screens/settings_screen.dart');
      expect(content.contains('getPref'), isTrue,
          reason: 'Units control must read through the existing prefs getter');
      expect(content.contains('setPref'), isTrue,
          reason: 'Units control must persist through the existing prefs setter');
    });

    test('settings_screen.dart references both KM and MI options', () {
      final content = _read('lib/screens/settings_screen.dart');
      expect(content.contains('KM'), isTrue, reason: 'KM option must be present');
      expect(content.contains('MI'), isTrue, reason: 'MI option must be present');
    });
  });

  group('three real notification channels, not placeholders', () {
    test('push, streak reminder, and run tracking channels are all named', () {
      final content = _read('lib/screens/settings_screen.dart');
      final lower = content.toLowerCase();
      expect(lower.contains('push'), isTrue,
          reason: 'Push notifications toggle must be labeled');
      expect(lower.contains('streak'), isTrue,
          reason: 'Daily streak reminder toggle must be labeled');
      expect(lower.contains('run tracking') || lower.contains('foreground'),
          isTrue,
          reason: 'Run tracking / foreground-service toggle must be labeled');
    });

    test('no generic or placeholder toggle label is used instead', () {
      final content = _read('lib/screens/settings_screen.dart');
      final lower = content.toLowerCase();
      expect(lower.contains('notification 1'), isFalse);
      expect(lower.contains('generic toggle'), isFalse);
    });
  });
}
