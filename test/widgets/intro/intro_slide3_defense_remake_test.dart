// test/widgets/intro/intro_slide3_defense_remake_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md (R-7..R-11)
// Design: IntroDefenseMapA rewritten in place, 4-beat/8s continuity scene;
// new IntroPhoneCardOverlay widget (Positioned direct Stack child).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relPath) {
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

void main() {
  group('R-7: 4-beat continuity scene over an 8s loop', () {
    // GIVEN  slide 3's AnimationController
    // WHEN   its duration is inspected
    // THEN   it is 8s, not the old 9s cycle
    test('AnimationController duration is 8s (replacing the old 9s cycle)', () {
      final src = _read('lib/widgets/intro/intro_defense_map.dart');
      expect(src, contains('Duration(seconds: 8)'),
          reason: 'R-7: slide 3 loop must be 8s');
      expect(src, isNot(contains('Duration(seconds: 9)')),
          reason: 'R-7: the old 9s cycle duration must be replaced');
    });

    // GIVEN  slide 3's own map center/route
    // WHEN   inspected against the old bespoke Beat data
    // THEN   the old unconnected _kP3RouteA / own map center are gone
    test('old unconnected _kP3RouteA attacker route is absent from source file', () {
      final src = _read('lib/widgets/intro/intro_defense_map.dart');
      expect(src, isNot(contains('_kP3RouteA')),
          reason: 'R-7/R-11: the old unconnected attacker route must be replaced '
              'by the new pink-comet raid beat sharing continuity constants');
    });
  });

  group('R-8: phone-card overlay is a Positioned direct Stack child', () {
    // GIVEN  the new intro_phone_card_overlay.dart file
    // WHEN   inspected
    // THEN   it declares a StatelessWidget named IntroPhoneCardOverlay
    test('intro_phone_card_overlay.dart declares IntroPhoneCardOverlay StatelessWidget', () {
      final src = _read('lib/widgets/intro/intro_phone_card_overlay.dart');
      expect(src, contains('class IntroPhoneCardOverlay'),
          reason: 'R-8: a distinct IntroPhoneCardOverlay widget must exist');
      expect(src, contains('StatelessWidget'),
          reason: 'R-8: the phone-card overlay must be a plain StatelessWidget, '
              'not part of the map CustomPainter');
    });

    // GIVEN  IntroDefenseMapA's Stack composition
    // WHEN   inspected
    // THEN   IntroPhoneCardOverlay is wrapped in Positioned as a direct Stack
    //        child (protocol rule: overlay widgets are Positioned Stack
    //        children, never painted inside the CustomPainter)
    test('IntroDefenseMapA wires IntroPhoneCardOverlay via Positioned(...) in its Stack', () {
      final src = _read('lib/widgets/intro/intro_defense_map.dart');
      expect(src, contains('IntroPhoneCardOverlay'),
          reason: 'R-8: slide 3 must mount the phone-card overlay widget');
      final positionedOverlay = RegExp(
        r'Positioned\([\s\S]{0,200}?IntroPhoneCardOverlay',
      ).hasMatch(src);
      expect(positionedOverlay, isTrue,
          reason: 'R-8: IntroPhoneCardOverlay must be a Positioned direct Stack '
              'child, not drawn inside the CustomPainter');
    });
  });

  group('R-9: raid attempt visibly fails (attacker trace shatters/retreats)', () {
    // GIVEN  slide 3's Beat 4 (5-8s)
    // WHEN   the source is inspected
    // THEN   a visible shatter/retreat treatment exists for the attacker trace
    test('source implements a shatter/retreat treatment for the attacker trace', () {
      final src = _read('lib/widgets/intro/intro_defense_map.dart');
      final hasShatterOrRetreat =
          src.contains('shatter') || src.contains('retreat');
      expect(hasShatterOrRetreat, isTrue,
          reason: 'R-9: the raid must visibly fail via a shatter/retreat treatment, '
              'not resolve off-screen or via silent recolor');
    });

    // GIVEN  the block must never transition to a rival color
    // WHEN   the source is inspected
    // THEN   the "DEFENDED" stamp is present
    test('"DEFENDED" stamp text is present in source file', () {
      final src = _read('lib/widgets/intro/intro_defense_map.dart');
      expect(src, contains('DEFENDED'),
          reason: 'R-9: a DEFENDED stamp must appear once the raid is repelled');
    });
  });

  group('R-10: updated copy for slide 3', () {
    // GIVEN  intro_screen.dart's _slides list, slide 3 entry
    // WHEN   inspected
    // THEN   tag/headline/body match the new copy exactly, and the old
    //        "SHIELD · VARIANT A" tag / "Activate. Drop the shield." headline
    //        are gone
    test('slide 3 headline/body match the new copy', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('Under attack? Tap back.'),
          reason: 'R-10: slide 3 headline must be updated');
      expect(
        src,
        contains('Fire your shield straight from the phone. The attack breaks. '
            'Your paint stays.'),
        reason: 'R-10: slide 3 body must be updated',
      );
    });

    test('old "SHIELD · VARIANT A" tag and old headline are gone', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('SHIELD · VARIANT A')),
          reason: 'R-10: the old variant-A tag copy must be replaced with "SHIELD"');
      expect(src, isNot(contains('ACTIVATE.\\nDROP THE SHIELD.')),
          reason: 'R-10: the old headline must be replaced');
    });

    test('mono subline for slide 3 is present', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(
        src,
        contains('DEFEND FROM HOME, FROM WORK, FROM BED'),
        reason: 'R-10: slide 3 must carry the new mono subline',
      );
    });
  });
}
