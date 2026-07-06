// test/widgets/intro/intro_copy_table_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md
// (R-5, R-10, R-14, R-19, R-22, R-26, R-31, R-32) — copy table across all
// 10 slides, source-inspection of the _slides list in intro_screen.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sourceText() {
  const relPath = 'lib/screens/intro_screen.dart';
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

void main() {
  group('R-32: slides 1, 5, 6 copy-only updates', () {
    test('slide 1 headline/body match the new copy', () {
      final src = _sourceText();
      expect(src, contains('A rival stole your block.'),
          reason: 'R-32: slide 1 headline must be updated');
      expect(
        src,
        contains('Every street belongs to the last runner who looped it.'),
        reason: 'R-32: slide 1 body must be updated',
      );
    });

    test('slide 5 headline/body match the new copy', () {
      final src = _sourceText();
      expect(src, contains('Pay in kilometers. Not in cash.'),
          reason: 'R-32: slide 5 headline must be updated');
      expect(
        src,
        contains('Shields, strikes, radar sweeps. Superpowers cannot be bought.'),
        reason: 'R-32: slide 5 body must be updated',
      );
    });

    test('slide 6 headline/body match the new copy', () {
      final src = _sourceText();
      expect(src, contains('First feet take it all.'),
          reason: 'R-32: slide 6 headline must be updated');
      expect(
        src,
        contains('Crates hit the map without warning.'),
        reason: 'R-32: slide 6 body must be updated',
      );
    });

    // GIVEN  slides 1, 5, 6 keep their animation widgets byte-for-byte
    // WHEN   the _slides entries are inspected
    // THEN   they still dispatch to pulse/defense/lootDrop respectively
    //        (no new _Anim value introduced for these three slides)
    test('slides 1/5/6 still dispatch to their unchanged animation widgets', () {
      final src = _sourceText();
      expect(src, contains('anim: _Anim.pulse'),
          reason: 'R-32: slide 1 animation widget must remain unchanged');
      expect(src, contains('anim: _Anim.defense'),
          reason: 'R-32: slide 5 animation widget must remain unchanged '
              '(IntroDefenseMap, distinct from IntroDefenseMapA used by slide 3)');
      expect(src, contains('anim: _Anim.lootDrop'),
          reason: 'R-32: slide 6 animation widget must remain unchanged');
    });
  });

  group('Copy table: slides 2, 3, 4, 7, 8, 9, 10 (cross-check against per-slide tests)', () {
    test('all 7 reworked slides carry their exact new headline strings', () {
      final src = _sourceText();
      const expectedHeadlines = [
        'Loop it. Own it.',
        'Under attack? Tap back.',
        'Run it again. Make it armor.',
        'A flag drops. The city sprints.',
        'Stay above the line.',
        'Real streets. Real rivals.',
        'Choose your ground.',
      ];
      for (final headline in expectedHeadlines) {
        expect(src, contains(headline),
            reason: 'Copy table: headline "$headline" must appear in _slides');
      }
    });
  });

  group('R-33: slide order and navigation unchanged', () {
    // GIVEN  the 10-slide deck after this change ships
    // WHEN   the _slides list is inspected
    // THEN   it still contains exactly 10 entries (no slide added/removed)
    test('_slides list contains exactly 10 entries', () {
      final src = _sourceText();
      final match =
          RegExp(r'const _slides = \[([\s\S]*?)\n\];').firstMatch(src);
      expect(match, isNotNull, reason: 'R-33: _slides list must exist');
      final block = match!.group(1)!;
      final entryCount = RegExp(r'_Slide\(').allMatches(block).length;
      expect(entryCount, equals(10),
          reason: 'R-33: exactly 10 slides must remain, same order, no additions/removals');
    });
  });

  group('R-34: no Lottie dependency introduced', () {
    test('no .json Lottie asset or Lottie import appears in intro_screen.dart', () {
      final src = _sourceText();
      expect(src, isNot(contains('lottie')),
          reason: 'R-34: no Lottie package/asset may be introduced');
    });
  });
}
