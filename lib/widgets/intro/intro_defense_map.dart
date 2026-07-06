import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';
import 'intro_phone_card_overlay.dart';

// ---------------------------------------------------------------------------
// 4. IntroDefenseMapA — 4-beat continuity scene, 8s loop (slide 4).
//
//    0-1s     FORTIFY's (slide 2) final-lap ARMOR-3 terminal state, painted
//             directly via IntroContinuity.kFortifyEndFillAlpha/
//             kFortifyEndBorderWidth (never replays slide 2's controller) —
//             inherited blocks underneath, gold border, "ARMOR 3" badge held
//             statically for the beat.
//    1-3.4s   A pink (kRunnerCPink) rival traces the SAME 4-edge closed loop
//             the player traces in slide 3's (YOUR TURF) claim animation —
//             IntroZones.kS1Block1's 4 vertices, closing back to the start —
//             at the same ~0.6s/edge pace as that slide's own comet trace.
//             A "⚠ RAID" chip slides in as the hostile tell.
//    3.4-5.4s IntroPhoneCardOverlay (a static Positioned widget, not part of
//             the map painter) is visible; a shield hex flies from it to the
//             block centroid, firing right as the rival's loop-trace is
//             about to close; a blue dome ignites over the block.
//    5.4-8s   The pink attack trace shatters into fading fragments and
//             retreats; the block stays in its carried ARMOR-3 gold state
//             throughout every beat — it is the same fortified block from
//             Beat 1, never a fresh capture; a shield badge pins; a
//             "DEFENDED" stamp appears.
// ---------------------------------------------------------------------------
class IntroDefenseMapA extends StatefulWidget {
  final Color accent;
  const IntroDefenseMapA({required this.accent, super.key});
  @override
  State<IntroDefenseMapA> createState() => _IntroDefenseMapAState();
}

class _IntroDefenseMapAState extends State<IntroDefenseMapA>
    with TickerProviderStateMixin, IntroMapMixin<IntroDefenseMapA> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  /// FORTIFY's (slide 2) inherited base — every kS1All block — carried into
  /// this scene's opening beat, mirroring intro_fortify_map.dart's own
  /// static under-layer (drawInheritedBlocks).
  List<List<Offset>> _inheritedPts = [];

  List<Offset> _blockPoly = [];

  /// The rival's raid trace — the SAME 4-edge closed loop the player traces
  /// in slide 3's claim animation (IntroCaptureMap): kS1Block1's 4 vertices
  /// with the first point repeated at the end, so the trace closes back to
  /// its start exactly like the player's own claim geometry. Rendered in
  /// kRunnerCPink instead of the player's accent — a rival attempting the
  /// identical claim move against turf the player already fortified.
  List<Offset> _raidLoop = [];

  void _onMapReady() {
    final cam = mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }

    markMapReady(() {
      _inheritedPts =
          IntroZones.kS1All.map((block) => block.map(toScreen).toList()).toList();
      _blockPoly = IntroZones.kS1Block1.map(toScreen).toList();
      _raidLoop = [..._blockPoly, _blockPoly.first];
    });
  }

  /// Beat-3 window (3.4-5.4s of the 8s loop) with a short fade in/out so the
  /// phone-card overlay does not pop in/out abruptly.
  double _cardOpacity(double v) {
    const start = 3.4 / 8;
    const end = 5.4 / 8;
    const fadeWindow = 0.02;
    if (v < start || v > end) return 0.0;
    if (v < start + fadeWindow) {
      return ((v - start) / fadeWindow).clamp(0.0, 1.0);
    }
    if (v > end - fadeWindow) {
      return ((end - v) / fadeWindow).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 8));
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
            onReady: _onMapReady,
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
                final tailPx =
                    kIntroRouteEstimatedMeters.clamp(0.0, kCometTailMaxMeters) /
                        metersPerPx;
                return CustomPaint(
                  painter: _IntroDefenseMapAPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    blockPoly: _blockPoly,
                    raidRoute: _raidLoop,
                    tailLengthPx: tailPx,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          _cardOverlay(),
        ],
      ),
    );
  }

  // Phone-card overlay — Positioned direct Stack child (protocol rule 7).
  // IntroPhoneCardOverlay animates its own opacity internally, so this call
  // site stays a single short expression.
  Widget _cardOverlay() => Positioned(
        left: 16,
        right: 16,
        bottom: 96,
        child:
            IntroPhoneCardOverlay(controller: _ctrl, opacityOf: _cardOpacity),
      );
}

