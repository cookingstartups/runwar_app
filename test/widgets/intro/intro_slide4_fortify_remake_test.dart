// test/widgets/intro/intro_slide4_fortify_remake_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md (R-12..R-14)
// Design: IntroFortifyMap rewritten in place — exactly 3 re-laps, ARMOR 1-2-3
// progression, addListener+setState anti-pattern removed in favor of
// AnimatedBuilder-derived lap computation.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sourceText() {
  const relPath = 'lib/widgets/intro/intro_fortify_map.dart';
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

void main() {
  group('R-12: exactly 3 re-laps at ~2.7s/lap within an 8s total loop', () {
    // GIVEN  slide 4's AnimationController
    // WHEN   its duration is inspected
    // THEN   it is 8s total, not the old 7.5s/15-loop cycle
    test('AnimationController duration is 8s (not the old 7.5s cycle)', () {
      final src = _sourceText();
      expect(src, contains('Duration(milliseconds: 8000)'),
          reason: 'R-12: total loop must be ~8s');
      expect(src, isNot(contains('Duration(milliseconds: 7500)')),
          reason: 'R-12: the old 7.5s/15-loop cycle duration must be replaced');
    });

    // GIVEN  the lap-derivation logic
    // WHEN   the source is inspected
    // THEN   laps are computed as (_ctrl.value * 3), not (_ctrl.value * 15)
    test('lap computation uses a factor of 3, not the old factor of 15', () {
      final src = _sourceText();
      expect(src, contains('_ctrl.value * 3'),
          reason: 'R-12: exactly 3 laps must be derived from the controller value');
      expect(src, isNot(contains('_ctrl.value * 15')),
          reason: 'R-12: the old 15-level derivation must be removed');
    });
  });

  group('R-12: ARMOR badge progression 1 -> 2 -> 3, gold-tinted at 3', () {
    // GIVEN  the badge text source
    // WHEN   inspected
    // THEN   the three ARMOR badge strings are present and the old
    //        "LV 1"..."LV 15" numeric counter framing is gone from this file
    test('ARMOR 1/2/3 badge strings are present', () {
      final src = _sourceText();
      expect(src, contains('ARMOR 1'), reason: 'R-12: ARMOR 1 badge must exist');
      expect(src, contains('ARMOR 2'), reason: 'R-12: ARMOR 2 badge must exist');
      expect(src, contains('ARMOR 3'), reason: 'R-12: ARMOR 3 badge must exist');
    });

    test('old numeric "LV" level-counter framing is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains("'LV ")),
          reason: 'R-12: the old climbing numeric LV counter must not remain '
              'in this onboarding animation');
    });
  });

  group('R-12/R-14: addListener+setState anti-pattern is removed', () {
    // GIVEN  the current build's _onTick/_level/addListener anti-pattern
    // WHEN   the rewritten source is inspected
    // THEN   _onTick, the int _level field, and _ctrl.addListener are all gone
    test('_onTick method is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('_onTick')),
          reason: 'design.md: _onTick must be removed (anti-pattern eliminated)');
    });

    test('_ctrl.addListener call is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('.addListener(')),
          reason: 'design.md: addListener must be removed; lap/badge/border '
              'are derived as a pure function of _ctrl.value inside AnimatedBuilder');
    });

    test('int _level state field is absent from source file', () {
      final src = _sourceText();
      expect(src, isNot(contains('int _level')),
          reason: 'design.md: the separate _level state field must be removed');
    });

    // GIVEN  the anti-pattern is removed
    // WHEN   the source is inspected
    // THEN   AnimatedBuilder is still present as the sole rebuild mechanism
    test('AnimatedBuilder is present as the rebuild mechanism', () {
      final src = _sourceText();
      expect(src, contains('AnimatedBuilder'),
          reason: 'design.md: AnimatedBuilder must remain the sole rebuild path');
    });
  });

  group('R-14: updated copy for slide 4', () {
    test('slide 4 headline/body match the new copy', () {
      final src = File('lib/screens/intro_screen.dart').existsSync()
          ? File('lib/screens/intro_screen.dart').readAsStringSync()
          : File('/home/algif/repos/venture/runwar/runwar_app/lib/screens/intro_screen.dart')
              .readAsStringSync();
      expect(src, contains('Run it again. Make it armor.'),
          reason: 'R-14: slide 4 headline must be updated');
      expect(
        src,
        contains('Every extra lap hardens your claim. Level 1, level 2, level 3.'),
        reason: 'R-14: slide 4 body must be updated',
      );
    });
  });
}
