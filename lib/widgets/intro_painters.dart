import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

// ---------------------------------------------------------------------------
// _PulseRingsPainter — slide 1 full-bleed background
// 4 concentric rings expanding from centre, fading out. Color = slide tagColor.
// ---------------------------------------------------------------------------
class PulseRingsPainter extends CustomPainter {
  const PulseRingsPainter({required this.t, required this.color});
  final double t; // 0..1 looping
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR =
        math.sqrt(size.width * size.width + size.height * size.height) / 2;
    const rings = 4;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (int i = 0; i < rings; i++) {
      final phase = (t + i / rings) % 1.0;
      final r = maxR * phase;
      final alpha = (1.0 - phase) * 0.5;
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(PulseRingsPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// _HexLassoPainter — slide 2 (lasso a zone)
// 6 surrounding dim hexes + 1 animated centre hex.
// Phase 0→0.4: dashed stroke grows; 0.4→0.7: solid stroke; 0.7→1.0: fill.
// ---------------------------------------------------------------------------
class HexLassoPainter extends CustomPainter {
  const HexLassoPainter({required this.t, required this.accentColor});
  final double t;
  final Color accentColor;

  static Path _hexPath(Offset center, double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 6 + math.pi / 3 * i;
      final p = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.18;

    // Surrounding hexes (static, dim)
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = accentColor.withValues(alpha: 0.15);
    const offsets = [
      Offset(0, -1.73),
      Offset(1.5, -0.87),
      Offset(1.5, 0.87),
      Offset(0, 1.73),
      Offset(-1.5, 0.87),
      Offset(-1.5, -0.87),
    ];
    for (final o in offsets) {
      canvas.drawPath(
        _hexPath(Offset(cx + o.dx * r, cy + o.dy * r), r * 0.95),
        bgPaint,
      );
    }

    // Centre hex — animated
    final cp = _hexPath(Offset(cx, cy), r);
    if (t < 0.4) {
      // Dashed growing stroke
      final fraction = t / 0.4;
      final metrics = cp.computeMetrics().first;
      final dashPath = metrics.extractPath(0, metrics.length * fraction);
      canvas.drawPath(
        dashPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = accentColor.withValues(alpha: 0.9)
          ..strokeCap = StrokeCap.round,
      );
    } else if (t < 0.7) {
      // Solid stroke
      canvas.drawPath(
        cp,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = accentColor,
      );
    } else {
      // Solid stroke + fill fading in
      final fill = (t - 0.7) / 0.3;
      canvas.drawPath(
        cp,
        Paint()
          ..style = PaintingStyle.fill
          ..color = accentColor.withValues(alpha: fill * 0.35),
      );
      canvas.drawPath(
        cp,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = accentColor,
      );
    }
  }

  @override
  bool shouldRepaint(HexLassoPainter old) =>
      old.t != t || old.accentColor != accentColor;
}

// ---------------------------------------------------------------------------
// _RivalsPainter — slide 3 (rivals running)
// Dim hex grid + 3 runner dots orbiting on distinct ellipses with comet tails.
// ---------------------------------------------------------------------------
class RivalsPainter extends CustomPainter {
  const RivalsPainter({required this.t});
  final double t; // 0..1 looping

  static Path _hexPath(Offset center, double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 6 + math.pi / 3 * i;
      final p = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.16;

    // Hex grid background
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = kBorder.withValues(alpha: 0.3);
    const hexOffsets = [
      Offset(0, -1.73),
      Offset(1.5, -0.87),
      Offset(1.5, 0.87),
      Offset(0, 1.73),
      Offset(-1.5, 0.87),
      Offset(-1.5, -0.87),
      Offset(0, 0),
    ];
    for (final o in hexOffsets) {
      canvas.drawPath(
        _hexPath(Offset(cx + o.dx * r, cy + o.dy * r), r * 0.95),
        bgPaint,
      );
    }

    // 3 runner dots on distinct elliptical orbits
    final runners = [
      _RunnerDef(
        color: kAccent,
        rx: size.width * 0.28,
        ry: size.height * 0.18,
        center: Offset(cx, cy - size.height * 0.05),
        phase: 0.0,
      ),
      _RunnerDef(
        color: kAccent2,
        rx: size.width * 0.22,
        ry: size.height * 0.22,
        center: Offset(cx + size.width * 0.06, cy + size.height * 0.06),
        phase: 0.33,
      ),
      _RunnerDef(
        color: kSea,
        rx: size.width * 0.30,
        ry: size.height * 0.14,
        center: Offset(cx - size.width * 0.04, cy + size.height * 0.08),
        phase: 0.67,
      ),
    ];

    for (final runner in runners) {
      const tail = 6;
      for (int j = tail; j >= 0; j--) {
        final tOffset = (t + runner.phase + j * 0.015) % 1.0;
        final angle = tOffset * 2 * math.pi;
        final pos = Offset(
          runner.center.dx + runner.rx * math.cos(angle),
          runner.center.dy + runner.ry * math.sin(angle),
        );
        final alpha = j == 0 ? 1.0 : (1.0 - j / tail) * 0.35;
        final dotR =
            j == 0 ? 5.0 : (3.0 * (1.0 - j / tail)).clamp(1.0, 5.0);
        canvas.drawCircle(
          pos,
          dotR,
          Paint()..color = runner.color.withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(RivalsPainter old) => old.t != t;
}

class _RunnerDef {
  const _RunnerDef({
    required this.color,
    required this.rx,
    required this.ry,
    required this.center,
    required this.phase,
  });
  final Color color;
  final double rx, ry;
  final Offset center;
  final double phase;
}

// ---------------------------------------------------------------------------
// _DropBeamsPainter — slide 4 (CTF drop)
// Fork of _BeamsPainter from map_screen.dart; uses kAccent2 beams + kAccent ring.
// intensity drives alpha; outerR scales with canvas size.
// ---------------------------------------------------------------------------
class DropBeamsPainter extends CustomPainter {
  const DropBeamsPainter({required this.intensity});
  final double intensity; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const innerR = 24.0;
    const beams = 8;
    final outerR = math.min(size.width, size.height) * 0.44;

    final paint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < beams; i++) {
      final angle = (2 * math.pi * i) / beams;
      final end = outerR - (i.isOdd ? 8.0 : 0.0);
      paint.color = kAccent2.withValues(
        alpha: (0.3 + 0.5 * intensity) * (i.isEven ? 1.0 : 0.6),
      );
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * innerR,
          center.dy + math.sin(angle) * innerR,
        ),
        Offset(
          center.dx + math.cos(angle) * end,
          center.dy + math.sin(angle) * end,
        ),
        paint,
      );
    }

    // Pulsing centre ring
    final ringR = 18.0 + 8.0 * intensity;
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = kAccent.withValues(alpha: 0.8 - 0.5 * intensity),
    );

    // Centre dot
    canvas.drawCircle(
      center,
      6,
      Paint()..color = kAccent.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(DropBeamsPainter old) => old.intensity != intensity;
}
