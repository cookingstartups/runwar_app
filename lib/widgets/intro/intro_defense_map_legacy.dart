import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 6. IntroDefenseMap — EARN YOUR EDGE slide: earn by running, boost with
//    credits — never buy the conquest.
//
//    Beat 1 (EARN): the runner traces IntroZones.kS1Block1 — the same shared
//    street block slides 2 and 4 trace — the loop closes and the block fills
//    to the standard claimed state (IntroContinuity.kBlock1EndFillAlpha /
//    kBlock1EndBorderWidth, identical visual language to
//    intro_capture_map.dart's CLAIMED beat), then a hex shield glyph pops:
//    the superpower was EARNED by the run, never bought.
//
//    Beat 2 (BOOST): the runner now STANDS on the block they own; a credit
//    offer chip ("FORTIFY · 1 CREDIT") slides in and is applied — the block
//    hardens to the gold reinforced treatment shared with
//    intro_fortify_map.dart's ARMOR 3 terminal state
//    (IntroContinuity.kFortifyEndFillAlpha / kFortifyEndBorderWidth).
//    Credits only stretch what running earned — they never claim ground.
// ---------------------------------------------------------------------------
class IntroDefenseMap extends StatefulWidget {
  final Color accent;
  const IntroDefenseMap({required this.accent, super.key});
  @override
  State<IntroDefenseMap> createState() => _IntroDefenseMapState();
}

class _IntroDefenseMapState extends State<IntroDefenseMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroDefenseMap> {
  // This slide's layout (textTopVisualBottom) overlays the text/CTA block
  // over roughly the top half of the screen, so the animation should read in
  // the bottom half — same constraint (and same value) as
  // intro_fortify_map.dart's local override. It must NOT be merged into
  // IntroContinuity.kMapCenter, which the visualTopTextBottom slides rely on
  // unchanged.
  static const _kMapCenter = LatLng(39.4659, -0.3756);

  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  List<List<Offset>> _inheritedPts = [];

  /// The vertices of the claimed block, unclosed (for fill/border).
  List<Offset> _blockPoly = [];

  /// Same vertices with the first repeated at the end, so the comet/runner
  /// trace closes the loop back to its start.
  List<Offset> _blockLoop = [];

  void _onMapReady() {
    final cam = mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }

