// test/widgets/intro/intro_slide7_flag_drop_remake_test.dart
//
// Lean source-inspection tests for the slide 7 (CTF) trisection rework.
// IntroFlagDropMap mounts a FlutterMap, so runtime widget tests generate
// hundreds of tile-fetch exceptions in the test environment - per
// flutter-test-patterns.md, routing/structural assertions are verified via
// static source inspection instead of testWidgets.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relPath) => File(relPath).readAsStringSync();

// Baseline tile-directory line count verified 2026-07-04 (Ruzafa/Alameda only:
// z15 4 columns + z16 7 columns = 11 lines) - unaffected by this rework since
// the trisection/faction changes are purely code-side, no new tile assets.
const int _kBaselineTileDirLineCount = 11;

void main() {
  group('real Hemisferic-plaza coordinates replace the old drop point', () {
    test('_kDropCoord equals the new Placa de la Marato coordinate', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('39.4567170'),
          reason: 'new drop latitude must be exact');
      expect(src, contains('-0.3553929'),
          reason: 'new drop longitude must be exact');
    });

    test('old Museu esplanade drop coordinate is fully removed', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, isNot(contains('39.457074305497436')),
          reason: 'old drop latitude must not remain anywhere in the file');
      expect(src, isNot(contains('-0.35217545801606326')),
          reason: 'old drop longitude must not remain anywhere in the file');
    });

    test('the 3 real routes reference new waypoints, not the old superseded ones',
        () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('_kRouteA'));
      expect(src, contains('_kRouteB'));
      expect(src, contains('_kRouteC'));
      // Spot-check one real, non-interpolated waypoint from each new route.
      expect(src, contains('39.4596015'), reason: 'Route A north-bank waypoint');
      expect(src, contains('39.4538975'), reason: 'Route B SE-avenue waypoint');
      expect(src, contains('39.4539054'), reason: 'Route C SW-arm waypoint');
      // The old route waypoints must be gone (migrated, not just appended).
      expect(src, isNot(contains('39.4662369')),
          reason: 'old Route A riverbed waypoint must be replaced');
      expect(src, isNot(contains('39.4506227')),
          reason: 'old Route C waypoint must be replaced');
    });
  });

  group('camera drops at zoom 16, eases out to 15.5 (unchanged mechanic)', () {
    test('zoom 15.5 ease-out target value is present', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('15.5'));
    });

    test('initial zoom 16.0 is still present alongside the ease-out', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('zoom: 16.0'));
    });
  });

  group('camera reframe decouples the camera center from the drop point', () {
    test('a separate camera-center resolver exists', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('_resolveCameraCenter'),
          reason: 'the camera must center on a computed point, not directly '
              'on _kDropCoord');
      expect(src, contains('_kDropAnchorYFraction'),
          reason: 'the bottom-half anchor fraction constant must be present');
    });

    test(
        'buildIntroMap is fed the resolved camera center, not the raw drop coordinate',
        () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('center: cameraCenter'),
          reason: 'the map must center on the shifted camera point');
      expect(src, isNot(contains('center: _kDropCoord')),
          reason: 'the map must no longer center directly on the drop point');
    });
  });

  group('faction color palette replaces the old all-orange runners', () {
    test('all 3 real faction colors are wired into the comet/dot draw calls',
        () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('color: kSea'), reason: 'faction blue must be used');
      expect(src, contains('color: kRunnerCPink'),
          reason: 'faction pink must be used');
      expect(src, contains('color: kLimeGreen'),
          reason: 'faction lime must be used');
    });

    test('kAccent (orange) is no longer used to color a runner route', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, isNot(contains('color: kAccent,')),
          reason:
              'the orange runner-A color must be fully retired for this slide');
    });

    test(
        'kLimeGreen is defined in theme.dart with the exact Valencia lime hex',
        () {
      final src = _read('lib/theme.dart');
      expect(src, contains('kLimeGreen'));
      expect(src, contains('0xFFA6FF00'));
    });
  });

  group('trisection + base-spawn beats replace the single-point mechanic', () {
    test('the trisection wedge overlay draw routine is wired in', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('drawCtfTrisection'),
          reason: 'the 3-faction wedge overlay must be drawn every frame');
    });

    test(
        'the base-spawn marker draw routine is wired in with a hidden "?" state',
        () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('drawCtfBaseMarker'));
      expect(src, contains('revealed: true'),
          reason: "the carrier's own base must render visible");
      expect(src, contains('revealed: false'),
          reason: 'rival bases must render as the unlabeled "?" marker');
    });

    test('the new helper file defines exactly 3 seamless 120-degree factions',
        () {
      final src = _read('lib/widgets/intro/intro_ctf_trisection.dart');
      expect(src, contains('kCtfSectorSweep'));
      expect(src, contains('ctfFactionBlue'));
      expect(src, contains('ctfFactionPink'));
      expect(src, contains('ctfFactionLime'));
    });

    test(
        'no regression: the superseded single-point converge-and-touch beats no longer stand alone',
        () {
      // The old mechanic had exactly 3 beats (flag land, runners converge,
      // arrival bursts) and nothing else. The rework must add the
      // trisection + base/steal beats on top, not merely relabel colors.
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('INTERCEPT!'),
          reason: 'the steal-attempt beat must be present');
      expect(src, contains('CAPTURED'),
          reason: 'the capture-confirmation beat must be present');
    });
  });

  group('8s beat timeline (grew from the old 5s single-beat loop)', () {
    test('the animation controller now runs an 8-second loop', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('Duration(seconds: 8)'));
      expect(src, isNot(contains('Duration(seconds: 5)')),
          reason: 'the old 5s loop duration must not remain in this file');
    });

    test('all 6 beat-timeline constants are present', () {
      final src = _read('lib/widgets/intro/intro_flag_drop_map.dart');
      expect(src, contains('_kTrisectionEnd'));
      expect(src, contains('_kLockStart'));
      expect(src, contains('_kFlagDropStart'));
      expect(src, contains('_kBaseSpawnStart'));
      expect(src, contains('_kCarryStart'));
      expect(src, contains('_fadeStart'));
    });
  });

  group('slide 7 copy is unchanged by this rework', () {
    test('slide 7 headline/body still match the existing copy', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('A flag drops. The city sprints.'));
      expect(
        src,
        contains(
            'One flag. One exact GPS point. Every runner notified in the '
            'same second.'),
      );
    });
  });

  group('offline tile prefetch is unaffected by this rework', () {
    test('pubspec.yaml still declares the baseline intro_tiles directories',
        () {
      final src = _read('pubspec.yaml');
      final tileDirLines =
          RegExp(r'- assets/intro_tiles/\d+/\d+/').allMatches(src).length;
      expect(
        tileDirLines,
        greaterThanOrEqualTo(_kBaselineTileDirLineCount),
        reason: 'this rework does not remove or change tile assets',
      );
    });

    test('pubspec.yaml still declares z15 and z16 tile directories', () {
      final src = _read('pubspec.yaml');
      expect(src, contains('assets/intro_tiles/15/'));
      expect(src, contains('assets/intro_tiles/16/'));
    });
  });
}
