import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 4. IntroFortifyMap - 3 re-laps of the shared block, ARMOR 1->2->3 (slide 4).
//    8s total loop, ~2.7s per lap. Traces IntroZones.kS1Block1 directly
//    (continuity with slides 2/3 - R-13), replacing the old bespoke
//    old bespoke 6-waypoint route that pointed at an unrelated location.
//    Lap/badge/border are derived as a pure function of the controller
//    value inside AnimatedBuilder.builder - no addListener/setState
//    anti-pattern (protocol rule 1; design.md).
// ---------------------------------------------------------------------------
class IntroFortifyMap extends StatefulWidget {
  final Color accent;
  const IntroFortifyMap({required this.accent, super.key});
  @override
  State<IntroFortifyMap> createState() => _IntroFortifyMapState();
}

class _IntroFortifyMapState extends State<IntroFortifyMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroFortifyMap> {
  // This slide's layout (visualTopTextBottom) overlays the text/CTA block
  // over roughly the bottom half of the screen. IntroContinuity.kMapCenter
  // is shared with slides 3 and 4, which use a different layout - reusing it
  // here put kS1Block1 too far south on screen, clipping it behind the text
  // panel. This constant is local to this slide only; it must NOT be merged
  // back into IntroContinuity.kMapCenter, which the other slides still rely
  // on unchanged.
  static const _kMapCenter = LatLng(39.4608, -0.3756);

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

  /// 0, 1 or 2 -> ARMOR 1, 2, 3 (design.md: `(_ctrl.value * 3).floor().clamp(0, 2)`).
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

  static const List<String> _kArmorBadges = [
    '⌃ ARMOR 1',
    '⌃⌃ ARMOR 2',
    '⌃⌃⌃ ARMOR 3',
  ];

  // The final-lap (ARMOR 3) border width is IntroContinuity's shared
  // constant, not a local literal - slide 4 (SHIELD) reuses this exact
  // value to open on this slide's terminal state, so the two frames can
  // never visually drift apart.
  static const List<double> _kArmorBorderWidths = [
    1.5,
    3.0,
    IntroContinuity.kFortifyEndBorderWidth,
  ];

  Offset _routeCentroid() {
    if (routePts.isEmpty) return Offset.zero;
    double sumX = 0, sumY = 0;
    for (final pt in routePts) {
      sumX += pt.dx;
      sumY += pt.dy;
    }
    return Offset(sumX / routePts.length, sumY / routePts.length);
  }

  /// NW-most vertex - approximated as minimising (dx + dy) in screen-space.
  Offset _nwVertex() {
    if (routePts.isEmpty) return Offset.zero;
    Offset nw = routePts[0];
    for (final pt in routePts) {
      if (pt.dx + pt.dy < nw.dx + nw.dy) nw = pt;
    }
    return nw;
  }

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

    // 1. Block fill - thickens with each completed lap (ARMOR 1 -> 2 -> 3).
    // The final lap (ARMOR 3) resolves to IntroContinuity's shared constant
    // directly, rather than recomputing a value that merely happens to
    // match - slide 4 (SHIELD) opens on this exact fill alpha.
    final fillOpacity =
        lap == 2 ? IntroContinuity.kFortifyEndFillAlpha : 0.30 + lap * 0.18;
    drawFillColor(canvas, routePts, accent, fillOpacity);

    // 2. Border - thickens with each completed lap; gold-tinted at ARMOR 3.
    final borderColor = lap == 2 ? kAccent2 : accent;
    final borderWidth = _kArmorBorderWidths[lap];
    final loopPath = Path()..moveTo(routePts[0].dx, routePts[0].dy);
    for (int i = 1; i < routePts.length; i++) {
      loopPath.lineTo(routePts[i].dx, routePts[i].dy);
    }
    loopPath.close();
    canvas.drawPath(
      loopPath,
      Paint()
        ..color = borderColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round,
    );

    // 3. ARMOR badge - steps 1 -> 2 -> 3 as each ~2.7s lap completes (R-12).
    final nw = _nwVertex();
    final centroid = _routeCentroid();
    final labelPos = nw + (centroid - nw) * 0.18;
    final badgeColor = lap == 2 ? kAccent2 : Colors.white;
    final tp = TextPainter(
      text: TextSpan(
        text: _kArmorBadges[lap],
        style: TextStyle(
          color: badgeColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'BebasNeue',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));

    // 4. Runner traces the block once per lap (3 laps / 8s loop) - persists
    // continuously (no fade) so the loop reads as ongoing training effort.
    final closedRoute = [...routePts, routePts[0]];
    final lapPos = (t * 3) % 1.0;
    drawComet(canvas, closedRoute, lapPos,
        tailLengthPx: tailLengthPx, color: accent);
    final runnerPos = _posOnClosedLoop(routePts, lapPos);
    drawRunnerAt(canvas, runnerPos, accent);

    // 5. At ARMOR 3 (final lap), a gold pulse ring reinforces the
    // max-hardened state.
    if (lap == 2) {
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
  }

  @override
  bool shouldRepaint(_IntroFortifyMapPainter old) =>
      old.t != t ||
      old.lap != lap ||
      old.tailLengthPx != tailLengthPx ||
      old.routePts != routePts ||
      old.inheritedPts != inheritedPts;
}
