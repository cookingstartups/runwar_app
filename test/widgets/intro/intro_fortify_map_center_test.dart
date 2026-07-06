// test/widgets/intro/intro_fortify_map_center_test.dart
//
// Slide 2 (FORTIFY)'s visualTopTextBottom layout overlays the text/CTA panel
// over roughly the bottom half of the screen. Reusing IntroContinuity's
// shared map center (built for slides 3/4's different layout) put
// IntroZones.kS1Block1 too far south on screen, clipping it behind the text
// panel. This slide now uses its own local center (intro_fortify_map.dart's
// private `_kMapCenter`).
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
      expect(src, contains('_kMapCenter = LatLng(39.4608, -0.3756)'),
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

  group('kS1Block1 projects within the top of the screen at the new center', () {
    // Mirrors _onMapReady's own projection: cam.latLngToScreenPoint(ll).
    final camera = MapCamera(
      crs: const Epsg3857(),
      center: const LatLng(39.4608, -0.3756),
      zoom: IntroContinuity.kMapZoom,
      rotation: 0,
      nonRotatedSize: const Point<double>(_kViewportWidth, _kViewportHeight),
    );

    test('every kS1Block1 vertex renders no lower than 55% of the viewport height', () {
      for (final vertex in IntroZones.kS1Block1) {
        final p = camera.latLngToScreenPoint(vertex);
        final yFrac = p.y / _kViewportHeight;
        expect(
          yFrac,
          lessThan(0.55),
          reason:
              'vertex $vertex projected to y=${p.y} (${(yFrac * 100).toStringAsFixed(1)}% '
              'of viewport height) — must render comfortably above the text '
              'panel, not clipped behind it',
        );
      }
    });

    test('kS1Block1 vertices are not pushed all the way up against the top edge', () {
      for (final vertex in IntroZones.kS1Block1) {
        final p = camera.latLngToScreenPoint(vertex);
        final yFrac = p.y / _kViewportHeight;
        expect(yFrac, greaterThan(0.15),
            reason: 'vertex $vertex projected to y=${p.y} — the recentered '
                'block should still sit within a natural top band, not '
                'crammed against the very top of the screen');
      }
    });

    test('the full inherited kS1All set also stays within the top 55% (bonus coverage)', () {
      for (final block in IntroZones.kS1All) {
        for (final vertex in block) {
          final p = camera.latLngToScreenPoint(vertex);
          final yFrac = p.y / _kViewportHeight;
          expect(
            yFrac,
            lessThan(0.55),
            reason: 'inherited-block vertex $vertex (drawn via '
                'drawInheritedBlocks) projected to y=${p.y} '
                '(${(yFrac * 100).toStringAsFixed(1)}%) — should also clear '
                'the text panel band',
          );
        }
      }
    });
  });
}
