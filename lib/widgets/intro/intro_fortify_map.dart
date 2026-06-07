import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 5. IntroFortifyMap — fortify animation: runner loops the claimed chunk (slide 4)
// 15 loops over 7.5 s, level 1→15; player fades at end, polygon + label persist.
// ---------------------------------------------------------------------------
class IntroFortifyMap extends StatefulWidget {
  final Color accent;
  const IntroFortifyMap({required this.accent, super.key});
  @override
  State<IntroFortifyMap> createState() => _IntroFortifyMapState();
}

class _IntroFortifyMapState extends State<IntroFortifyMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroFortifyMap> {
  /// Main animation: 15 loops in 7.5 s.
  late final AnimationController _ctrl;

  /// Widget fade-in on first appearance (200 ms, delayed 400 ms).
  late final AnimationController _fadeCtrl;

  /// Player-dot fade-out triggered when _ctrl completes (300 ms).
  late final AnimationController _playerFadeCtrl;

  // ── Fortify route — 6 real-GPS waypoints, closed loop ─────────────────────
  static const _kFortifyRoute = [
    LatLng(39.46123804583449, -0.3765349555679282),
    LatLng(39.46103302303833, -0.376402178394288),
    LatLng(39.461582855538815, -0.3752071838315262),
    LatLng(39.46262659342135, -0.37593142296047277),
    LatLng(39.46213268369572, -0.3771747001318311),
    LatLng(39.46105166149929, -0.37637803708998985),
  ];

