// test/widgets/intro/intro_capture_map_center_test.dart
//
// Slide 3 (YOUR TURF)'s visualTopTextBottom layout overlays the text/CTA
// panel over roughly the bottom half of the screen. IntroCaptureMap's
// default center - the shared IntroContinuity.kMapCenter, also used by
// slide 4 - put kS1Block1 too far south on screen, clipping it behind the
// text panel. Slide 3's on-screen instance now passes intro_screen.dart's
// private `_kSlide3CaptureMapCenter` override, shifted south so the block
// reads in the top half instead.
//
// No FlutterMap widget pump here - pumping a real FlutterMap in this test
// environment risks asset-tile load exceptions/pending timers unrelated to
// the geometry being verified (see flutter-test-patterns.md §1/§2/"When NOT
// to use testWidgets for map tests"). Instead this test builds a real
// flutter_map MapCamera directly, with the same center/zoom the widget uses,
// and calls the exact same `latLngToScreenPoint` projection method the
// widget's own onReady handler calls, at a realistic phone viewport size.

import 'dart:io';
import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runwar_app/widgets/intro/intro_helpers.dart';

String _captureMapSourceText() {
  const relPath = 'lib/widgets/intro/intro_capture_map.dart';
  final file = File(relPath);
  if (file.existsSync()) return file.readAsStringSync();
  return File('/home/algif/repos/venture/runwar/runwar_app/$relPath')
      .readAsStringSync();
}

String _introScreenSourceText() {
  const relPath = 'lib/screens/intro_screen.dart';
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

// Mirrors intro_screen.dart's private `_kSlide3CaptureMapCenter`.
const _kSlide3CaptureMapCenter = LatLng(39.4583, -0.3756);

void main() {
  group('IntroCaptureMap accepts an optional center override', () {
    test('constructor declares an optional center param', () {
      final src = _captureMapSourceText();
      expect(src, contains('this.center'),
          reason: 'IntroCaptureMap must accept an optional center override '
              'so slide 3 can shift its on-screen instance without moving '
              'the shared IntroContinuity.kMapCenter other callers rely on');
    });

    test('falls back to the shared IntroContinuity.kMapCenter when unset', () {
      final src = _captureMapSourceText();
      expect(src, contains('widget.center ?? IntroContinuity.kMapCenter'),
          reason: 'other callers (e.g. the pre-warm Offstage instance) must '
              'keep rendering at the shared default center');
    });
  });

  group('intro_screen.dart wires the shifted center to slide 3 only', () {
    test('declares the shifted _kSlide3CaptureMapCenter constant', () {
      final src = _introScreenSourceText();
      expect(
          src,
          contains(
              '_kSlide3CaptureMapCenter = LatLng(39.4583, -0.3756)'));
    });

    test('_buildAnimWidget threads captureMapCenter through to IntroCaptureMap', () {
      final src = _introScreenSourceText();
      expect(src, contains('IntroCaptureMap(accent: accent, center: captureMapCenter)'));
    });

    test('the on-screen (_SplitBleedSlide) call site gates the override to hexCapture', () {
      final src = _introScreenSourceText();
      expect(
          src,
          contains(
              'slide.anim == _Anim.hexCapture ? _kSlide3CaptureMapCenter : null'));
    });
  });

  group('kS1Block1 projects within the top half at the slide-3 shifted center', () {
    // Mirrors _updatePoints' own projection: cam.latLngToScreenPoint(ll).
    final camera = MapCamera(
      crs: const Epsg3857(),
      center: _kSlide3CaptureMapCenter,
      zoom: IntroContinuity.kMapZoom,
      rotation: 0,
      nonRotatedSize: const Point<double>(_kViewportWidth, _kViewportHeight),
    );

    test('kS1Block1 centroid projects at roughly 22%-28% of the viewport height', () {
      double sumY = 0;
      for (final vertex in IntroZones.kS1Block1) {
        sumY += camera.latLngToScreenPoint(vertex).y;
      }
      final centroidYFrac =
          (sumY / IntroZones.kS1Block1.length) / _kViewportHeight;
      expect(
        centroidYFrac,
        allOf(greaterThan(0.22), lessThan(0.28)),
        reason: 'kS1Block1 centroid must land in the top-half band, clear '
            'of the bottom text panel on slide 3\'s visualTopTextBottom '
            'layout - got ${(centroidYFrac * 100).toStringAsFixed(1)}%',
      );
    });

    test('every kS1Block1 vertex renders comfortably above the mid-screen line', () {
      for (final vertex in IntroZones.kS1Block1) {
        final p = camera.latLngToScreenPoint(vertex);
        final yFrac = p.y / _kViewportHeight;
        expect(
          yFrac,
          lessThan(0.5),
          reason:
              'vertex $vertex projected to y=${p.y} (${(yFrac * 100).toStringAsFixed(1)}% '
              'of viewport height) - must render in the top half, not '
              'clipped behind the bottom text panel',
        );
      }
    });
  });
}
