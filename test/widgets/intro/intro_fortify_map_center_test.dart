// test/widgets/intro/intro_fortify_map_center_test.dart
//
// Slide 2 (FORTIFY)'s textTopVisualBottom layout overlays the text/CTA panel
// over roughly the top half of the screen, so the animation should read in
// the bottom half. Reusing IntroContinuity's shared map center (built for
// slides 3/4's different layout) put IntroZones.kS1Block1 too far north on
// screen, clipping it behind the text panel. This slide now uses its own
// local center (intro_fortify_map.dart's private `_kMapCenter`), recentered
// so the block reads in the bottom half instead.
//
// No FlutterMap widget pump here - pumping a real FlutterMap in this test
// environment risks asset-tile load exceptions/pending timers unrelated to
// the geometry being verified (see flutter-test-patterns.md §1/§2/"When NOT
// to use testWidgets for map tests"). Instead this test builds a real
// flutter_map MapCamera directly, with the same center/zoom the widget uses,
// and calls the exact same `latLngToScreenPoint` projection method the
// widget's own onMapReady handler calls, at a realistic phone viewport size.

import 'dart:io';
import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runwar_app/widgets/intro/intro_helpers.dart';

String _sourceText() {
  const relPath = 'lib/widgets/intro/intro_fortify_map.dart';
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

// Realistic phone viewport (logical px) - the visual fills the whole screen
// in production (StackFit.expand in _SplitBleedSlide), so this matches a
// typical device height rather than just "the top half".
const double _kViewportWidth = 412;
const double _kViewportHeight = 915;

void main() {
  group('slide 2 (FORTIFY) declares its own independent map center', () {
    test('_kMapCenter constant is declared with the derived recentered value', () {
      final src = _sourceText();
      expect(src, contains('_kMapCenter = LatLng(39.4659, -0.3756)'),
          reason: 'the recentered constant must be declared locally in '
              'intro_fortify_map.dart, not folded into the shared '
              'IntroContinuity.kMapCenter used by other slides');
    });

    test('buildIntroMap is called with the local center, not the shared one', () {
      final src = _sourceText();
      expect(src, contains('center: _kMapCenter'));
      expect(src, isNot(contains('center: IntroContinuity.kMapCenter')));
    });

    test('zoom is unchanged — still the shared IntroContinuity.kMapZoom', () {
      final src = _sourceText();
      expect(src, contains('zoom: IntroContinuity.kMapZoom'));
    });
  });

  group('kS1Block1 projects within the bottom half of the screen at the new center', () {
    // Mirrors _onMapReady's own projection: cam.latLngToScreenPoint(ll).
    final camera = MapCamera(
      crs: const Epsg3857(),
      center: const LatLng(39.4659, -0.3756),
      zoom: IntroContinuity.kMapZoom,
      rotation: 0,
      nonRotatedSize: const Point<double>(_kViewportWidth, _kViewportHeight),
    );

    test('kS1Block1 centroid projects at roughly 72%-78% of the viewport height', () {
      double sumY = 0;
      for (final vertex in IntroZones.kS1Block1) {
        sumY += camera.latLngToScreenPoint(vertex).y;
      }
      final centroidYFrac =
          (sumY / IntroZones.kS1Block1.length) / _kViewportHeight;
      expect(
        centroidYFrac,
        allOf(greaterThan(0.72), lessThan(0.78)),
        reason: 'kS1Block1 centroid must land in the bottom-half band, clear '
            'of the top text panel on this slide\'s textTopVisualBottom '
            'layout - got ${(centroidYFrac * 100).toStringAsFixed(1)}%',
      );
    });

    test('every kS1Block1 vertex renders comfortably below the mid-screen line', () {
      for (final vertex in IntroZones.kS1Block1) {
        final p = camera.latLngToScreenPoint(vertex);
        final yFrac = p.y / _kViewportHeight;
        expect(
          yFrac,
          greaterThan(0.5),
          reason:
              'vertex $vertex projected to y=${p.y} (${(yFrac * 100).toStringAsFixed(1)}% '
              'of viewport height) — must render comfortably below the text '
              'panel, not clipped behind it',
        );
      }
    });

    test('kS1Block1 vertices are not pushed all the way down against the bottom edge', () {
      for (final vertex in IntroZones.kS1Block1) {
        final p = camera.latLngToScreenPoint(vertex);
        final yFrac = p.y / _kViewportHeight;
        expect(yFrac, lessThan(0.9),
            reason: 'vertex $vertex projected to y=${p.y} — the recentered '
                'block should still sit within a natural bottom band, not '
                'crammed against the very bottom of the screen');
      }
    });

    test('the full inherited kS1All set also stays within the bottom band (bonus coverage)', () {
      for (final block in IntroZones.kS1All) {
        for (final vertex in block) {
          final p = camera.latLngToScreenPoint(vertex);
          final yFrac = p.y / _kViewportHeight;
          expect(
            yFrac,
            allOf(greaterThan(0.5), lessThan(0.9)),
            reason: 'inherited-block vertex $vertex (drawn via '
                'drawInheritedBlocks) projected to y=${p.y} '
                '(${(yFrac * 100).toStringAsFixed(1)}%) — should also clear '
                'the text panel band and stay on screen',
          );
        }
      }
    });
  });
}
