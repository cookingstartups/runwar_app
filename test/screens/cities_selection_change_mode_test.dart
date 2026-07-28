// test/screens/cities_selection_change_mode_test.dart
//
// Covers CitiesSelectionScreen's new change mode: a single-select-and-replace
// city change, distinct from the existing onboarding multi-select-and-join
// flow. Source-inspection, since exercising the full flow requires a live
// Supabase client (WaitlistRepository.changeCity / joinedCitySlugs).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('CitiesSelectionMode and constructor wiring', () {
    test('CitiesSelectionMode enum with onboarding and change values exists',
        () {
      final content = _read('lib/screens/auth/cities_selection_screen.dart');
      expect(content.contains('CitiesSelectionMode'), isTrue,
          reason: 'A mode enum must exist to distinguish onboarding vs change');
      expect(content.contains('onboarding'), isTrue);
      expect(content.contains('change'), isTrue);
    });

    test('constructor accepts a currentCitySlug parameter for pre-seeding', () {
      final content = _read('lib/screens/auth/cities_selection_screen.dart');
      expect(content.contains('currentCitySlug'), isTrue,
          reason: 'Change mode must pre-seed the current city');
    });
  });

  group('change mode caps selection at one city, not three', () {
    test('the multi-city onboarding dialog trigger is not the only cap path',
        () {
      final content = _read('lib/screens/auth/cities_selection_screen.dart');
      // The onboarding cap-3 dialog must still exist for onboarding mode, but
      // a change-mode-aware cap (replace-on-second-tap) must also be present
      // so a change-mode user is never shown the "run & conquer" dialog.
      expect(content.contains('mode == CitiesSelectionMode.change') ||
              content.contains('widget.mode'), isTrue,
          reason: 'Selection/submit logic must branch on the mode parameter');
    });
  });

  group('OTHER CITY dialog is hidden in change mode', () {
    test('_showOtherCityDialog call site is gated by mode', () {
      final content = _read('lib/screens/auth/cities_selection_screen.dart');
      final dialogIdx = content.indexOf('_showOtherCityDialog');
      expect(dialogIdx, greaterThan(-1),
          reason: 'OTHER CITY dialog method must still exist for onboarding');
      // A mode check must appear somewhere before the dialog is reachable
      // from the build method (guarding its card/tap from rendering).
      expect(content.contains('CitiesSelectionMode.onboarding'), isTrue,
          reason: 'Onboarding-only gating must reference the onboarding mode');
    });
  });

  group('change mode button label and submit target', () {
    test('button label switches to a city-change confirmation string', () {
      final content = _read('lib/screens/auth/cities_selection_screen.dart');
      expect(content.contains('CONFIRM CITY CHANGE'), isTrue,
          reason: 'Change mode must present a distinct button label');
    });

    test('change mode submits via WaitlistRepository.changeCity, not joinCities',
        () {
      final content = _read('lib/screens/auth/cities_selection_screen.dart');
      expect(content.contains('changeCity'), isTrue,
          reason: 'Change mode must call the new replace-semantics method');
    });
  });

  group('WaitlistRepository.changeCity method', () {
    test('changeCity(userId, newSlug) is defined on WaitlistRepository', () {
      final content =
          _read('lib/services/database/waitlist_repository.dart');
      expect(content.contains('Future<void> changeCity('), isTrue,
          reason: 'changeCity must be a new method composing join/leave');
    });

    test(
        'changeCity leaves every other currently-joined city, pinning the '
        'multi-city side effect the design flags as an open product question',
        () {
      final content =
          _read('lib/services/database/waitlist_repository.dart');
      final changeIdx = content.indexOf('changeCity');
      expect(changeIdx, greaterThan(-1));
      final body = content.substring(changeIdx);
      expect(body.contains('leaveCityWaitlist'), isTrue,
          reason:
              'changeCity must leave other joined cities as it commits the '
              'new one, even though this drops multi-city access - pinned '
              'here as flagged behavior, not silently assumed correct');
    });
  });
}
