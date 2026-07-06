// test/widgets/intro/intro_continuity_test.dart
//
// RED phase - SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md (R-6, R-11, R-13)
// Design: IntroContinuity shared-constants block (intro_helpers.dart)
//
// Source-inspection only - no widget pumps (protocol pattern #2): these are
// pure "does this constant appear in this file" checks across 4 files.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relPath) {
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

void main() {
  group('AC-CONT-1: IntroContinuity block exists in intro_helpers.dart', () {
    // GIVEN  intro_helpers.dart after this spec ships
    // WHEN   the file is inspected
    // THEN   an IntroContinuity block defines kMapCenter/kMapZoom/
    //        kBlock1EndFillAlpha/kBlock1EndBorderWidth
    test('IntroContinuity class with all 4 shared constants is declared', () {
      final src = _read('lib/widgets/intro/intro_helpers.dart');
      expect(src, contains('IntroContinuity'),
          reason: 'R-11: IntroContinuity block must exist in intro_helpers.dart');
      expect(src, contains('kMapCenter'),
          reason: 'R-11: IntroContinuity.kMapCenter must be declared');
      expect(src, contains('kMapZoom'),
          reason: 'R-11: IntroContinuity.kMapZoom must be declared');
      expect(src, contains('kBlock1EndFillAlpha'),
          reason: 'R-6: IntroContinuity.kBlock1EndFillAlpha must be declared');
      expect(src, contains('kBlock1EndBorderWidth'),
          reason: 'R-6: IntroContinuity.kBlock1EndBorderWidth must be declared');
    });
  });

  group('AC-CONT-2: slides 2/3/4 all reference IntroContinuity (no divergent literals)', () {
    // GIVEN  slides 2, 3, 4 widget files
    // WHEN   each is inspected for the shared map center/zoom reference
    // THEN   all three reference IntroContinuity.kMapCenter/kMapZoom rather
    //        than repeating a bare LatLng(39.4650, -0.3756) literal
    test('intro_capture_map.dart references IntroContinuity.kMapCenter/kMapZoom', () {
      final src = _read('lib/widgets/intro/intro_capture_map.dart');
      expect(src, contains('IntroContinuity.kMapCenter'),
          reason: 'R-11: slide 2 must reference the shared map center constant');
      expect(src, contains('IntroContinuity.kMapZoom'),
          reason: 'R-11: slide 2 must reference the shared zoom constant');
    });

    test('intro_defense_map.dart references IntroContinuity.kMapCenter/kMapZoom', () {
      final src = _read('lib/widgets/intro/intro_defense_map.dart');
      expect(src, contains('IntroContinuity.kMapCenter'),
          reason: 'R-11: slide 3 must reference the shared map center constant');
      expect(src, contains('IntroContinuity.kMapZoom'),
          reason: 'R-11: slide 3 must reference the shared zoom constant');
    });

    test('intro_fortify_map.dart references IntroContinuity.kMapZoom', () {
      final src = _read('lib/widgets/intro/intro_fortify_map.dart');
      expect(src, contains('IntroContinuity.kMapZoom'),
          reason: 'R-13: slide 4 must reference the shared zoom constant');
    });

    // Slide 2 (FORTIFY)'s visualTopTextBottom layout overlays the text panel
    // over the bottom half of the screen, so this slide keeps its own local
    // map center (declared and used only in intro_fortify_map.dart) instead
    // of IntroContinuity.kMapCenter, which stays shared by slides 3 and 4.
    test('intro_fortify_map.dart declares and uses its own local map center', () {
      final src = _read('lib/widgets/intro/intro_fortify_map.dart');
      expect(src, contains('_kMapCenter'),
          reason: 'slide 2 must declare its own local map center constant');
      expect(src, contains('center: _kMapCenter'),
          reason: 'slide 2 must pass its own local center to buildIntroMap, '
              'not the shared IntroContinuity.kMapCenter');
      expect(src, isNot(contains('center: IntroContinuity.kMapCenter')),
          reason: 'slide 2 must no longer pass the shared center constant');
    });
  });

  group('AC-CONT-3: slide 4 renders FORTIFY end-state via IntroContinuity constants', () {
    // GIVEN  IntroDefenseMapA's Beat-1 (0-1s) paint path, now chained after
    //        FORTIFY (slide 2) rather than the hex-capture slide, following
    //        the carousel reorder that put YOUR TURF between them
    // WHEN   the source is inspected
    // THEN   it draws using IntroContinuity.kFortifyEndFillAlpha/
    //        kFortifyEndBorderWidth rather than re-deriving its own
    //        fill/border constants
    test('intro_defense_map.dart uses IntroContinuity FORTIFY end-state fill/border constants', () {
      final src = _read('lib/widgets/intro/intro_defense_map.dart');
      expect(src, contains('IntroContinuity.kFortifyEndFillAlpha'),
          reason:
              'slide 4 opening frame must reuse FORTIFY (slide 2)\'s terminal fill alpha');
      expect(src, contains('IntroContinuity.kFortifyEndBorderWidth'),
          reason:
              'slide 4 opening frame must reuse FORTIFY (slide 2)\'s terminal border width');
    });
  });

  group('AC-CONT-4: slide 4 traces kS1Block1 directly, no bespoke route', () {
    // GIVEN  intro_fortify_map.dart's route data
    // WHEN   the source is inspected
    // THEN   the bespoke _kFortifyRoute (6 hand-authored waypoints) is gone;
    //        the widget instead traces IntroZones.kS1Block1
    test('_kFortifyRoute bespoke waypoint constant is absent from source file', () {
      final src = _read('lib/widgets/intro/intro_fortify_map.dart');
      expect(src, isNot(contains('_kFortifyRoute')),
          reason: 'R-13: bespoke _kFortifyRoute must be dropped in favor of kS1Block1');
    });

    test('intro_fortify_map.dart references IntroZones.kS1Block1', () {
      final src = _read('lib/widgets/intro/intro_fortify_map.dart');
      expect(src, contains('IntroZones.kS1Block1'),
          reason: 'R-13: slide 4 must trace the shared kS1Block1 geometry');
    });
  });
}
