// test/widgets/intro/intro_slide2_capture_remake_test.dart
//
// Design: IntroCaptureMap rewritten for the 2026-08-29 rival-claim redesign
// - opens on slide 2's fortified terminal state, a kSea rival then claims
// the adjacent kS1Block2 via a street approach + perimeter loop, one-shot
// capture flash, quiet hold. Replaces the old self-reclaim / player-accent
// "CLAIMED" sequence.

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
  group('Rival-claim redesign: kSea rival claims kS1Block2', () {
    // GIVEN  slide 3's rival-claim animation source
    // WHEN   inspected for the rival's color and target block
    // THEN   both kSea (rival color) and IntroZones.kS1Block2 (the claimed
    //        block) are referenced
    test('kSea (rival color) is referenced in source file', () {
      final src = _sourceText();
      expect(src, contains('kSea'),
          reason: 'the rival runner/fill/flash must render in kSea');
    });

    test('IntroZones.kS1Block2 (the claimed block) is referenced', () {
      final src = _sourceText();
      expect(src, contains('IntroZones.kS1Block2'),
          reason: 'the rival must claim the adjacent kS1Block2, not '
              'kS1Block1 again');
    });

    test('the player-orange fortified kS1Block1 stays referenced', () {
      final src = _sourceText();
      expect(src, contains('IntroZones.kS1Block1'),
          reason: 'the player\'s fortified block must stay intact and '
              'visible throughout the scene');
    });

    // GIVEN  the old self-reclaim "CLAIMED" stamp in the player accent
    // WHEN   the source is inspected
    // THEN   it is gone - the rival's claim has no text stamp of its own
    //        (a one-shot capture flash + quiet hold instead)
    test('the old "CLAIMED" stamp text is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('CLAIMED')),
          reason: 'the old self-reclaim CLAIMED stamp must be removed - the '
              'rival claim resolves via a capture flash + quiet hold only');
    });
  });

  group('No contested-border treatment, no dispute geometry (mockup option A)', () {
    test('"DISPUTED"/"CONTESTED" labels are absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('DISPUTED')),
          reason: 'no dispute label may render on slide 3');
      expect(src, isNot(contains('CONTESTED')),
          reason: 'mockup option A (clean claim) carries no CONTESTED tag');
    });

    test('amber flash color 0xFFFFB200 is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('0xFFFFB200')),
          reason: 'no amber dispute-flash color may appear on slide 3');
    });

    test('no shared-edge dispute-geometry constants remain', () {
      final src = _sourceText();
      expect(src, isNot(contains('_kDisputedArea')),
          reason: 'dispute-area geometry must not fire on slide 3');
      expect(src, isNot(contains('_kAttackerLasso')),
          reason: 'attacker-lasso geometry must not fire on slide 3');
      expect(src, isNot(contains('_kSharedTransferVertices')),
          reason: 'shared-transfer ping geometry must not fire on slide 3');
    });
  });

  group('Rival approach stays outside block interiors (street path)', () {
    // GIVEN  the rival's off-screen approach route
    // WHEN   the source is inspected
    // THEN   it is built from right-angle waypoints outside the block
    //        bounding box before joining the block's own perimeter, not a
    //        straight line cutting through the interior
    test('rival route is assembled from a street approach plus the block perimeter', () {
      final src = _sourceText();
      expect(src, contains('_buildRivalRoute'),
          reason: 'the rival route must be built from an explicit street '
              'approach + perimeter-loop helper, not an ad hoc straight line');
      expect(src, contains('rivalRoute'),
          reason: 'the assembled route must be threaded into the painter');
    });
  });
}
