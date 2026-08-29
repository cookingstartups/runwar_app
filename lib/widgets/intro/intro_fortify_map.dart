import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 4. IntroFortifyMap - 3 re-laps of the shared block, fill-only influence
//    levels 3 -> 6 -> 9 (slide 2). 8s total loop, ~2.7s per lap. Traces
//    IntroZones.kS1Block1 directly (continuity with slides 2/3 - R-13),
//    replacing the old bespoke 6-waypoint route that pointed at an
//    unrelated location.
//
//    Territory renders as a flat-alpha fill only - no border stroke,
//    no gold hard-switch on the final lap, no centroid pulse ring - the
//    2026-08-29 redesign. Fill alpha = 0.0633 * influenceLevel, with laps
//    mapping to levels 3/6/9 (lap 0 = alpha 0.19, lap 1 = alpha 0.38, lap 2
//    = alpha 0.57). Each lap close fires a brief one-shot flare (level-up
//    feedback), easing out over IntroContinuity.kCaptureFlashDuration.
//
//    Lap/fill/flare are derived as a pure function of the controller value
//    inside AnimatedBuilder.builder - no addListener/setState anti-pattern
//    (protocol rule 1; design.md).
// ---------------------------------------------------------------------------
class IntroFortifyMap extends StatefulWidget {
  final Color accent;
  const IntroFortifyMap({required this.accent, super.key});
  @override
  State<IntroFortifyMap> createState() => _IntroFortifyMapState();
}

class _IntroFortifyMapState extends State<IntroFortifyMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroFortifyMap> {
  // This slide's layout (textTopVisualBottom) overlays the text/CTA block
  // over roughly the top half of the screen, so the animation should read in
  // the bottom half. IntroContinuity.kMapCenter is shared with slides 3 and
  // 4, which use a different layout - reusing it here put kS1Block1 too far
  // north on screen, clipping it behind the text panel. This constant is
  // local to this slide only; it must NOT be merged back into
  // IntroContinuity.kMapCenter, which the other slides still rely on
  // unchanged.
  static const _kMapCenter = LatLng(39.4659, -0.3756);

  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _routePts = [];

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
      _routePts = IntroZones.kS1Block1.map(toScreen).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    );
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
                // Pure function of the controller value - exactly 3 laps,
                // no separate _level state field or listener (R-12).
                final lap = (_ctrl.value * 3).floor().clamp(0, 2);
                return CustomPaint(
                  painter: _IntroFortifyMapPainter(
                    t: _ctrl.value,
                    lap: lap,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    routePts: _routePts,
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

class _IntroFortifyMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;

  /// 0, 1 or 2 -> influence level 3, 6, 9 (design.md: `(_ctrl.value * 3).floor().clamp(0, 2)`).
  final int lap;

  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> routePts;
  final double tailLengthPx;

  _IntroFortifyMapPainter({
    required this.t,
    required this.lap,
    required this.accent,
    required this.inheritedPts,
    required this.routePts,
    required this.tailLengthPx,
  });

  // Flat-alpha influence-fill unit - 0.0633 per level, so level 9 (the
  // final lap) resolves to 0.0633 * 9 = 0.5697, rounded to
  // IntroContinuity.kFortifyEndFillAlpha (0.57). Slide 4 (SHIELD) reuses
  // that exact constant to open on this slide's terminal state, so the two
  // frames can never visually drift apart.
  static const double _kInfluenceAlphaUnit = 0.0633;

  /// Arc-length interpolation along a closed polyline.
  Offset _posOnClosedLoop(List<Offset> pts, double frac) {
    if (pts.isEmpty) return Offset.zero;
    if (pts.length == 1) return pts[0];
    final segCount = pts.length;
    double totalLen = 0;
    final segLens = List<double>.filled(segCount, 0);
    for (int i = 0; i < segCount; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final len = (b - a).distance;
      segLens[i] = len;
      totalLen += len;
    }
    if (totalLen == 0) return pts[0];
    double target = frac.clamp(0.0, 1.0) * totalLen;
    for (int i = 0; i < segCount; i++) {
      final segLen = segLens[i];
      if (target <= segLen) {
        final a = pts[i];
        final b = pts[(i + 1) % pts.length];
        return Offset.lerp(a, b, segLen > 0 ? target / segLen : 0)!;
      }
      target -= segLen;
    }
    return pts[0];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (routePts.isEmpty) return;

    // 0. Inherited orange blocks - static base.
    drawInheritedBlocks(canvas, inheritedPts);

    // 1. Block fill - flat alpha, thickens with each completed lap
    // (level 3 -> 6 -> 9). No border, no gradient, no pulse modulation -
    // the final lap resolves to IntroContinuity's shared constant directly,
    // rather than recomputing a value that merely happens to match - slide
    // 4 (SHIELD) opens on this exact fill alpha.
    final influenceLevel = switch (lap) { 0 => 3, 1 => 6, _ => 9 };
    final fillOpacity = lap == 2
        ? IntroContinuity.kFortifyEndFillAlpha
        : _kInfluenceAlphaUnit * influenceLevel;
    drawFillColor(canvas, routePts, accent, fillOpacity);

    // 2. Runner traces the block once per lap (3 laps / 8s loop) - persists
    // continuously (no fade) so the loop reads as ongoing training effort.
    final closedRoute = [...routePts, routePts[0]];
    final lapPos = (t * 3) % 1.0;
    drawComet(canvas, closedRoute, lapPos,
        tailLengthPx: tailLengthPx, color: accent);
    final runnerPos = _posOnClosedLoop(routePts, lapPos);
    drawRunnerAt(canvas, runnerPos, accent);

    // 3. On each lap close (level-up), a brief one-shot fill flare eases
    // out over IntroContinuity.kCaptureFlashDuration - the level-up moment
    // feedback, reusing the same easing shape as the map screen's capture
    // flash. Only fires when a lap has genuinely just closed (lap > 0);
    // the very first frame (lap == 0, t == 0) is the block already sitting
    // at level 3, not a level-up.
    if (lap > 0) {
      const lapDurationMs = 8000.0 / 3.0;
      final withinLapMs = ((t * 3) - lap) * lapDurationMs;
      final flareWindowMs =
          IntroContinuity.kCaptureFlashDuration.inMilliseconds.toDouble();
      if (withinLapMs < flareWindowMs) {
        final flareT = withinLapMs / flareWindowMs;
        final flareAlpha = (1.0 - flareT) * 0.35;
        drawFillColor(canvas, routePts, accent, flareAlpha);
      }
    }
  }

  @override
  bool shouldRepaint(_IntroFortifyMapPainter old) =>
      old.t != t ||
      old.lap != lap ||
      old.tailLengthPx != tailLengthPx ||
      old.routePts != routePts ||
      old.inheritedPts != inheritedPts;
}
