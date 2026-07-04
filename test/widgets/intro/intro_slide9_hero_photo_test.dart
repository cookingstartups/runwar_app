// test/widgets/intro/intro_slide9_hero_photo_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md (R-23..R-27)
// Design: IntroPhysicalEventsMap retired; new intro_hero_photo.dart /
// IntroHeroPhoto with a single forward-repeating Ken Burns controller.
//
// NOTE: the photo asset test (R-25) is expected RED until the commissioned
// asset ships (implementation-time deliverable per design.md) — a missing
// file is the correct RED reason here, not a config error.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relPath) {
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

void main() {
  group('R-23: IntroPhysicalEventsMap abstract painter is retired', () {
    // GIVEN  intro_screen.dart after this change ships
    // WHEN   inspected
    // THEN   no reference to IntroPhysicalEventsMap remains
    test('intro_screen.dart no longer references IntroPhysicalEventsMap', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('IntroPhysicalEventsMap')),
          reason: 'R-23: the abstract 3-dot race painter must not remain wired');
    });

    test('intro_screen.dart wires the new IntroHeroPhoto widget for slide 9', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('IntroHeroPhoto'),
          reason: 'R-23: slide 9 must render the new hero-photo widget');
    });
  });

  group('R-23/R-27: Ken Burns motion via a single forward-repeating controller', () {
    // GIVEN  the new intro_hero_photo.dart file
    // WHEN   inspected
    // THEN   a single AnimationController..repeat() (forward-only, no
    //        reverse: true ping-pong) drives a triangular value profile
    test('intro_hero_photo.dart declares IntroHeroPhoto', () {
      final src = _read('lib/widgets/intro/intro_hero_photo.dart');
      expect(src, contains('class IntroHeroPhoto'),
          reason: 'R-23: a new IntroHeroPhoto widget must exist');
    });

    test('AnimationController uses forward repeat(), not reverse: true ping-pong', () {
      final src = _read('lib/widgets/intro/intro_hero_photo.dart');
      expect(src, contains('..repeat()'),
          reason: 'R-23/R-27: design mandates a single forward-only repeat(), '
              'not a ping-pong reverse: true controller');
      expect(src, isNot(contains('reverse: true')),
          reason: 'R-23: reverse: true ping-pong was explicitly rejected in design.md');
    });

    test('scale range 1.00 to 1.09 is present', () {
      final src = _read('lib/widgets/intro/intro_hero_photo.dart');
      expect(src, contains('1.09'),
          reason: 'R-23: Ken Burns scale must reach 1.09');
    });

    test('no second AnimationStatusListener is added for direction detection', () {
      final src = _read('lib/widgets/intro/intro_hero_photo.dart');
      expect(src, isNot(contains('AnimationStatusListener')),
          reason: 'design.md: an AnimationStatusListener was explicitly rejected '
              'as the mechanism for gating the once-per-cycle light sweep');
    });
  });

  group('R-27: zero new runtime dependencies', () {
    // GIVEN  pubspec.yaml after the slide-9 change ships
    // WHEN   inspected
    // THEN   no Lottie or video package dependency has been added
    test('pubspec.yaml adds no Lottie or video package dependency', () {
      final src = _read('pubspec.yaml');
      expect(src, isNot(contains('lottie:')),
          reason: 'R-27/R-34: no Lottie dependency may be added for slide 9');
      expect(src, isNot(contains('video_player:')),
          reason: 'R-27: no video package dependency may be added for slide 9');
    });
  });

  group('R-25: asset size budget (under 1 MB, target 200-350 KB)', () {
    // GIVEN  the final slide-9 asset file
    // WHEN   its file size is checked
    // THEN   it is under 1 MB
    // Expected RED until the commissioned asset ships — a missing file here
    // is the correct failure reason for this RED phase.
    test('assets/hero_photos/game_gets_real.jpg exists and is under 1 MB', () {
      final path = 'assets/hero_photos/game_gets_real.jpg';
      final file = File(path).existsSync()
          ? File(path)
          : File('/home/algif/repos/venture/runwar/runwar_app/$path');
      expect(file.existsSync(), isTrue,
          reason: 'R-25: the commissioned hero photo asset must exist '
              '(implementation-time deliverable, expected RED until it ships)');
      if (file.existsSync()) {
        expect(file.lengthSync(), lessThan(1024 * 1024),
            reason: 'R-25: asset must be under 1 MB (target 200-350 KB)');
      }
    });
  });

  group('R-26: updated copy for slide 9', () {
    test('slide 9 headline/body match the new copy', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('Real streets. Real rivals.'),
          reason: 'R-26: slide 9 headline must be updated');
      expect(
        src,
        contains('Behind every gamertag is a runner in your city.'),
        reason: 'R-26: slide 9 body must be updated',
      );
    });

    test('old "THE GAME GETS REAL" copy is gone', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('THE GAME\\nGETS REAL.')),
          reason: 'R-26: the current build\'s headline must be replaced');
    });
  });
}
