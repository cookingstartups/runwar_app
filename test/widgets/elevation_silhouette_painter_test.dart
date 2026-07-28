// test/widgets/elevation_silhouette_painter_test.dart
//
// RED phase: lib/widgets/elevation_silhouette_painter.dart does not exist
// yet. ElevationSilhouettePainter is purely decorative: no axis labels, no
// tooltip, no numeric callout, and it must never fabricate data - it draws
// nothing when fewer than two samples exist, and guards against a
// division-by-zero-shaped path for a perfectly flat route.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/widgets/elevation_silhouette_painter.dart';

void main() {
  group('ElevationSilhouettePainter: guards', () {
    test('paint() does not throw when fewer than two samples are provided', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const painter = ElevationSilhouettePainter(samples: <double>[]);

      expect(() => painter.paint(canvas, const Size(200, 60)), returnsNormally);

      const singleSamplePainter = ElevationSilhouettePainter(samples: <double>[12.0]);
      expect(() => singleSamplePainter.paint(canvas, const Size(200, 60)),
          returnsNormally,
          reason: 'a single sample has no line to draw and must not throw');
    });

    test('paint() does not throw for a perfectly flat route (zero altitude range)', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const painter = ElevationSilhouettePainter(samples: <double>[10.0, 10.0, 10.0, 10.0]);

      expect(() => painter.paint(canvas, const Size(200, 60)), returnsNormally,
          reason: 'a flat route must not divide by a zero altitude range');
    });

    test('paint() does not throw for a normal route with rise and fall', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const painter =
          ElevationSilhouettePainter(samples: <double>[10, 15, 22, 18, 12, 9]);

      expect(() => painter.paint(canvas, const Size(200, 60)), returnsNormally);
    });
  });

  group('ElevationSilhouettePainter: shouldRepaint', () {
    test('shouldRepaint is false when the same samples list instance is reused', () {
      final samples = <double>[10, 12, 14];
      final a = ElevationSilhouettePainter(samples: samples);
      final b = ElevationSilhouettePainter(samples: samples);

      expect(a.shouldRepaint(b), isFalse);
    });

    test('shouldRepaint is true for a different samples list instance', () {
      const a = ElevationSilhouettePainter(samples: <double>[10, 12, 14]);
      const b = ElevationSilhouettePainter(samples: <double>[10, 12, 15]);

      expect(a.shouldRepaint(b), isTrue);
    });
  });

  group('ElevationSilhouettePainter as a rendered CustomPaint', () {
    testWidgets('renders as a CustomPaint without throwing, with no interactive gesture attached',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: CustomPaint(
              painter: const ElevationSilhouettePainter(
                samples: <double>[10, 15, 22, 18, 12, 9],
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(GestureDetector), findsNothing,
          reason: 'the silhouette must not be an interactive widget');
      expect(tester.takeException(), isNull);
    });
  });
}
