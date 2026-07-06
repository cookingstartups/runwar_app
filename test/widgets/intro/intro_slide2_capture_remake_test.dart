// test/widgets/intro/intro_slide2_capture_remake_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md (R-1..R-4)
// Design: IntroCaptureMap rewritten in place — player-orange protagonist fix,
// squared kS1Block1 loop, 5.2s beat-timed cycle, no dispute mechanics.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sourceText() {
  const relPath = 'lib/widgets/intro/intro_capture_map.dart';
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

void main() {
  group('R-1: player-orange capture, no blue rival on this slide', () {
    // GIVEN  slide 2's capture animation source
    // WHEN   inspected for rival coloring
    // THEN   no kSea (blue) token appears anywhere in the file — the runner,
    //        fill, border and CLAIMED stamp are all kAccent orange
    test('kSea (blue rival color) is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('kSea')),
          reason: 'R-1: protagonist fix requires the runner/fill/border/CLAIMED '
              'to be kAccent orange only — no kSea rival may draw on slide 2');
    });

    // GIVEN  slide 2's capture animation source
    // WHEN   inspected for a pink rival token
    // THEN   no kRunnerCPink appears (that rival belongs to slide 3 only)
    test('kRunnerCPink (pink rival) is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('kRunnerCPink')),
          reason: 'R-1: no rival runner of any color may appear on slide 2');
    });
  });

  group('R-2: squared 4-vertex kS1Block1 loop, no cross-block dispute geometry', () {
    // GIVEN  slide 2's route data
    // WHEN   the capture polygon source is inspected
    // THEN   it references IntroZones.kS1Block1 directly
    test('source references IntroZones.kS1Block1', () {
      final src = _sourceText();
      expect(src, contains('IntroZones.kS1Block1'),
          reason: 'R-2: slide 2 must trace the existing kS1Block1 4-vertex geometry');
    });

    // GIVEN  slide 2 must not introduce cross-block dispute geometry
    // WHEN   the source is inspected
    // THEN   no kS1Block2/kS1Block3 reference and no dispute-only constants exist
    test('no kS1Block2/kS1Block3 or dispute-geometry constants remain', () {
      final src = _sourceText();
      expect(src, isNot(contains('kS1Block2')),
          reason: 'R-2: slide 2 must not overlap kS1Block2');
      expect(src, isNot(contains('kS1Block3')),
          reason: 'R-2: slide 2 must not overlap kS1Block3');
      expect(src, isNot(contains('_kDisputedArea')),
          reason: 'R-4: dispute-area geometry must not fire on slide 2');
      expect(src, isNot(contains('_kAttackerLasso')),
          reason: 'R-4: attacker-lasso geometry must not fire on slide 2');
      expect(src, isNot(contains('_kSharedTransferVertices')),
          reason: 'R-4: shared-transfer ping geometry must not fire on slide 2');
    });
  });

  group('R-3: beat timing — ~4s capture within ~5.2s cycle', () {
    // GIVEN  slide 2's AnimationController
    // WHEN   its duration is inspected
    // THEN   it is configured for ~5.2s (5200ms), replacing the old 8s cycle
    test('AnimationController duration is 5200ms (5.2s cycle)', () {
      final src = _sourceText();
      expect(src, contains('5200'),
          reason: 'R-3: cycle duration must be ~5.2s (5200ms), not the old 8s cycle');
      expect(src, isNot(contains('Duration(seconds: 8)')),
          reason: 'R-3: the old 8-second cycle duration must be replaced');
    });
  });

  group('R-4: no mid-game dispute mechanics render on slide 2', () {
    // GIVEN  slide 2's animation is playing
    // WHEN   the source is inspected for a DISPUTED label or amber flash phase
    // THEN   neither is present in this file's own render path
    test('"DISPUTED" label text is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('DISPUTED')),
          reason: 'R-4: no DISPUTED label may render on slide 2');
    });

    test('amber flash color 0xFFFFB200 is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('0xFFFFB200')),
          reason: 'R-4: no amber dispute-flash color may appear on slide 2');
    });
  });
}
