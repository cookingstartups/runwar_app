import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 2. IntroCaptureMap — player claims a single squared block (slide 2).
//    A clean, uncontested claim: the player-controlled runner traces the
//    4 edges of IntroZones.kS1Block1 in kAccent orange, the loop closes,
//    the block fills orange and holds a "CLAIMED" stamp, then the cycle
//    fades and restarts. No rival color and no dispute mechanics ever fire
//    on this slide (R-1..R-4) — this fixes the prior build's "wrong
//    protagonist" defect where the capturer was rendered in the rival's
//    blue instead of the player's own color.
// ---------------------------------------------------------------------------
class IntroCaptureMap extends StatefulWidget {
  final Color accent;
  const IntroCaptureMap({required this.accent, super.key});
  @override
  State<IntroCaptureMap> createState() => _IntroCaptureMapState();
}

class _IntroCaptureMapState extends State<IntroCaptureMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroCaptureMap> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  /// The 4 vertices of the claimed block, unclosed (for fill/border).
  List<Offset> _blockPoly = [];

  /// The same 4 vertices with the first point repeated at the end, so the
  /// comet/runner trace closes the loop back to its start.
  List<Offset> _blockLoop = [];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5200));
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    loopController(_ctrl, mounted: () => mounted);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _ctrl.dispose();
    disposeMapCtrl();
    super.dispose();
  }

  void _updatePoints() {
    final cam = mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }

    markMapReady(() {
      _blockPoly = IntroZones.kS1Block1.map(toScreen).toList();
      _blockLoop = [..._blockPoly, _blockPoly.first];
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Stack(
        children: [
          buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: IntroContinuity.kMapCenter,
            zoom: IntroContinuity.kMapZoom,
            onReady: _updatePoints,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final zoom = mapCtrl.camera.zoom;
                final lat = mapCtrl.camera.center.latitudeInRad;
                const earthCircumference = 2 * math.pi * 6378137.0;
                final metersPerPx = (earthCircumference * math.cos(lat)) /
                    (256.0 * math.pow(2.0, zoom));
                final tailPx = (_ctrl.value * kIntroRouteEstimatedMeters)
                        .clamp(0.0, kCometTailMaxMeters) /
                    metersPerPx;
                return CustomPaint(
                  painter: _IntroCaptureMapPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    blockLoop: _blockLoop,
                    blockPoly: _blockPoly,
                    tailLengthPx: tailPx,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _IntroCaptureMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<Offset> blockLoop;
  final List<Offset> blockPoly;
  final double tailLengthPx;

  _IntroCaptureMapPainter({
    required this.t,
    required this.accent,
    required this.blockLoop,
    required this.blockPoly,
    required this.tailLengthPx,
  });

  // Beat timing — ~5.2s total cycle (R-3):
  //   0.0 – 2.4s  comet trace around the 4 edges (~0.6s/edge)
  //   2.4s        close: expanding ring ping from the block centroid
  //   2.4 – 3.0s  fill sweep to IntroContinuity.kBlock1EndFillAlpha,
  //               border settles to IntroContinuity.kBlock1EndBorderWidth
  //   3.0 – 4.2s  "CLAIMED" stamp + hold
  //   4.2 – 5.2s  fade out (base map persists), loop restarts seamlessly
  static const double _kCloseT = 2.4 / 5.2;
  static const double _kFillDoneT = 3.0 / 5.2;
  static const double _kStampEndT = 4.2 / 5.2;

  Offset _centroid(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    double sx = 0, sy = 0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  Path _makePoly(List<Offset> pts) {
    if (pts.isEmpty) return Path();
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (blockLoop.isEmpty || blockPoly.isEmpty) return;

    // Reset window (4.2s-5.2s): everything fades to 0 while the base map
    // persists, so the next cycle restarts with no visible seam.
    final fade = t < _kStampEndT
        ? 1.0
        : (1.0 - (t - _kStampEndT) / (1.0 - _kStampEndT)).clamp(0.0, 1.0);

    final closed = t >= _kCloseT;

    if (!closed) {
      // Comet trace + orange runner tracing the 4 edges. No rival color,
      // no dispute geometry — a clean, uncontested claim (R-1/R-4).
      final traceProgress = (t / _kCloseT).clamp(0.0, 1.0);
      drawComet(canvas, blockLoop, traceProgress,
          tailLengthPx: tailLengthPx, color: accent, decayMul: fade);

      final segs = blockLoop.length - 1;
      final traveled = traceProgress * segs;
      final segIdx = traveled.floor().clamp(0, segs - 1);
      final segFrac = (traveled - segIdx).clamp(0.0, 1.0);
      final pos = Offset.lerp(
        blockLoop[segIdx],
        blockLoop[(segIdx + 1).clamp(0, segs)],
        segFrac,
      )!;
      drawRunnerAt(canvas, pos, accent);
    } else {
      // Fill sweep — ramps to IntroContinuity.kBlock1EndFillAlpha over the
      // fill window, then holds through the stamp window. This exact value
      // is what slide 3 re-paints verbatim as its Beat-1 opening frame (R-6).
      final fillRamp =
          ((t - _kCloseT) / (_kFillDoneT - _kCloseT)).clamp(0.0, 1.0);
      final fillAlpha = IntroContinuity.kBlock1EndFillAlpha * fillRamp * fade;
      drawFillColor(canvas, blockPoly, accent, fillAlpha);

      // Border settles to a solid IntroContinuity.kBlock1EndBorderWidth
      // stroke over the same fill window.
      final borderWidth = IntroContinuity.kBlock1EndBorderWidth * fillRamp;
      if (borderWidth > 0) {
        canvas.drawPath(
          _makePoly(blockPoly),
          Paint()
            ..color = accent.withValues(alpha: fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth,
        );
      }

      // Expanding ring ping from the block centroid at the close beat.
      final pingT = ((t - _kCloseT) / 0.12).clamp(0.0, 1.0);
      if (pingT < 1.0) {
        final ringRadius = pingT * 60.0;
        final ringAlpha = ((1.0 - pingT) * 0.7 * fade).clamp(0.0, 1.0);
        if (ringAlpha > 0) {
          canvas.drawCircle(
            _centroid(blockPoly),
            ringRadius,
            Paint()
              ..color = accent.withValues(alpha: ringAlpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0,
          );
        }
      }

      // "CLAIMED" label + hold, 3.0s-4.2s.
      if (t >= _kFillDoneT) {
        final stampFadeIn = ((t - _kFillDoneT) / 0.08).clamp(0.0, 1.0);
        final stampOpacity = stampFadeIn * fade;
        if (stampOpacity > 0) {
          final centroid = _centroid(blockPoly);
          final tp = TextPainter(
            text: TextSpan(
              text: 'CLAIMED',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: accent.withValues(alpha: stampOpacity),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(centroid.dx - tp.width / 2, centroid.dy - tp.height / 2),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_IntroCaptureMapPainter old) =>
      old.t != t ||
      old.blockLoop != blockLoop ||
      old.blockPoly != blockPoly ||
      old.tailLengthPx != tailLengthPx;
}
