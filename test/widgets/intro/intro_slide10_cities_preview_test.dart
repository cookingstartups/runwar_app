// test/widgets/intro/intro_slide10_cities_preview_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Spec: infra/meta/specs/runwar/onboarding-remake/requirements.md (R-28..R-31)
// Design: _CenteredCloseSlide replaced by a CityCard-based preview
// (IntroCitiesPreview, reusing kCitiesCatalog), non-interactive except the
// final CTA which calls markShowcaseSeen via the existing _done().
//
// No FlutterMap on this slide (per design.md Test Plan Skeleton). CityCard
// starts its progress-bar animation from a 300ms Future.delayed, which
// pumpAndSettle() alone cannot drain (a bare Future.delayed does not itself
// schedule a frame, so pumpAndSettle can return before it fires) — so each
// render assertion first pumps past the 300ms delay explicitly, then
// pumpAndSettle()s to finish the resulting AnimationController, avoiding a
// pending-timer failure at teardown.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runwar_app/widgets/intro/intro_cities_preview.dart';

String _read(String relPath) {
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

void main() {
  group('R-28: _CenteredCloseSlide is retired, real preview UI replaces it', () {
    test('intro_screen.dart no longer references _CenteredCloseSlide', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains('_CenteredCloseSlide')),
          reason: 'R-28: the old centered-text close slide must be retired');
    });

    test('intro_screen.dart wires IntroCitiesPreview for slide 10', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('IntroCitiesPreview'),
          reason: 'R-28: slide 10 must render the new cities-preview widget');
    });
  });

  group('R-28: preview grid renders non-interactively', () {
    // GIVEN  slide 10's city-card grid renders from kCitiesCatalog
    // WHEN   IntroCitiesPreview is pumped
    // THEN   exactly 1 OPEN card and 5 SOON cards are visible, and the grid
    //        is wrapped so taps produce no selection change
    testWidgets('renders exactly 1 OPEN card and 5 SOON cards', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('OPEN'), findsOneWidget,
          reason: 'R-29: exactly 1 card (Valencia) must show OPEN');
      expect(find.text('SOON'), findsNWidgets(5),
          reason: 'R-29: exactly 5 cards must show SOON');
    });

    testWidgets('grid is wrapped in IgnorePointer (non-interactive)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.byType(IgnorePointer), findsWidgets,
          reason: 'R-28: the preview grid must be non-interactive '
              '(IgnorePointer or equivalent)');
    });
  });

  group('R-29: every locked card shows an invite-to-unlock affordance', () {
    testWidgets('exactly 5 "Invite friends to unlock" rows are shown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Invite friends to unlock'), findsNWidgets(5),
          reason: 'R-29: every SOON card must show the invite-to-unlock row');
    });
  });

  group('R-29: CityCard gains an opt-in inviteHint parameter', () {
    test('CityCard declares an inviteHint constructor parameter, default false', () {
      final src = _read('lib/widgets/city_card.dart');
      expect(src, contains('inviteHint'),
          reason: 'R-29: CityCard must gain a new opt-in inviteHint parameter');
      expect(src, contains('this.inviteHint = false'),
          reason: 'R-29: inviteHint must default to false so '
              'CitiesSelectionScreen\'s existing call site is unaffected');
    });
  });

  group('R-30: preview label and final CTA', () {
    test('IntroCitiesPreview shows the preview label text', () {
      final src = _read('lib/widgets/intro/intro_cities_preview.dart');
      expect(
        src,
        contains('ONBOARDING PREVIEW'),
        reason: 'R-30: a distinct preview label must be visible above the grid',
      );
    });

    test('intro_screen.dart wires the final CTA to _done (markShowcaseSeen)', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains("I'M IN"),
          reason: 'R-30: the final primary CTA must read "I\'M IN · CREATE MY ACCOUNT"');
      final ctaWiredToDone = RegExp(
        r"I'M IN[\s\S]{0,120}?onPressed:\s*_done",
      ).hasMatch(src);
      expect(ctaWiredToDone, isTrue,
          reason: 'R-30: tapping the CTA must invoke the existing _done() '
              '(markShowcaseSeen) completion flow');
    });
  });

  group('R-31: updated copy for slide 10', () {
    test('slide 10 headline/body match the new copy', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('Choose your ground.'),
          reason: 'R-31: slide 10 headline must be updated');
      expect(
        src,
        contains('Valencia is live. Five more cities sit behind the wall.'),
        reason: 'R-31: slide 10 body must be updated',
      );
    });
  });
}