  // Fortified polygon — the territory being reinforced.
  static const _kDisputedCoords = [
    LatLng(39.4616, -0.3768), // B — NW
    LatLng(39.4616, -0.3752), // E — NE
    LatLng(39.4604, -0.3760), // F — SE
    LatLng(39.4611, -0.3764), // G — SW interior
  ];

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _claimedChunk = [];
  List<Offset> _routePts = [];
  int _level = 1;

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
      _claimedChunk = _kDisputedCoords.map(toScreen).toList();
      _routePts = _kFortifyRoute.map(toScreen).toList();
    });
  }

  void _onTick() {
    final newLevel = (((_ctrl.value * 15).floor() + 1).clamp(1, 15));
    if (newLevel != _level) {
      setState(() => _level = newLevel);
    }
  }

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _playerFadeCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7500),
    );

    // Widget fade-in.
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });

    // Level updates on each animation tick.
    _ctrl.addListener(_onTick);

    // When the 15-loop animation finishes, start the player-dot fade-out.
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) _playerFadeCtrl.forward();
      }
    });

    loopController(_ctrl, mounted: () => mounted);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
    _playerFadeCtrl.dispose();
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
            center: const LatLng(39.4614, -0.3762),
            zoom: 16.0,
            onReady: _onMapReady,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: Listenable.merge([_ctrl, _playerFadeCtrl]),
              builder: (_, __) {
                final zoom = mapCtrl.camera.zoom;
                final lat = mapCtrl.camera.center.latitudeInRad;
                const earthCircumference = 2 * math.pi * 6378137.0;
                final metersPerPx = (earthCircumference * math.cos(lat)) /
                    (256.0 * math.pow(2.0, zoom));
                final tailPx =
                    (_ctrl.value * kIntroRouteEstimatedMeters)
                            .clamp(0.0, kCometTailMaxMeters) /
                        metersPerPx;
                return CustomPaint(
                  painter: _IntroFortifyMapPainter(
                    t: _ctrl.value,
                    level: _level,
                    playerFade: _playerFadeCtrl.value,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    claimedChunk: _claimedChunk,
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
  final int level;

  /// 0.0 = player fully visible; 1.0 = player fully faded.
  final double playerFade;

  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> claimedChunk;
  final List<Offset> routePts;
  final double tailLengthPx;

  _IntroFortifyMapPainter({
    required this.t,
    required this.level,
    required this.playerFade,
    required this.accent,
    required this.inheritedPts,
    required this.claimedChunk,
    required this.routePts,
    required this.tailLengthPx,
  });

  static const int _kTotalLaps = 15;

  Offset _chunkCentroid() {
    if (claimedChunk.isEmpty) return Offset.zero;
    double sumX = 0, sumY = 0;
    for (final pt in claimedChunk) {
      sumX += pt.dx;
      sumY += pt.dy;
    }
    return Offset(sumX / claimedChunk.length, sumY / claimedChunk.length);
  }

  /// NW-most vertex: maximises (lat - lng) in LatLng space, which in screen
  /// space corresponds to the vertex that is most upper-left. We approximate
  /// this as minimising (dx + dy) in screen-space (smaller x+y = upper-left).
  Offset _nwVertex() {
    if (claimedChunk.isEmpty) return Offset.zero;
    Offset nw = claimedChunk[0];
    for (final pt in claimedChunk) {
      if (pt.dx + pt.dy < nw.dx + nw.dy) nw = pt;
    }
    return nw;
  }

  /// Arc-length interpolation along a closed polyline.
  Offset _posOnClosedLoop(List<Offset> pts, double frac) {
    if (pts.isEmpty) return Offset.zero;
    if (pts.length == 1) return pts[0];
    final segCount = pts.length; // closed: last→first is the nth segment
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
    return pts[0]; // wrapped back to start
  }

  void _drawPulseRing(Canvas canvas, Offset center, double t, Color color) {
    final pulseT = (math.sin(t * math.pi * 4) + 1) / 2;
    canvas.drawCircle(
      center,
      20 + pulseT * 12,
      Paint()
        ..color = color.withValues(alpha: (1.0 - pulseT) * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (claimedChunk.isEmpty) return;

    // 0. Inherited orange blocks — static base.
    drawInheritedBlocks(canvas, inheritedPts);

    // 1. Claimed chunk — kSea fill. Opacity ramps with level 1→15.
    final fillOpacity = 0.15 + (level / _kTotalLaps.toDouble()) * 0.65;
    drawFillColor(canvas, claimedChunk, kSea, fillOpacity);

    // 2. Halo on route circuit — grows with level.
    if (routePts.length >= 2) {
      final haloOpacity = 0.20 + (level / _kTotalLaps.toDouble()) * 0.65;
      final haloStroke = 1.0 + (level / _kTotalLaps.toDouble()) * 4.0;
      final loopPath = Path()..moveTo(routePts[0].dx, routePts[0].dy);
      for (int i = 1; i < routePts.length; i++) {
        loopPath.lineTo(routePts[i].dx, routePts[i].dy);
      }
      loopPath.close();
      canvas.drawPath(
        loopPath,
        Paint()
          ..color = kSea.withValues(alpha: haloOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = haloStroke
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 3. NW influence level label — visible from t=0, updates each frame.
    if (claimedChunk.isNotEmpty) {
      final nw = _nwVertex();
      final centroid = _chunkCentroid();
      // Nudge 18% from NW corner toward centroid — guaranteed inside polygon.
      final labelPos = nw + (centroid - nw) * 0.18;
      final tp = TextPainter(
        text: TextSpan(
          text: '$level',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'BebasNeue',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }

    // 4. Comet-tail trace for the active runner.
    if (routePts.length >= 2 && playerFade < 1.0) {
      final lapPos = (t * _kTotalLaps) % 1.0;
      // Closed polyline: append first point so the comet wraps around.
      final closedRoute = [...routePts, routePts[0]];
      drawComet(canvas, closedRoute, lapPos,
          tailLengthPx: tailLengthPx,
          color: kSea,
          decayMul: 1.0 - playerFade);
    }

    // 5. Runner dot — fades out after last loop via playerFade.
    if (playerFade < 1.0 && routePts.isNotEmpty) {
      final lapPos = (t * _kTotalLaps) % 1.0;
      final runnerPos = _posOnClosedLoop(routePts, lapPos);
      final dotAlpha = 1.0 - playerFade;
      canvas.drawCircle(
          runnerPos,
          10,
          Paint()
            ..color = kSea.withValues(alpha: 0.2 * dotAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(
          runnerPos, 4, Paint()..color = kSea.withValues(alpha: dotAlpha));
      canvas.drawCircle(
          runnerPos,
          1.5,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85 * dotAlpha));
    }

    // 6. At max level (15): pulse ring + "FORTIFIED" label.
    if (level >= _kTotalLaps) {
      final centroid = _chunkCentroid();
      _drawPulseRing(canvas, centroid, t, kSea);

      final fortOpacity = ((t * 4) % 1.0 < 0.5)
          ? ((t * 4) % 1.0) * 2.0
          : (1.0 - ((t * 4) % 1.0)) * 2.0;
      if (fortOpacity > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'FORTIFIED',
            style: GoogleFonts.bebasNeue(
              fontSize: 16,
              color: kSea.withValues(alpha: fortOpacity.clamp(0.0, 1.0)),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(centroid.dx - tp.width / 2, centroid.dy + 24));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroFortifyMapPainter old) =>
      old.t != t ||
      old.level != level ||
      old.playerFade != playerFade ||
      old.tailLengthPx != tailLengthPx ||
      old.claimedChunk != claimedChunk ||
      old.routePts != routePts;
}
