import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Decorative elevation-line silhouette, drawn as a background layer behind
/// the distance/duration/avg-pace triad. Purely visual texture: no axis
/// labels, no tooltip, no numeric callout, and it never fabricates data - a
/// run with fewer than two altitude samples renders nothing at all.
class ElevationSilhouettePainter extends CustomPainter {
  const ElevationSilhouettePainter({required this.samples});

  /// Chronological, real per-fix altitude readings for this session's
  /// track. Never randomized or synthesized.
  final List<double> samples;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final smoothed = _movingAverage(samples, window: 5);
    final minAlt = smoothed.reduce(math.min);
    final maxAlt = smoothed.reduce(math.max);
    final range = (maxAlt - minAlt).abs() < 1e-6 ? 1.0 : maxAlt - minAlt;

    final path = Path();
    for (var i = 0; i < smoothed.length; i++) {
      final x = size.width * i / (smoothed.length - 1);
      final y = size.height * (1 - (smoothed[i] - minAlt) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [kAccent.withValues(alpha: 0.18), kAccent.withValues(alpha: 0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  /// Light smoothing pass for visual cleanliness only - never a
  /// data-quality gate, since this feature makes no accuracy claim.
  List<double> _movingAverage(List<double> values, {required int window}) {
    if (values.length <= 2 || window <= 1) return values;
    final result = <double>[];
    for (var i = 0; i < values.length; i++) {
      final lo = math.max(0, i - window ~/ 2);
      final hi = math.min(values.length - 1, i + window ~/ 2);
      var sum = 0.0;
      for (var j = lo; j <= hi; j++) {
        sum += values[j];
      }
      result.add(sum / (hi - lo + 1));
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant ElevationSilhouettePainter oldDelegate) =>
      !identical(oldDelegate.samples, samples);
}