    markMapReady(() {
      _inheritedPts = IntroZones.kS1All
          .map((block) => block.map(toScreen).toList())
          .toList();
      _blockPoly = IntroZones.kS1Block1.map(toScreen).toList();
      _blockLoop = [..._blockPoly, _blockPoly.first];
    });
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
            center: _kMapCenter,
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
                final tailPx = (_ctrl.value * kIntroRouteEstimatedMeters)
                        .clamp(0.0, kCometTailMaxMeters) /
                    metersPerPx;
                return CustomPaint(
                  painter: _IntroDefenseMapPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    blockPoly: _blockPoly,
                    blockLoop: _blockLoop,
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

class _IntroDefenseMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> blockPoly;
  final List<Offset> blockLoop;
  final double tailLengthPx;

  _IntroDefenseMapPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.blockPoly,
    required this.blockLoop,
    required this.tailLengthPx,
  });

  // Timeline (8s loop):
  //   0.00–0.40  Beat 1a — comet trace + runner around kS1Block1's edges.
  //   0.40–0.48  Beat 1b — loop closes: ping ring, fill/border sweep to the
  //              shared claimed state, "CLAIMED" stamp fades in.
  //   0.48–0.52  runner lerps from the closing vertex to the block centroid
  //              (they now stand ON the zone they own).
  //   0.52–0.64  Beat 1c — hex shield glyph pops + "SHIELD EARNED": the
  //              superpower unlocked by the run itself.
  //   0.66–0.74  Beat 2a — credit chip "FORTIFY · 1 CREDIT" slides in above
  //              the block (spend allowed only while standing on owned turf).
  //   0.74–0.84  Beat 2b — chip applied: white flash, fill/border ramp to the
  //              gold ARMOR-3 reinforced treatment; chip fades out.
  //   0.86–1.00  Beat 2c — closing labels "EARNED ON THE STREET" /
  //              "CREDITS ONLY BOOST IT"; gold pulse; hold until loop pause.
  static const double _kTraceEndT = 0.40;
  static const double _kFillDoneT = 0.48;
  static const double _kStandDoneT = 0.52;
  static const double _kEarnEndT = 0.64;
  static const double _kChipInT = 0.66;
  static const double _kApplyT = 0.74;
  static const double _kGoldDoneT = 0.84;
  static const double _kLabelT = 0.86;

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

  void _paintCenteredText(Canvas canvas, Offset center, TextSpan span) {
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (blockPoly.isEmpty || blockLoop.isEmpty) return;

    final centroid = _centroid(blockPoly);

    // 0. Inherited blocks — static orange base (prior territory).
    drawInheritedBlocks(canvas, inheritedPts);

    final closed = t >= _kTraceEndT;

    // ── Beat 1a: comet trace + runner around the block's real street edges ──
    if (!closed) {
      final traceProgress = (t / _kTraceEndT).clamp(0.0, 1.0);
      drawComet(canvas, blockLoop, traceProgress,
          tailLengthPx: tailLengthPx, color: accent);

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
      return; // nothing else exists before the loop closes
    }

    // ── Beat 1b/2b: block fill + border — claimed state, then gold ramp ─────
    final fillRamp = ((t - _kTraceEndT) / (_kFillDoneT - _kTraceEndT))
        .clamp(0.0, 1.0);
    final goldRamp =
        ((t - _kApplyT) / (_kGoldDoneT - _kApplyT)).clamp(0.0, 1.0);

    final fillColor = Color.lerp(accent, kAccent2, goldRamp)!;
    final fillAlpha = IntroContinuity.kBlock1EndFillAlpha * fillRamp +
        (IntroContinuity.kFortifyEndFillAlpha -
                IntroContinuity.kBlock1EndFillAlpha) *
            goldRamp;
    drawFillColor(canvas, blockPoly, fillColor, fillAlpha);

    final borderColor = Color.lerp(accent, kAccent2, goldRamp)!;
    final borderWidth = IntroContinuity.kBlock1EndBorderWidth * fillRamp +
        (IntroContinuity.kFortifyEndBorderWidth -
                IntroContinuity.kBlock1EndBorderWidth) *
            goldRamp;
    if (borderWidth > 0) {
      canvas.drawPath(
        _makePoly(blockPoly),
        Paint()
          ..color = borderColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Expanding ring ping at the close beat (same language as capture map).
    final pingT = ((t - _kTraceEndT) / 0.08).clamp(0.0, 1.0);
    if (pingT < 1.0) {
      final ringAlpha = ((1.0 - pingT) * 0.7).clamp(0.0, 1.0);
      canvas.drawCircle(
        centroid,
        pingT * 60.0,
        Paint()
          ..color = accent.withValues(alpha: ringAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    // ── Runner: closing vertex → centroid, then standing on the owned zone ──
    final standT = ((t - _kFillDoneT) / (_kStandDoneT - _kFillDoneT))
        .clamp(0.0, 1.0);
    final runnerPos = Offset.lerp(blockLoop.last, centroid, standT)!;
    drawRunnerAt(canvas, runnerPos, accent);

    // ── "CLAIMED" stamp — fades in at fill-done, out as the EARN beat lands ─
    if (t >= _kFillDoneT && t < _kEarnEndT) {
      final stampIn = ((t - _kFillDoneT) / 0.04).clamp(0.0, 1.0);
      final stampOut = t < _kEarnEndT - 0.06
          ? 1.0
          : (1.0 - (t - (_kEarnEndT - 0.06)) / 0.06).clamp(0.0, 1.0);
      final stampOpacity = stampIn * stampOut;
      if (stampOpacity > 0) {
        _paintCenteredText(
          canvas,
          centroid + const Offset(0, 30),
          TextSpan(
            text: 'CLAIMED',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: accent.withValues(alpha: stampOpacity),
            ),
          ),
        );
      }
    }

    // ── Beat 1c: hex shield glyph pops — superpower EARNED by the run ───────
    if (t >= _kStandDoneT) {
      final popT = ((t - _kStandDoneT) / 0.06).clamp(0.0, 1.0);
      final popEase = 1.0 - math.pow(1.0 - popT, 3).toDouble();
      final hexCenter = centroid + const Offset(0, -56);
      final hexColor = Color.lerp(accent, kAccent2, goldRamp)!;
      drawHexGlyph(
        canvas,
        hexCenter,
        16.0 * popEase,
        Paint()
          ..color = hexColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round,
      );
      // One expanding echo ring as it lands.
      if (popT < 1.0) {
        canvas.drawCircle(
          hexCenter,
          10 + popT * 26,
          Paint()
            ..color = hexColor.withValues(alpha: (1.0 - popT) * 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      // "SHIELD EARNED" — visible through the EARN beat, then hands off.
      if (t < _kApplyT) {
        final earnFade = t < _kChipInT
            ? popT
            : (1.0 - (t - _kChipInT) / (_kApplyT - _kChipInT)).clamp(0.0, 1.0);
        if (earnFade > 0) {
          _paintCenteredText(
            canvas,
            hexCenter + const Offset(0, -26),
            TextSpan(
              text: 'SHIELD EARNED',
              style: GoogleFonts.bebasNeue(
                fontSize: 20,
                color: accent.withValues(alpha: earnFade),
              ),
            ),
          );
        }
      }
    }

    // ── Beat 2a: credit offer chip — spendable only standing on owned turf ──
    if (t >= _kChipInT && t < _kLabelT) {
      final chipIn = ((t - _kChipInT) / 0.05).clamp(0.0, 1.0);
      final chipOut = t < _kApplyT
          ? 1.0
          : (1.0 - (t - _kApplyT) / (_kGoldDoneT - _kApplyT)).clamp(0.0, 1.0);
      final chipOpacity = chipIn * chipOut;
      if (chipOpacity > 0) {
        final chipCenter =
            centroid + Offset(0, -104 + (1.0 - chipIn) * 10);
        final tp = TextPainter(
          text: TextSpan(
            text: 'FORTIFY · 1 CREDIT',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              color: kAccent2.withValues(alpha: chipOpacity),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final chipRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: chipCenter,
            width: tp.width + 24,
            height: tp.height + 14,
          ),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          chipRect,
          Paint()..color = kBg.withValues(alpha: 0.85 * chipOpacity),
        );
        canvas.drawRRect(
          chipRect,
          Paint()
            ..color = kAccent2.withValues(alpha: 0.9 * chipOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        tp.paint(canvas, chipCenter - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // ── Beat 2b: apply flash — white ring as the credit boost lands ─────────
    if (t >= _kApplyT && t < _kApplyT + 0.06) {
      final flashT = ((t - _kApplyT) / 0.06).clamp(0.0, 1.0);
      canvas.drawCircle(
        centroid,
        flashT * 90,
        Paint()
          ..color = Colors.white.withValues(alpha: (1.0 - flashT) * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // ── Beat 2c: gold pulse on the reinforced block (fortify's ARMOR-3 cue) ─
    if (t >= _kGoldDoneT) {
      final pulseT = (math.sin(t * math.pi * 4) + 1) / 2;
      canvas.drawCircle(
        centroid,
        20 + pulseT * 10,
        Paint()
          ..color = kAccent2.withValues(alpha: (1.0 - pulseT) * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    // ── Closing labels — the slide's thesis, anchored below the block ───────
    if (t >= _kLabelT) {
      final labelFade = ((t - _kLabelT) / 0.05).clamp(0.0, 1.0);
      if (labelFade > 0) {
        _paintCenteredText(
          canvas,
          centroid + const Offset(0, 34),
          TextSpan(
            text: 'EARNED ON THE STREET',
            style: GoogleFonts.bebasNeue(
              fontSize: 18,
              color: kAccent2.withValues(alpha: labelFade),
            ),
          ),
        );
        _paintCenteredText(
          canvas,
          centroid + const Offset(0, 52),
          TextSpan(
            text: 'CREDITS ONLY BOOST IT',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              letterSpacing: 1.5,
              color: kFgMuted.withValues(alpha: labelFade),
            ),
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_IntroDefenseMapPainter old) =>
      old.t != t ||
      old.blockPoly != blockPoly ||
      old.blockLoop != blockLoop ||
      old.inheritedPts != inheritedPts ||
      old.tailLengthPx != tailLengthPx;
}
