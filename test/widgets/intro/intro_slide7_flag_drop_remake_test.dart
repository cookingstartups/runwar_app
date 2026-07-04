// test/widgets/intro/intro_slide7_flag_drop_remake_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md (R-15..R-19, R-35)
// Design: IntroFlagDropMap rewritten in place — new City of Arts drop
// coordinate, zoom 16 -> 15.5 ease-out, three real-street routes, offline
// tile prefetch for the new area.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relPath) {
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

// Baseline tile-directory line count verified 2026-07-04 (Ruzafa/Alameda only:
// z15 4 columns + z16 7 columns = 11 lines) before R-35's new tiles ship.
const int _kBaselineTileDirLineCount = 11;

void main() {
  group('R-15: flag drop at the verified City of Arts coordinate', () {
    // GIVEN  slide 7's flag-drop coordinate constant
    // WHEN   it is inspected
    // THEN   it equals the exact new coordinate and the old Alameda Metro
    //        drop point is gone
    test('_kDropCoord equals the exact new City of Arts coordinate', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('39.457074305497436'),
          reason: 'R-15: new drop latitude must be exact');
      expect(src, contains('-0.35217545801606326'),
          reason: 'R-15: new drop longitude must be exact');
    });

    test('old Alameda Metro drop coordinate 39.47140/-0.36490 is absent', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, isNot(contains('39.47140')),
          reason: 'R-15: old Alameda Metro drop latitude must be removed');
    });
  });

  group('R-16: camera drops at zoom 16, eases out to 15.5', () {
    // GIVEN  slide 7's camera initialization
    // WHEN   the source is inspected
    // THEN   zoom starts at 16.0 and a tween eases it to 15.5
    test('zoom 15.5 ease-out target value is present', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('15.5'),
          reason: 'R-16: the eased-out zoom value 15.5 must appear');
    });

    test('initial zoom 16.0 is still present alongside the ease-out', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('zoom: 16.0'),
          reason: 'R-16: the camera must still initialize at zoom 16');
    });
  });

  group('R-17: three routes converge on the drop point', () {
    // GIVEN  slide 7's three route definitions
    // WHEN   inspected
    // THEN   _kRouteA/_kRouteB/_kRouteC all exist and the old Alameda-area
    //        waypoints are gone
    test('_kRouteA, _kRouteB and _kRouteC constants all exist', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('_kRouteA'), reason: 'R-17: Route A must exist');
      expect(src, contains('_kRouteB'), reason: 'R-17: Route B must exist');
      expect(src, contains('_kRouteC'), reason: 'R-17: Route C must exist');
    });

    test('old Alameda-area route waypoints are absent from source file', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, isNot(contains('39.48600')),
          reason: 'R-17: old Route A off-screen-north waypoint must be replaced');
      expect(src, isNot(contains('39.46100')),
          reason: 'R-17: old Route C off-screen-south waypoint must be replaced');
    });
  });

  group('R-18: flag lands before runner comets advance', () {
    // GIVEN  slide 7's camera-story-order gate
    // WHEN   the source is inspected
    // THEN   a flag-land gate constant/guard exists before runner progress
    //        is computed
    test('a flag-land timing gate exists before runner progress computation', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('_kFlagLandT'),
          reason: 'R-18: a _kFlagLandT gate must delay runner comets until '
              'the flag-drop animation completes');
    });
  });

  group('R-19: updated copy for slide 7', () {
    test('slide 7 headline/body match the new copy', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('A flag drops. The city sprints.'),
          reason: 'R-19: slide 7 headline must be updated');
      expect(
        src,
        contains('One flag. One exact GPS point. Every runner notified in the '
            'same second.'),
        reason: 'R-19: slide 7 body must be updated',
      );
    });
  });

  group('R-35: offline tile prefetch for the new map center', () {
    // GIVEN  the current baseline pubspec.yaml tile-directory entries
    //        (verified: 11 lines, Ruzafa/Alameda area only)
    // WHEN   slide 7's map center moves to the City of Arts coordinate
    // THEN   new tile directory lines must be added beyond the baseline
    test('pubspec.yaml declares more intro_tiles directories than the baseline', () {
      final src = _read('pubspec.yaml');
      final tileDirLines =
          RegExp(r'- assets/intro_tiles/\d+/\d+/').allMatches(src).length;
      expect(
        tileDirLines,
        greaterThan(_kBaselineTileDirLineCount),
        reason: 'R-35: new tile PNGs for the City of Arts viewport at z15/z16 '
            'must be bundled and their directories enumerated in pubspec.yaml '
            '(baseline was $_kBaselineTileDirLineCount lines, Ruzafa/Alameda only)',
      );
    });

    test('pubspec.yaml still declares z15 and z16 tile directories', () {
      final src = _read('pubspec.yaml');
      expect(src, contains('assets/intro_tiles/15/'),
          reason: 'R-35: z15 fallback coverage is required for the fractional-zoom ease');
      expect(src, contains('assets/intro_tiles/16/'),
          reason: 'R-35: z16 coverage is required for the initial drop zoom');
    });
  });
}
