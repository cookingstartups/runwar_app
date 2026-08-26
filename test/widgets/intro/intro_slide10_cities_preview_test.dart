// test/widgets/intro/intro_slide10_cities_preview_test.dart
//
// Slide 10 ("Choose your ground.") -- constant linear turntable carousel.
// Spec: infra/meta/specs/runwar/intro-carousel-realism/decisions.md
//   ("Slide 10 Choose your ground", APPROVED: keep the 3D ring; ONE constant
//   linear speed with no easing drift or wobble; scale/opacity/blur tied
//   strictly to depth; sorted back-to-front for correct occlusion; ring
//   weighted to the bottom half).
// Mockup: infra/meta/specs/runwar/intro-carousel-realism/mockups/
//   slides-proposed.html, slide A proposed column (`a-pro-orbit`:
//   rotateY 0..360deg translateZ(R), 18s linear, depth-locked opacity/blur).
//
// This replaces the earlier "Land and Go" dwell-schedule suite: the dwell
// design's per-card arrival/departure easing is exactly the wobble the
// redesign removes, so its waypoint/dwell assertions are gone with it.
//
// No pumpAndSettle() anywhere here -- the ring's AnimationController repeats
// forever (`..repeat()`), so pumpAndSettle would never terminate. Every test
// uses bounded `tester.pump(Duration(...))` steps instead, per
// infra/protocols/flutter-test-patterns.md.

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
/// given Text finder -- used to assert the readout's fade schedule without
/// depending on internal state.
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

    testWidgets('tapping the front card does not throw and changes nothing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

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

  group('constant linear turntable -- no easing anywhere on the motion path', () {
    test('loop duration matches the mockup\'s 18s linear orbit', () {
      expect(kCitiesRingLoopDuration, const Duration(milliseconds: 18000),
          reason: 'the proposed mockup runs `a-pro-orbit 18s linear '
              'infinite`; the old 16.8s belonged to the retired dwell '
              'schedule');
    });

    test('angular velocity is constant across the whole revolution', () {
      const dt = 0.01;
      // Unwrapped angle deltas must be identical at every sample point of
      // the loop -- any easing/wobble would make them diverge.
      final samples = [0.0, 0.11, 0.23, 0.37, 0.49, 0.62, 0.78, 0.91];
      final deltas = samples.map((p) {
        final a0 = cityCardPose(p).angleRadians;
        final a1 = cityCardPose(p + dt).angleRadians;
        var d = a1 - a0;
        if (d < 0) d += 2 * 3.141592653589793; // wrap at the loop seam
        return d;
      }).toList();
      for (final d in deltas) {
        expect(d, closeTo(deltas.first, 1e-9),
            reason: 'ring angular speed must be one constant linear rate '
                'with zero easing drift between cards');
      }
    });

    test('no Curve/Cubic easing exists in the carousel source', () {
      final src = _read('lib/widgets/intro/intro_cities_preview.dart');
      expect(RegExp(r'Cubic\(').hasMatch(src), isFalse,
          reason: 'the turntable has no eased legs at all -- the old '
              'arrival/departure Cubics are the wobble the redesign removes');
      expect(src, isNot(contains('Curves.')),
          reason: 'no named curve may drive any part of the ring motion');
      expect(src, isNot(contains('CurvedAnimation')),
          reason: 'the controller value maps linearly to ring angle');
    });
  });

  group('depth-locked pose -- opacity/blur are monotonic functions of depth', () {
    test('opacity and blur are monotonic in depth from front to back', () {
      // Sample the front-to-back half of the revolution: depth strictly
      // decreases, so opacity must strictly decrease and blur strictly
      // increase.
      final phases = List.generate(26, (i) => i * 0.02); // 0 .. 0.5
      for (var i = 1; i < phases.length; i++) {
        final prev = cityCardPose(phases[i - 1]);
        final cur = cityCardPose(phases[i]);
        expect(cur.depth, lessThan(prev.depth));
        expect(cur.opacity, lessThan(prev.opacity),
            reason: 'opacity must be a monotonic function of depth');
        expect(cur.blurSigma, greaterThan(prev.blurSigma),
            reason: 'blur must be a monotonic function of depth');
      }
    });

    test('front card is fully opaque and unblurred; back card is faded', () {
      final front = cityCardPose(0.0);
      final back = cityCardPose(0.5);
      expect(front.depth, closeTo(1.0, 1e-9));
      expect(front.opacity, closeTo(1.0, 1e-9));
      expect(front.blurSigma, closeTo(0.0, 1e-9));
      expect(back.depth, closeTo(-1.0, 1e-9));
      expect(back.opacity, closeTo(0.28, 1e-9),
          reason: 'mockup: opacity .28 at the very back of the ring');
      expect(back.blurSigma, closeTo(2.4, 1e-9),
          reason: 'mockup: blur(2.4px) at the very back of the ring');
    });

    test('cards are sorted back-to-front by depth before painting', () {
      final src = _read('lib/widgets/intro/intro_cities_preview.dart');
      expect(src, contains('a.pose.depth.compareTo(b.pose.depth)'),
          reason: 'per-frame back-to-front sort by depth is what prevents '
              'popping at the depth-swap boundary');
    });
  });

  group('readout window -- synced to the front passage', () {
    testWidgets('each city\'s readout is at full opacity when its card is at '
        'the front', (tester) async {
      for (var i = 0; i < kCitiesCatalog.length; i++) {
        final city = kCitiesCatalog[i];
        // Card i is at the exact front when controllerValue == (1 - i/6) % 1.
        final cv = (1.0 - i / 6) % 1.0;
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
        );
        await tester.pump();
        await tester.pump(Duration(
          milliseconds: (cv * kCitiesRingLoopDuration.inMilliseconds).round(),
        ));

        // The tagline is only rendered inside the readout (the ring card
        // itself shows name + flag/country), so it uniquely targets the
        // readout's own opacity.
        final finder = find.text(city.tagline);
        final opacity = _ancestorOpacity(tester, finder);
        expect(opacity, greaterThan(0.95),
            reason: '${city.name} should be at full readout opacity while '
                'its card passes the front, got $opacity');

        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('a city\'s readout is fully faded when its card is at the back',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();
      // Half a revolution puts city 0 at the exact back of the ring.
      await tester.pump(Duration(
        milliseconds: kCitiesRingLoopDuration.inMilliseconds ~/ 2,
      ));

      final finder = find.text(kCitiesCatalog.first.tagline);
      final opacity = _ancestorOpacity(tester, finder);
      expect(opacity, lessThan(0.001),
          reason: 'the first city\'s readout must be invisible while its '
              'card is at the back of the ring, got $opacity');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('numeric scarcity readout', () {
    testWidgets('shows status and a real capacity number per city',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IntroCitiesPreview())),
      );
      await tester.pump();

      final unlocked = kCitiesCatalog.first; // Valencia, isUnlocked: true
      expect(unlocked.isUnlocked, isTrue);
      final expectedCapacity = NumberFormat.decimalPattern().format(
        unlocked.totalTarget,
      );
      expect(
        find.text('OPEN · $expectedCapacity SPOTS'),
        findsWidgets,
        reason: 'the unlocked city must show its real, non-fabricated '
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

  group('performance craft rules', () {
    test('the card drop shadow has a fixed blur radius, never animated', () {
      final src = _read('lib/widgets/intro/intro_cities_preview.dart');
      final shadowMatch =
          RegExp(r'BoxShadow\(([\s\S]*?)\)').firstMatch(src)!.group(1)!;
      expect(shadowMatch, isNot(contains('pose')),
          reason: 'BoxShadow blurRadius must be a static constant, not '
              'animated from the pose');
    });

    test('depth blur sigma is quantized so filters are not rebuilt per frame',
        () {
      final src = _read('lib/widgets/intro/intro_cities_preview.dart');
      expect(src, contains('roundToDouble'),
          reason: 'blur sigma must be quantized to coarse steps so a new '
              'ImageFilter is only created when depth has moved meaningfully');
    });
  });
}
