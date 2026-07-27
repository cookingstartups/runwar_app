// test/widgets/intro/intro_slide10_cities_preview_test.dart
//
// Slide 10 redesign ("Land and Go" 3D carousel).
// Spec: infra/meta/specs/runwar/onboarding-remake/slide10-redesign-decision.md
// Mockup: infra/meta/specs/runwar/onboarding-remake/mockups/slide10-redesign-variants-v1.html
// (Variant B "vb"/"landB", with Variant D's numeric readout folded in).
//
// This replaces the earlier flat 2x3 CityCard grid + bottom CTA test suite
// with coverage for the new ambient, non-interactive 3D ring carousel: no
// button, all 6 catalog cities land on their own schedule, and taps are
// still fully inert.
//
// No pumpAndSettle() anywhere here -- the ring's AnimationController repeats
// forever (`..repeat()`), so pumpAndSettle would never terminate. Every test
// uses bounded `tester.pump(Duration(...))` steps instead, per
// infra/protocols/flutter-test-patterns.md §3.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:runwar_app/data/cities_catalog.dart';
import 'package:runwar_app/widgets/intro/intro_cities_preview.dart';
import 'package:runwar_app/widgets/valencia_button.dart';

String _read(String relPath) {
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

/// Locates the nearest ancestor Opacity widget's current opacity for a
/// given Text finder -- used to assert the readout's fade-in/fade-out
/// schedule without depending on internal state.
double _ancestorOpacity(WidgetTester tester, Finder textFinder) {
  final opacityFinder = find.ancestor(
    of: textFinder,
    matching: find.byType(Opacity),
  );
  final opacity = tester.widget<Opacity>(opacityFinder.first);
  return opacity.opacity;
}

void main() {
  group('slide 10 wiring -- carousel replaces the flat grid, no bottom CTA', () {
    test('intro_screen.dart wires IntroCitiesPreview for slide 10', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, contains('IntroCitiesPreview'),
          reason: 'slide 10 must render the cities-preview carousel widget');
    });

    test('_CitiesPreviewSlide no longer references ValenciaButton or _done', () {
      final src = _read('lib/screens/intro_screen.dart');
      final classBody = RegExp(
        r'class _CitiesPreviewSlide[\s\S]*?\n}\n',
      ).firstMatch(src)!.group(0)!;
      expect(classBody, isNot(contains('ValenciaButton')),
          reason: 'the bottom CTA button must be removed entirely, '
              'not replaced with another CTA');
      expect(classBody, isNot(contains('_done')),
          reason: 'slide 10 no longer owns a button wired to _done -- '
              'advancing past it is the deck\'s existing swipe gesture');
    });

    test('intro_screen.dart no longer imports ValenciaButton', () {
      final src = _read('lib/screens/intro_screen.dart');
      expect(src, isNot(contains("import '../widgets/valencia_button.dart'")),
          reason: 'the import becomes dead once the CTA is removed from '
              'this file');
    });
  });

  group('carousel renders all 6 catalog cities, non-interactively', () {
    testWidgets('no button of any kind exists in the rendered tree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();

      expect(find.byType(ValenciaButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.text("I'M IN · CREATE MY ACCOUNT"), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('is wrapped in IgnorePointer and has no GestureDetector',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();

      expect(find.byType(IgnorePointer), findsWidgets,
          reason: 'the carousel must stay non-interactive, IgnorePointer '
              'or equivalent');
      expect(find.byType(GestureDetector), findsNothing,
          reason: 'no card in the ring should attach a tap handler at all '
              '-- this is a showcase, not a picker');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('tapping a landed card does not throw and changes nothing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();
      // Let the first city land and settle into its dwell window.
      await tester.pump(const Duration(milliseconds: 1900));

      final before = find.text(kCitiesCatalog.first.name).evaluate().length;
      await tester.tapAt(tester.getCenter(find.byType(IntroCitiesPreview)));
      await tester.pump();
      final after = find.text(kCitiesCatalog.first.name).evaluate().length;

      expect(after, equals(before),
          reason: 'a tap on the non-interactive carousel must not change '
              'what is rendered');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('all 6 catalog city names are present in the ring',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();

      for (final city in kCitiesCatalog) {
        expect(find.text(city.name), findsWidgets,
            reason: '${city.name} must be rendered somewhere in the ring '
                'or its readout');
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('landing schedule -- each city lands and dwells on its own slot', () {
    // One full loop is 16.8s across 6 cities -> a 2.8s slot per card
    // (matching the mockup's -2.8s per-card animation-delay stagger, i.e.
    // card i's own local phase is (controllerValue + i/6) mod 1 -- see
    // cityCardPhase). Dwell is the [0.06, 0.1667] window of that local
    // phase. Solving for the controller value that puts card i at its own
    // dwell midpoint gives the exact real time each city lands at, rather
    // than assuming cards land in roster order (they don't -- the shared
    // per-card phase offset makes the landing order 0, 5, 4, 3, 2, 1).
    const dwellCenterPhase = (0.06 + 0.1667) / 2;

    Duration dwellMidpointFor(int index) {
      final cv = (dwellCenterPhase - index / 6) % 1.0;
      return Duration(
        milliseconds: (cv * kCitiesRingLoopDuration.inMilliseconds).round(),
      );
    }

    // The tagline is only rendered inside the readout (the ring card itself
    // only shows the city's name + flag/country), so finding it uniquely
    // targets the readout's own opacity, not the ring card's.
    testWidgets('each city\'s readout reaches full opacity during its own dwell',
        (tester) async {
      for (var i = 0; i < kCitiesCatalog.length; i++) {
        final city = kCitiesCatalog[i];
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
        );
        await tester.pump();
        await tester.pump(dwellMidpointFor(i));

        final finder = find.text(city.tagline);
        final opacity = _ancestorOpacity(tester, finder);
        expect(opacity, greaterThan(0.85),
            reason: '${city.name} should be at (or near) full readout '
                'opacity at its own dwell midpoint, got $opacity');

        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('a city\'s readout is faded out well outside its own slot',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();
      // City 0's own dwell window ends at ~2.8s (phase 0.1667 of 16.8s);
      // 6s in is well clear of it without landing inside any other city's
      // narrow dwell window either.
      await tester.pump(const Duration(milliseconds: 6000));

      final finder = find.text(kCitiesCatalog.first.tagline);
      final opacity = _ancestorOpacity(tester, finder);
      expect(opacity, lessThan(0.05),
          reason: 'the first city\'s readout must have faded out well '
              'outside its own dwell window, got $opacity');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('numeric scarcity readout (folded in from Variant D)', () {
    testWidgets('shows status and a real capacity number per city',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1900));

      final unlocked = kCitiesCatalog.first; // Valencia, isUnlocked: true
      expect(unlocked.isUnlocked, isTrue);
      final expectedCapacity = NumberFormat.decimalPattern().format(
        unlocked.totalTarget,
      );
      expect(
        find.text('OPEN · $expectedCapacity SPOTS'),
        findsWidgets,
        reason: 'the landed unlocked city must show its real, non-fabricated '
              'totalTarget capacity from kCitiesCatalog',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('data note -- no live joined-count fabrication', () {
    test('city.joinedCount is not read to compute the numeric readout', () {
      final src = _read('lib/widgets/intro/intro_cities_preview.dart');
      // kCitiesCatalog.joinedCount always defaults to 0 in the static
      // catalog (live counts require an async CitiesRepository fetch, out
      // of scope per the decision doc). The comment header legitimately
      // documents this gap using the word "joinedCount" -- what must never
      // appear is an actual field access on a city instance.
      expect(src, isNot(contains('city.joinedCount')),
          reason: 'the readout must use the real static totalTarget field '
              'instead of fabricating or showing an always-zero occupancy '
              'count derived from city.joinedCount');
      expect(src, contains('totalTarget'),
          reason: 'the readout must use the real static capacity field');
    });
  });

  group('craft fixes required by the decision doc', () {
    test('the return path is driven by one continuous curve, not per-waypoint', () {
      final src = _read('lib/widgets/intro/intro_cities_preview.dart');
      expect(src, contains('_kReturnCurve'),
          reason: 'craft fix 1: a single named curve must drive the whole '
              'off-center return path');
      // The waypoint tables (raw positions) must exist independently of any
      // additional per-segment Curve/Cubic declarations beyond arrival and
      // departure -- i.e. exactly two Cubic curves (arrival, departure),
      // not one per intermediate keyframe.
      final cubicCount = RegExp(r'Cubic\(').allMatches(src).length;
      expect(cubicCount, equals(2),
          reason: 'craft fix 1: only the arrival and departure legs may use '
              'a bespoke eased Cubic curve -- the return path must not be '
              're-eased at every intermediate waypoint');
    });

    test('the landed-card glow animates opacity of a static blur, not blur radius', () {
      final src = _read('lib/widgets/intro/intro_cities_preview.dart');
      expect(src, contains('glowOpacity'),
          reason: 'craft fix 2: the glow layer\'s opacity must be the '
              'animated value');
      // BoxShadow's blurRadius must be a fixed literal, never itself driven
      // by the animation controller/pose.
      final shadowMatch =
          RegExp(r'BoxShadow\(([\s\S]*?)\)').firstMatch(src)!.group(1)!;
      expect(shadowMatch, isNot(contains('pose')),
          reason: 'craft fix 2: BoxShadow blurRadius must be a static '
              'constant, not animated from the pose');
    });
  });
}
