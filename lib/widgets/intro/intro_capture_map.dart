import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 2. IntroCaptureMap - player claims a single squared block (slide 2).
//    A clean, uncontested claim: the player-controlled runner traces the
//    4 edges of IntroZones.kS1Block1 in the slide's own accent color, the
//    loop closes, the block fills and holds a "CLAIMED" stamp, then the
//    cycle fades and restarts. No rival color and no dispute mechanics
//    ever fire on this slide (R-1..R-4) - the capturer always renders in
//    the player's own accent, never a rival color.
//
//    Two visually distinct layers render here: the carried/pre-owned turf
//    inherited from the prior slide (the "defender's" already-held
//    territory) always paints as fixed kAccent orange, independent of
//    whichever accent this slide is using - while the actively-claimed
//    block (comet trace, runner, fill sweep, "CLAIMED" stamp - the
//    "attacker" claiming new ground) always follows the slide's own
//    widget.accent (currently a light-blue tag color on the YOUR TURF slide).
// ---------------------------------------------------------------------------
class IntroCaptureMap extends StatefulWidget {
  final Color accent;

  /// Optional map-center override. Defaults to the shared
  /// IntroContinuity.kMapCenter used by slides 3/4. The on-screen slide 3
  /// instance (visualTopTextBottom layout) passes a center shifted south so
  /// the claimed block reads in the top half, clear of the bottom text
  /// panel - other callers (e.g. the pre-warm Offstage instance) keep the
  /// shared default so nothing else on screen shifts.
  final LatLng? center;
  const IntroCaptureMap({required this.accent, this.center, super.key});
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

  /// Slide 1's terminal captured territory (every kS1All block), projected to
  /// screen space. Painted as a persistent under-layer so slide 2 opens on the
  /// turf the player already holds - the pulse map's end state carried across
  /// the cut - instead of a blank map that resets each loop.
  List<List<Offset>> _carriedBlocks = [];

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
      _carriedBlocks =
          IntroZones.kS1All.map((b) => b.map(toScreen).toList()).toList();
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
            center: widget.center ?? IntroContinuity.kMapCenter,
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
                    carriedBlocks: _carriedBlocks,
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
  final List<List<Offset>> carriedBlocks;
  final double tailLengthPx;

  _IntroCaptureMapPainter({
    required this.t,
    required this.accent,
    required this.blockLoop,
    required this.blockPoly,
    required this.carriedBlocks,
    required this.tailLengthPx,
  });

  // Beat timing - ~5.2s total cycle (R-3):
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

    // ── Carried turf (slide 1's end state) ─────────────────────────────────
    // Paint the pulse map's captured union directly as a persistent under-
    // layer at IntroContinuity.kS1CapturedFillAlpha. This is slide 1's held
    // territory arriving intact across the cut - it is NOT gated by the loop's
    // fade envelope, so the turf stays put while the claim sequence replays on
    // top of it. Unioned (protocol #5) so contiguous blocks read as one shape
    // with no internal seams, exactly like the pulse map's terminal frame.
    // Always fixed kAccent orange - the "defender's" already-held territory -
    // regardless of this slide's own widget.accent, so it reads as visually
    // distinct from the actively-claimed block painted below in `accent`.
    if (carriedBlocks.isNotEmpty) {
      var carriedUnion = Path();
      for (final block in carriedBlocks) {
        if (block.isEmpty) continue;
        carriedUnion =
            Path.combine(PathOperation.union, carriedUnion, _makePoly(block));
      }
      canvas.drawPath(
        carriedUnion,
        Paint()
          ..color = kAccent.withValues(alpha: IntroContinuity.kS1CapturedFillAlpha)
          ..style = PaintingStyle.fill,
      );
    }

    // Reset window (4.2s-5.2s): everything fades to 0 while the base map
    // persists, so the next cycle restarts with no visible seam.
    final fade = t < _kStampEndT
        ? 1.0
        : (1.0 - (t - _kStampEndT) / (1.0 - _kStampEndT)).clamp(0.0, 1.0);

    final closed = t >= _kCloseT;

    if (!closed) {
      // Comet trace + orange runner tracing the 4 edges. No rival color,
      // no dispute geometry - a clean, uncontested claim (R-1/R-4).
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
      // Fill sweep - ramps to IntroContinuity.kBlock1EndFillAlpha over the
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
      old.carriedBlocks != carriedBlocks ||
      old.tailLengthPx != tailLengthPx;
}
