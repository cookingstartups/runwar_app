// test/widgets/intro/intro_slide8_purge_leaderboard_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md (R-20..R-22)
// Design: IntroSurvivalCut retired; new intro_purge_leaderboard.dart /
// IntroPurgeLeaderboard (operator-locked Option B: leaderboard cut).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relPath) {
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

void main() {
  group('R-21: IntroSurvivalCut circle-grid painter is retired', () {
    // GIVEN  intro_screen.dart after this change ships
    // WHEN   inspected
    // THEN   no reference to IntroSurvivalCut remains (it is wired to the new
    //        leaderboard-cut widget instead)
    test('intro_screen.dart no longer references IntroSurvivalCut', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('IntroSurvivalCut')),
          reason: 'R-21: IntroSurvivalCut must not remain wired for slide 8');
    });

    test('intro_screen.dart no longer references the retired survivalCut enum value', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('_Anim.survivalCut')),
          reason: 'R-21: the _Anim.survivalCut enum value must be retired '
              'in favor of a new purgeCut value');
    });
  });

  group('R-20: leaderboard-cut visualization is wired for slide 8', () {
    // GIVEN  the new intro_purge_leaderboard.dart file
    // WHEN   inspected
    // THEN   it declares IntroPurgeLeaderboard and a data row model with
    //        exactly one row marked isYou: true
    test('intro_purge_leaderboard.dart declares IntroPurgeLeaderboard', () {
      final src = _read('lib/widgets/intro/intro_purge_leaderboard.dart');
      expect(src, contains('class IntroPurgeLeaderboard'),
          reason: 'R-20: a new IntroPurgeLeaderboard widget must exist');
    });

    test('exactly one leaderboard row is marked isYou: true', () {
      final src = _read('lib/widgets/intro/intro_purge_leaderboard.dart');
      final isYouCount = 'isYou: true'.allMatches(src).length;
      expect(isYouCount, equals(1),
          reason: 'R-20: exactly one "YOU" row must be positioned near the cut line');
    });

    test('intro_screen.dart wires the new leaderboard widget into slide 8', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('IntroPurgeLeaderboard'),
          reason: 'R-20: slide 8 must render the new leaderboard-cut widget');
    });
  });

  group('R-20 unwanted-behaviour guard: Option A/C are never implemented', () {
    // GIVEN  the operator-locked D1 decision (Option B only)
    // WHEN   the new leaderboard file is inspected
    // THEN   no "map burn" (Option A) or "territory decay" (Option C) code
    //        path exists anywhere in this file
    test('no map-burn-off (Option A) treatment exists in the new file', () {
      final src = _read('lib/widgets/intro/intro_purge_leaderboard.dart');
      final hasMapBurn = src.contains('map burn') || src.contains('mapBurn');
      expect(hasMapBurn, isFalse,
          reason: 'R-20: Option A (map burns off) is explicitly not chosen');
    });

    test('no territory-decay (Option C) treatment exists in the new file', () {
      final src = _read('lib/widgets/intro/intro_purge_leaderboard.dart');
      final hasDecay = src.contains('decay') || src.contains('crack');
      expect(hasDecay, isFalse,
          reason: 'R-20: Option C (territory decay/cracking) is explicitly not chosen');
    });
  });

  group('R-22: updated copy for slide 8', () {
    // The body copy below was corrected against the authoritative purge
    // game design: the purge is irregular and unannounced (no weekly or
    // Sunday cadence), and protection paths (a free sick/away flag plus a
    // post-purge appeal) do exist, so copy claiming a weekly schedule or
    // "no appeals" is wrong and must not appear.
    test('slide 8 headline/body match the corrected copy', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('Stay above the line.'),
          reason: 'R-22: slide 8 headline must be updated');
      expect(
        src,
        contains('Without warning, a red line cuts the board. Land below it '
            'and you lose everything: zones, rank, access to the app.'),
        reason: 'R-22: slide 8 body must be updated (corrected copy)',
      );
    });

    test('body does not claim a weekly/Sunday schedule or "no appeals"', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('Every Sunday a red line cuts the board')),
          reason: 'R-22: the purge is irregular/unannounced, not weekly');
      expect(src, isNot(contains('No appeals')),
          reason: 'R-22: a post-purge appeal path exists');
    });

    test('old "THE PURGE HAS BEGUN" copy is gone', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('THE PURGE\\nHAS BEGUN.')),
          reason: 'R-22: the current build\'s headline must be replaced');
    });

    test('option-A copy ("Sunday 00:00. The map burns.") was never introduced', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('The map burns.')),
          reason: 'R-22: option A copy must not be used for slide 8');
    });
  });
}
