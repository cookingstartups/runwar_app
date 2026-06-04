import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

// ---------------------------------------------------------------------------
// PulseRingsPainter — slide 1 "YOUR CITY. YOUR RULES."
// Simulates a GPS location ping: filled dot at center + cascading rings
// expanding outward and fading, like the blue dot acquiring your position.
// ---------------------------------------------------------------------------
class PulseRingsPainter extends CustomPainter {
  const PulseRingsPainter({required this.t, required this.color});
  final double t; // 0..1 looping
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.max(size.width, size.height) * 0.52;

    // Center GPS dot
    canvas.drawCircle(
      center,
      6,
      Paint()..color = color.withValues(alpha: 0.95),
    );

    // Accuracy halo around center dot
    canvas.drawCircle(
      center,
      14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = color.withValues(alpha: 0.3),
    );

    // 4 expanding ping rings, staggered by 0.25 phase
    const rings = 4;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (int i = 0; i < rings; i++) {
      final phase = (t + i * 0.25) % 1.0;
      final r = 14 + (maxR - 14) * phase;
      final alpha = (1.0 - phase) * 0.55;
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, r, paint);
    }

    // Small accuracy circle (inner, faint fill)
    canvas.drawCircle(
      center,
      24,
      Paint()..color = color.withValues(alpha: 0.04),
    );
  }

  @override
  bool shouldRepaint(PulseRingsPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// HexLassoPainter — slide 2 "LASSO A ZONE. IT'S YOURS."
// Simulates a runner drawing a GPS polygon around a city block:
// - Background street grid (faint horizontal + vertical lines)
// - Runner dot traces a closed irregular quadrilateral (city block perimeter)
// - Fading dot trail follows the runner
// - Completed polygon: dashed outline appears, then fill fades in
// ---------------------------------------------------------------------------
class HexLassoPainter extends CustomPainter {
  const HexLassoPainter({required this.t, required this.accentColor});
  final double t; // 0..1 looping
  final Color accentColor;

  // Irregular quadrilateral waypoints (city block, offset for GPS feel)
  // Computed relative to canvas size at paint time
  static List<Offset> _waypoints(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    return [
      Offset(cx - 70, cy - 60),  // top-left with GPS jitter
      Offset(cx + 65, cy - 68),  // top-right
      Offset(cx + 72, cy + 55),  // bottom-right
      Offset(cx - 62, cy + 58),  // bottom-left
    ];
  }

  // Interpolate position along closed polygon path given fraction 0..1
  static Offset _posOnPath(List<Offset> pts, double fraction) {
    final n = pts.length;
    final totalLen = () {
      double len = 0;
      for (int i = 0; i < n; i++) {
        len += (pts[(i + 1) % n] - pts[i]).distance;
      }
      return len;
    }();
    final target = fraction * totalLen;
    double accumulated = 0;
    for (int i = 0; i < n; i++) {
      final segLen = (pts[(i + 1) % n] - pts[i]).distance;
      if (accumulated + segLen >= target) {
        final segFraction = (target - accumulated) / segLen;
        return Offset.lerp(pts[i], pts[(i + 1) % n], segFraction)!;
      }
      accumulated += segLen;
    }
    return pts[0];
  }

  @override
  void paint(Canvas canvas, Size size) {
    // --- Street grid background ---
    final gridPaint = Paint()
      ..color = kBorder.withValues(alpha: 0.20)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final pts = _waypoints(size);

    // Build full closed polygon path
    final fullPath = Path();
    fullPath.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      fullPath.lineTo(pts[i].dx, pts[i].dy);
    }
    fullPath.close();

    if (t < 0.6) {
      // Phase 0→0.6: runner dot traces the polygon perimeter
      final fraction = t / 0.6;

      // Draw partial path (runner's trail as drawn line)
      final metrics = fullPath.computeMetrics().first;
      final drawnPath =
          metrics.extractPath(0, metrics.length * fraction);
      canvas.drawPath(
        drawnPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = accentColor.withValues(alpha: 0.5),
      );

      // Trailing dots (8 positions, decreasing opacity)
      const trailCount = 8;
      for (int j = trailCount; j >= 0; j--) {
        final trailFraction =
            (fraction - j * 0.015).clamp(0.0, 1.0);
        final trailPos = _posOnPath(pts, trailFraction);
        final alpha = j == 0 ? 1.0 : ((1.0 - j / trailCount) * 0.45);
        final dotR = j == 0 ? 4.0 : (2.5 * (1.0 - j / trailCount)).clamp(0.8, 2.5);
        canvas.drawCircle(
          trailPos,
          dotR,
          Paint()..color = accentColor.withValues(alpha: alpha),
        );
      }
    } else if (t < 0.8) {
      // Phase 0.6→0.8: completed polygon outline appears as dashed stroke
      final dashFraction = (t - 0.6) / 0.2;
      final metrics = fullPath.computeMetrics().first;
      // Draw dashed by alternating extracted segments
      final totalLen = metrics.length;
      const dashLen = 8.0;
      const gapLen = 5.0;
      double pos = 0;
      bool drawing = true;
      final dashPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = accentColor.withValues(alpha: 0.85);
      final visibleLen = totalLen * dashFraction;
      while (pos < visibleLen) {
        final segLen = drawing ? dashLen : gapLen;
        final end = (pos + segLen).clamp(0.0, visibleLen);
        if (drawing) {
          canvas.drawPath(metrics.extractPath(pos, end), dashPaint);
        }
        pos += segLen;
        drawing = !drawing;
      }
    } else {
      // Phase 0.8→1.0: fill fades in + solid outline
      final fillFraction = (t - 0.8) / 0.2;

      // Solid outline
      canvas.drawPath(
        fullPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = accentColor.withValues(alpha: 0.85),
      );

      // Fill
      canvas.drawPath(
        fullPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = kSea.withValues(alpha: fillFraction * 0.35),
      );

      // Ownership label dot at center
      final cx = size.width / 2;
      final cy = size.height / 2;
      canvas.drawCircle(
        Offset(cx, cy),
        3,
        Paint()..color = accentColor.withValues(alpha: fillFraction * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(HexLassoPainter old) =>
      old.t != t || old.accentColor != accentColor;
}

// ---------------------------------------------------------------------------
// RivalsPainter — slide 3 "RIVALS ARE RUNNING NOW."
// Simulates live runners on a city street map:
// - Street-like grid overlay (thin, faint)
// - 1 owned zone polygon (kSea fill)
// - 3 runner dots moving along L-shaped/zigzag street paths
// - Each runner leaves a polyline trail
// ---------------------------------------------------------------------------
class RivalsPainter extends CustomPainter {
  const RivalsPainter({required this.t});
  final double t; // 0..1 looping

  // L-shaped street waypoints for each runner, relative to canvas size
  static List<List<Offset>> _runnerPaths(Size size) {
    final w = size.width;
    final h = size.height;
    return [
      // Runner 1 (orange): street block on left side, L-shape
      [
        Offset(w * 0.15, h * 0.20),
        Offset(w * 0.15, h * 0.55),
        Offset(w * 0.48, h * 0.55),
        Offset(w * 0.48, h * 0.30),
      ],
      // Runner 2 (gold): zigzag top-right area
      [
        Offset(w * 0.55, h * 0.15),
        Offset(w * 0.82, h * 0.15),
        Offset(w * 0.82, h * 0.45),
        Offset(w * 0.60, h * 0.45),
        Offset(w * 0.60, h * 0.70),
      ],
      // Runner 3 (sea): bottom-right street segment
      [
        Offset(w * 0.72, h * 0.62),
        Offset(w * 0.40, h * 0.62),
        Offset(w * 0.40, h * 0.82),
        Offset(w * 0.72, h * 0.82),
      ],
    ];
  }

  // Interpolate position along open polyline given fraction 0..1
  static Offset _posOnPolyline(List<Offset> pts, double fraction) {
    double totalLen = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      totalLen += (pts[i + 1] - pts[i]).distance;
    }
    final target = fraction * totalLen;
    double accumulated = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final segLen = (pts[i + 1] - pts[i]).distance;
      if (accumulated + segLen >= target) {
        final segFraction = (target - accumulated) / segLen;
        return Offset.lerp(pts[i], pts[i + 1], segFraction)!;
      }
      accumulated += segLen;
    }
    return pts.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // --- Street grid overlay (city blocks) ---
    final streetPaint = Paint()
      ..color = kBorder.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    const gridStep = 25.0;
    for (double x = 0; x < w; x += gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), streetPaint);
    }
    for (double y = 0; y < h; y += gridStep) {
      canvas.drawLine(Offset(0, y), Offset(w, y), streetPaint);
    }

    // --- Owned zone polygon at center (kSea, represents captured territory) ---
    final cx = w / 2;
    final cy = h / 2;
    final zonePath = Path()
      ..moveTo(cx - 38, cy - 30)
      ..lineTo(cx + 40, cy - 34)
      ..lineTo(cx + 36, cy + 28)
      ..lineTo(cx - 42, cy + 32)
      ..close();
    canvas.drawPath(
      zonePath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = kSea.withValues(alpha: 0.20),
    );
    canvas.drawPath(
      zonePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = kSea.withValues(alpha: 0.45),
    );

    // --- Runner dots ---
    final runnerColors = [kAccent, kAccent2, kSea];
    final phases = [0.0, 0.30, 0.60]; // stagger start positions
    final paths = _runnerPaths(size);
    const trailCount = 12;

    for (int r = 0; r < 3; r++) {
      final color = runnerColors[r];
      final fraction = (t + phases[r]) % 1.0;
      final pts = paths[r];

      // Draw trail (last 12 positions)
      for (int j = trailCount; j >= 0; j--) {
        final trailFraction =
            (fraction - j * 0.012).clamp(0.0, 1.0);
        final pos = _posOnPolyline(pts, trailFraction);
        final alpha = j == 0 ? 0.95 : ((1.0 - j / trailCount) * 0.55);
        final dotR = j == 0 ? 4.5 : (3.0 * (1.0 - j / trailCount)).clamp(0.5, 3.0);
        canvas.drawCircle(
          pos,
          dotR,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(RivalsPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// DropBeamsPainter — slide 4 "FIRST HERE WINS."
// Simulates a GPS drop pin with runners converging toward it:
// - Street grid background
// - Animated drop-pin marker at center (circle + triangle, gold pulsing)
// - 3 beams at 120° apart (signal effect) — outer rotation via Transform.rotate
// - Outer pulsing ring around pin
// - 2 runner dots moving along L-shaped paths toward center, looping
// Note: the entire CustomPaint is wrapped in Transform.rotate by intro_screen.dart
//       so the beams naturally rotate without additional rotation logic here.
// ---------------------------------------------------------------------------
class DropBeamsPainter extends CustomPainter {
  const DropBeamsPainter({required this.intensity});
  final double intensity; // 0..1 (= loop.value)

  // Runner waypoints approaching the center pin along L-shaped streets
  // intensity 0..1 drives progress; runners loop back to start when complete
  static List<List<Offset>> _runnerPaths(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    return [
      // Runner 1: from top-left corner toward pin via L
      [
        Offset(w * 0.10, h * 0.12),
        Offset(w * 0.10, cy),
        Offset(cx, cy),
      ],
      // Runner 2: from bottom-right corner toward pin via L
      [
        Offset(w * 0.88, h * 0.86),
        Offset(w * 0.88, cy),
        Offset(cx, cy),
      ],
    ];
  }

  static Offset _posOnPolyline(List<Offset> pts, double fraction) {
    double totalLen = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      totalLen += (pts[i + 1] - pts[i]).distance;
    }
    final target = fraction.clamp(0.0, 1.0) * totalLen;
    double accumulated = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final segLen = (pts[i + 1] - pts[i]).distance;
      if (accumulated + segLen >= target) {
        final segFraction = (target - accumulated) / segLen;
        return Offset.lerp(pts[i], pts[i + 1], segFraction)!;
      }
      accumulated += segLen;
    }
    return pts.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // --- Street grid ---
    final gridPaint = Paint()
      ..color = kBorder.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    const step = 25.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // --- 3 signal beams at 120° apart (rotation handled by Transform.rotate) ---
    const innerR = 20.0;
    const outerR = 60.0;
    final beamPaint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 3; i++) {
      final angle = (2 * math.pi * i) / 3;
      final beamAlpha = (0.25 + 0.5 * intensity) *
          (i == 0 ? 1.0 : (i == 1 ? 0.75 : 0.5));
      beamPaint.color = kAccent2.withValues(alpha: beamAlpha);
      canvas.drawLine(
        Offset(center.dx + math.cos(angle) * innerR,
            center.dy + math.sin(angle) * innerR),
        Offset(center.dx + math.cos(angle) * outerR,
            center.dy + math.sin(angle) * outerR),
        beamPaint,
      );
    }

    // --- Outer pulsing ring (kAccent2, r=24→36) ---
    final outerRingR = 24.0 + 12.0 * intensity;
    canvas.drawCircle(
      center,
      outerRingR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = kAccent2.withValues(alpha: (1.0 - intensity) * 0.55),
    );

    // --- Runner dots converging on pin ---
    // Each runner uses (intensity * 1.0) as progress; at 1.0 they're at the pin
    // and then restart from the start
    final runnerColors = [kAccent, kFgMuted];
    final phases = [0.0, 0.5];
    final runPaths = _runnerPaths(size);

    for (int r = 0; r < 2; r++) {
      final fraction = (intensity + phases[r]) % 1.0;
      final pos = _posOnPolyline(runPaths[r], fraction);
      canvas.drawCircle(
        pos,
        3.5,
        Paint()..color = runnerColors[r].withValues(alpha: 0.85),
      );
      // Small trail dot
      final trailFraction = (fraction - 0.04).clamp(0.0, 1.0);
      final trailPos = _posOnPolyline(runPaths[r], trailFraction);
      canvas.drawCircle(
        trailPos,
        2.0,
        Paint()..color = runnerColors[r].withValues(alpha: 0.35),
      );
    }

    // --- Drop pin at center (drawn last so it's on top) ---
    // Pin scale pulses: 0.8→1.2
    final pinScale = 0.8 + 0.4 * (0.5 + 0.5 * math.sin(intensity * 2 * math.pi));
    const pinR = 8.0;
    final scaledR = pinR * pinScale;

    // Pin circle
    canvas.drawCircle(
      center,
      scaledR,
      Paint()..color = kAccent2.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      center,
      scaledR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = kFg.withValues(alpha: 0.6),
    );

    // Pin triangle (teardrop point below)
    const triH = 10.0;
    const triW = 7.0;
    final triPath = Path()
      ..moveTo(center.dx - triW * pinScale, center.dy + scaledR - 2)
      ..lineTo(center.dx + triW * pinScale, center.dy + scaledR - 2)
      ..lineTo(center.dx, center.dy + scaledR + triH * pinScale)
      ..close();
    canvas.drawPath(
      triPath,
      Paint()..color = kAccent2.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(DropBeamsPainter old) => old.intensity != intensity;
}