class _IntroDefenseMapAPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> blockPoly;
  final List<Offset> raidRoute;
  final double tailLengthPx;

  _IntroDefenseMapAPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.blockPoly,
    required this.raidRoute,
    required this.tailLengthPx,
  });

  // Beat boundaries (8s loop, t in [0,1]). Beat 2's window was widened from
  // the old 2.0s single-edge approach to 2.4s so the fuller 4-edge loop
  // trace reads at the same ~0.6s/segment pace as slide 3's own capture
  // comet (2.4s / 4 segments there too) — Beats 3/4 each shrink slightly to
  // absorb the difference within the same 8s total.
  static const double _kBeat1End = 1.0 / 8; // 0-1s
  static const double _kBeat2End = 3.4 / 8; // 1-3.4s (2.4s raid loop trace)
  static const double _kBeat3End = 5.4 / 8; // 3.4-5.4s (2.0s shield deploy)
  // Beat 4 runs from _kBeat3End through t=1.0 (5.4-8s, 2.6s).

  Offset _centroid(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    double sx = 0, sy = 0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  /// The persistent shield badge pins to the block's top-right vertex (the
  /// screen point with the smallest dy, i.e. the topmost corner of the
  /// fortified polygon) rather than the map, mirroring the reference scene
  /// where the shield icon locks onto the zone's top-right corner and stays
  /// there for the rest of the loop.
  Offset _topRightVertex(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    return pts.reduce((a, b) => a.dy <= b.dy ? a : b);
  }

  Path _makePoly(List<Offset> pts) {
    if (pts.isEmpty) return Path();
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    return p..close();
  }

  void _drawLabel(Canvas canvas, Offset centroid, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(centroid.dx - tp.width / 2, centroid.dy - tp.height / 2),
    );
  }

  void _drawRaidChip(Canvas canvas, Size size, double slideT) {
    final dx = (1.0 - slideT) * 60;
    final pos = Offset(size.width - 90 + dx, 40);
    final tp = TextPainter(
      text: TextSpan(
        text: '⚠ RAID',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
          color: kRunnerCPink.withValues(alpha: slideT),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  /// The raid attempt visibly and unambiguously fails — the pink trace
  /// shatters into fading fragments and the runner retreats, rather than
  /// resolving off-screen or via a silent recolor.
  void _drawShatterRetreat(Canvas canvas, List<Offset> route, double retreatT) {
    if (route.length < 2) return;
    final fade = (1.0 - retreatT).clamp(0.0, 1.0);
    if (fade <= 0) return;
    final rnd = math.Random(7);
    for (int i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final jitter = Offset(
        (rnd.nextDouble() - 0.5) * 18 * retreatT,
        (rnd.nextDouble() - 0.5) * 18 * retreatT,
      );
      canvas.drawLine(
        a + jitter,
        b + jitter,
        Paint()
          ..color = kRunnerCPink.withValues(alpha: 0.6 * fade)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    // The runner retreats back toward the route's start as the trace
    // shatters — the attack never touches the block's fortified color.
    final retreatPos = Offset.lerp(route.last, route.first, retreatT)!;
    drawRunnerAt(canvas, retreatPos, kRunnerCPink.withValues(alpha: fade));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (blockPoly.isEmpty) return;

    final centroid = _centroid(blockPoly);
    final blockPath = _makePoly(blockPoly);

    // FORTIFY's (slide 2) inherited base — every kS1All block — painted as a
    // static under-layer, exactly mirroring intro_fortify_map.dart's own
    // opening treatment (drawInheritedBlocks) so the carried turf reads
    // identically across the cut.
    drawInheritedBlocks(canvas, inheritedPts);

    // The block stays in its carried ARMOR-3 state through every beat — this
    // is the same fortified block from Beat 1, not a fresh capture, so the
    // fill and border reuse IntroContinuity.kFortifyEndFillAlpha/
    // kFortifyEndBorderWidth (structurally shared with
    // intro_fortify_map.dart's own final lap) rather than the plain-accent
    // hex-capture look.
    canvas.drawPath(
      blockPath,
      Paint()
        ..color = accent.withValues(alpha: IntroContinuity.kFortifyEndFillAlpha)
        ..style = PaintingStyle.fill,
    );

    // Border stress-flickers during Beat 2 (raid trace); otherwise a steady
    // solid gold IntroContinuity.kFortifyEndBorderWidth stroke, matching
    // ARMOR 3's gold-tinted border in intro_fortify_map.dart.
    double borderWidth = IntroContinuity.kFortifyEndBorderWidth;
    double borderAlpha = 0.9;
    if (t >= _kBeat1End && t < _kBeat2End) {
      final flicker = (math.sin(t * math.pi * 30) + 1) / 2;
      borderWidth =
          IntroContinuity.kFortifyEndBorderWidth * (0.6 + 0.4 * flicker);
      borderAlpha = 0.6 + 0.4 * flicker;
    }
    canvas.drawPath(
      blockPath,
      Paint()
        ..color = kAccent2.withValues(alpha: borderAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // Beat 1 (0-1s): FORTIFY's held terminal frame — the ARMOR 3 badge,
    // static for the whole beat (no fade — it is a held shot, not a
    // transition).
    if (t < _kBeat1End) {
      _drawLabel(canvas, centroid, '⌃⌃⌃ ARMOR 3', kAccent2);
    }

    // Beat 2 (1-3.4s): the rival traces the same 4-edge closed loop the
    // player traces in slide 3's claim animation, in kRunnerCPink; a
    // "RAID" alert chip slides in as the hostile tell.
    if (t >= _kBeat1End && t < _kBeat2End && raidRoute.isNotEmpty) {
      final approachT =
          ((t - _kBeat1End) / (_kBeat2End - _kBeat1End)).clamp(0.0, 1.0);
      drawComet(canvas, raidRoute, approachT,
          tailLengthPx: tailLengthPx, color: kRunnerCPink);
      final segs = raidRoute.length - 1;
      if (segs > 0) {
        final traveled = approachT * segs;
        final segIdx = traveled.floor().clamp(0, segs - 1);
        final segFrac = (traveled - segIdx).clamp(0.0, 1.0);
        final pos = Offset.lerp(
          raidRoute[segIdx],
          raidRoute[(segIdx + 1).clamp(0, segs)],
          segFrac,
        )!;
        drawRunnerAt(canvas, pos, kRunnerCPink);
      }

      final chipSlideT = (((t - _kBeat1End) / 0.05)).clamp(0.0, 1.0);
      _drawRaidChip(canvas, size, chipSlideT);
    }

    // Beat 3 (3.4-5.4s): shield hex flies from the phone-card position to
    // the block centroid — firing right as the rival's loop-trace is about
    // to close, intercepting the claim before it resolves; a blue dome
    // ignites over the still-fortified block.
    if (t >= _kBeat2End && t < _kBeat3End) {
      final flyT =
          ((t - _kBeat2End) / (_kBeat3End - _kBeat2End)).clamp(0.0, 1.0);
      final cardPos = Offset(size.width / 2, size.height - 96);
      final hexPos =
          Offset.lerp(cardPos, centroid, Curves.easeOut.transform(flyT))!;
      drawHexGlyph(
        canvas,
        hexPos,
        12,
        Paint()
          ..color = accent.withValues(alpha: flyT)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      // Blue dome ignites over the block once the hex has mostly arrived.
      final domeT = ((flyT - 0.5) / 0.5).clamp(0.0, 1.0);
      if (domeT > 0) {
        canvas.drawPath(
          blockPath,
          Paint()
            ..color = kSea.withValues(alpha: 0.28 * domeT)
            ..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          blockPath,
          Paint()
            ..color = kSea.withValues(alpha: 0.6 * domeT)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }

    // Beat 4 (5.4-8s): the raid trace shatters and retreats; the block stays
    // in its carried ARMOR-3 gold state throughout; a shield badge pins; the
    // "DEFENDED" stamp appears.
    if (t >= _kBeat3End) {
      final retreatT = ((t - _kBeat3End) / (1.0 - _kBeat3End)).clamp(0.0, 1.0);
      _drawShatterRetreat(canvas, raidRoute, retreatT);

      drawHexGlyph(
        canvas,
        _topRightVertex(blockPoly),
        9,
        Paint()
          ..color = kSea.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      final stampOpacity = (retreatT / 0.3).clamp(0.0, 1.0);
      if (stampOpacity > 0) {
        _drawLabel(canvas, centroid, 'DEFENDED',
            accent.withValues(alpha: stampOpacity));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroDefenseMapAPainter old) =>
      old.t != t ||
      old.inheritedPts != inheritedPts ||
      old.blockPoly != blockPoly ||
      old.raidRoute != raidRoute ||
      old.tailLengthPx != tailLengthPx;
}
