import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 7. IntroPhysicalEventsMap — 3 runners race to finish (Real Events slide)
//    Pure CustomPaint — no flutter_map.
// ---------------------------------------------------------------------------
class IntroPhysicalEventsMap extends StatefulWidget {
  final Color accent;
  const IntroPhysicalEventsMap({required this.accent, super.key});
  @override
  State<IntroPhysicalEventsMap> createState() => _IntroPhysicalEventsMapState();
}

class _IntroPhysicalEventsMapState extends State<IntroPhysicalEventsMap>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    loopController(_ctrl, mounted: () => mounted);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _IntroPhysicalEventsPainter(
            t: _ctrl.value,
            accent: widget.accent,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _IntroPhysicalEventsPainter extends CustomPainter {
  final double t;
  final Color accent;

  const _IntroPhysicalEventsPainter({required this.t, required this.accent});

  static const _kRunnerColors = [kAccent, kSea, kAccent2];
  static const _kStartOffsets = [0.15, 0.10, 0.05]; // x-factor stagger at t=0

  void _drawHexGrid(Canvas canvas, Size size) {
    const double hexR = 22.0;
    final paint = Paint()
      ..color = kAccent2.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    final double hexH = hexR * math.sqrt(3);
    int col = 0;
    for (double x = -hexR; x < size.width + hexR * 2; x += hexR * 1.5, col++) {
      final yOffset = (col % 2 == 0) ? 0.0 : hexH / 2;
      for (double y = -hexH + yOffset; y < size.height + hexH; y += hexH) {
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = (math.pi / 3) * i - math.pi / 2;
          final px = x + hexR * math.cos(angle);
          final py = y + hexR * math.sin(angle);
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawRunner(Canvas canvas, Offset pos, Color color, double alpha) {
    if (alpha <= 0) return;
    // Head.
    canvas.drawCircle(pos.translate(0, -20), 8,
        Paint()..color = color.withValues(alpha: alpha));
    // Body.
    canvas.drawRect(
        Rect.fromCenter(center: pos.translate(0, -6), width: 16, height: 28),
        Paint()..color = color.withValues(alpha: alpha));
    // Legs (diagonal lines).
    final legPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        pos.translate(-5, 8), pos.translate(-12, 28), legPaint);
    canvas.drawLine(
        pos.translate(5, 8), pos.translate(12, 28), legPaint);
  }

  void _drawFinishLine(Canvas canvas, double x, Size size) {
    const checkerH = 8.0;
    const checkerW = 12.0;
    int row = 0;
    for (double y = 0; y < size.height; y += checkerH, row++) {
      for (int col = 0; col < 2; col++) {
        final isDark = (row + col) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x + col * checkerW, y, checkerW, checkerH),
          Paint()
            ..color = isDark ? Colors.black : Colors.white
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  void _drawPodium(Canvas canvas, Offset bottomCenter, double opacity) {
    if (opacity <= 0) return;
    final heights = [60.0, 80.0, 40.0]; // 2nd, 1st, 3rd
    final labels = ['2', '1', '3'];
    const w = 36.0;
    final strokePaint = Paint()
      ..color = kAccent2.withValues(alpha: opacity)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = kAccent2.withValues(alpha: opacity * 0.15)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 3; i++) {
      final x = bottomCenter.dx + (i - 1) * (w + 4);
      final rect = Rect.fromLTWH(x - w / 2, bottomCenter.dy - heights[i], w, heights[i]);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: kAccent2.withValues(alpha: opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, bottomCenter.dy - heights[i] - 20));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = kBg,
    );

    // Faint diagonal hex grid.
    _drawHexGrid(canvas, size);

    // Finish line at x = 0.78 * size.width.
    final finishX = 0.78 * size.width;
    _drawFinishLine(canvas, finishX, size);

    // 3 runners.
    final runnerY = size.height * 0.50;
    for (int i = 0; i < 3; i++) {
      final color = _kRunnerColors[i];
      final startX = _kStartOffsets[i] * size.width;
      final endX = finishX;
      final progress = (t / 0.65).clamp(0.0, 1.0);
      final runnerX = startX + (endX - startX) * progress;
      final pos = Offset(runnerX, runnerY + (i - 1) * 14.0);

      // Motion blur ghost stamps.
      for (int g = 1; g <= 4; g++) {
        final ghostAlphas = [0.07, 0.14, 0.22, 0.35];
        _drawRunner(canvas, pos.translate(-12.0 * g, 0), color, ghostAlphas[g - 1]);
      }
      _drawRunner(canvas, pos, color, 1.0);
    }

    // Stopwatch top-left.
    final totalSecs = (t * 14).floor();
    final frames = ((t * 1488).floor() % 100);
    final stopwatch =
        '00:${totalSecs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
    final swTp = TextPainter(
      text: TextSpan(
        text: stopwatch,
        style: GoogleFonts.robotoMono(
          fontSize: 18,
          color: kAccent2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    swTp.paint(canvas, const Offset(12, 12));

    // Podium (t >= 0.78).
    if (t >= 0.78) {
      final podiumOpacity = ((t - 0.78) / 0.07).clamp(0.0, 1.0);
      _drawPodium(
          canvas, Offset(size.width / 2, size.height - 16), podiumOpacity);
    }

    // "COMING SOON" stamp (t >= 0.85).
    if (t >= 0.85) {
      final stampOpacity = ((t - 0.85) / 0.05).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: 'COMING SOON',
          style: GoogleFonts.bebasNeue(
            fontSize: 40,
            color: kAccent2.withValues(alpha: stampOpacity),
          ).copyWith(
            shadows: [
              Shadow(
                color: kAccent2.withValues(alpha: stampOpacity * 0.7),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(
          canvas,
          Offset(
              (size.width - tp.width) / 2, size.height / 2 - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_IntroPhysicalEventsPainter old) => old.t != t;
}
