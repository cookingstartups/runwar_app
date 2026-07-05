import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 7. IntroFlagDropMap — flag drops at the City of Arts and Sciences, 3
//    runners race in from real Valencia streets (slide 7)
//
// Drop point: LatLng(39.457074305497436, -0.35217545801606326) — the
// esplanade at the Museu de les Ciències Príncipe Felipe.
// Camera: initializes at zoom 16 centered on the drop, eases out to 15.5
// over ~1.2s of each loop so the three converging routes come into frame.
//
// Runner A (kAccent orange)  — NW, via the Jardí del Túria riverbed path and
//   Pont de Montolivet.
// Runner B (kSea blue)       — NE, via Avinguda de França and Pont de
//   l'Assut de l'Or.
// Runner C (kRunnerCPink)    — S, via Avinguda d'Amado Granell Mesado and
//   Carrer d'Eduardo Primo Yúfera.
//
// Camera story order: the flag lands (translate + bounce + shockwave ring)
// before any runner comet advances — gated by _kFlagLandT.
// ---------------------------------------------------------------------------

class IntroFlagDropMap extends StatefulWidget {
  final Color accent;
  const IntroFlagDropMap({required this.accent, super.key});
  @override
  State<IntroFlagDropMap> createState() => _IntroFlagDropMapState();
}

class _IntroFlagDropMapState extends State<IntroFlagDropMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroFlagDropMap> {
  // ── Fixed coordinates ──────────────────────────────────────────────────────
  static const _kDropCoord =
      LatLng(39.457074305497436, -0.35217545801606326);

  // Camera: drop at zoom 16, ease out to 15.5 over the first ~1.2s of the 5s
  // loop (operator-locked D3, option B — ease-out, not a static hold).
  static const double _kZoomStart = 16.0;
  static const double _kZoomEnd = 15.5;
  static const double _kZoomEaseSeconds = 1.2;
  static const double _kLoopSeconds = 5.0;
  static const double _kZoomEaseFrac = _kZoomEaseSeconds / _kLoopSeconds;

  // Camera story order: flag lands (bounce + shockwave) fully before any
  // runner comet begins advancing. All three _runnerProgress() calls are
  // clamped to 0 below this fraction of the loop — see the painter's own
  // _kFlagLandT constant below, which is the one actually referenced.

  // Routes: 3 runners converge on the Museu de les Ciències esplanade.
  // Waypoints fetched via the /gps-streets skill (Overpass API, OSM data,
  // 2026-07-04) — a handful of connector points bridging gaps between two
  // verified named-street segments are marked "interpolated" below; every
  // other point is a real OSM node.

  // Runner A (kAccent orange) — NW approach via the Jardí del Túria riverbed
  // path, crossing the river on Pont de Montolivet, then onto the esplanade.
  static const _kRouteA = [
    LatLng(39.4662369, -0.3620171), // 0: off-screen NW — Circuit 5K Jardí del Túria (OSM way 964690388)
    LatLng(39.4633274, -0.3601853), // 1: riverbed path, continuing SE (same OSM way)
    LatLng(39.4609500, -0.3575000), // 2: riverbed corridor toward the bridge (interpolated)
    LatLng(39.4596231, -0.3538958), // 3: Pont de Montolivet — north bank (OSM way 738981373)
    LatLng(39.4567151, -0.3552334), // 4: Pont de Montolivet — south bank, crossing complete (OSM way 738981369)
    LatLng(39.457074305497436, -0.35217545801606326), // 5: DROP POINT
  ];

  // Runner B (kSea blue) — NE approach via Avinguda de França, crossing the
  // river on Pont de l'Assut de l'Or, then along the pool edge.
  static const _kRouteB = [
    LatLng(39.4584521, -0.3441403), // 0: off-screen NE — Avinguda de França (OSM way 23454492)
    LatLng(39.4593793, -0.3484329), // 1: Avinguda de França, approaching the crossing (OSM way 12767382)
    LatLng(39.4595479, -0.3482330), // 2: Avinguda de França — link toward the bridge (OSM way 115600549)
    LatLng(39.4559562, -0.3481749), // 3: Pont de l'Assut de l'Or — north bank (OSM way 23446727)
    LatLng(39.4537908, -0.3512359), // 4: Pont de l'Assut de l'Or — south bank (OSM way 117809803)
    LatLng(39.4552000, -0.3517000), // 5: pool-edge esplanade, heading west (interpolated)
    LatLng(39.457074305497436, -0.35217545801606326), // 6: DROP POINT
  ];

  // Runner C (kRunnerCPink) — S approach via Avinguda d'Amado Granell
  // Mesado, then Carrer d'Eduardo Primo Yúfera onto the esplanade.
  static const _kRouteC = [
    LatLng(39.4506227, -0.3585243), // 0: off-screen S — Avinguda d'Amado Granell Mesado (OSM way 12658078)
    LatLng(39.4539934, -0.3612127), // 1: Avinguda d'Amado Granell Mesado, NE end (OSM way 12658078)
    LatLng(39.4535000, -0.3560000), // 2: connector toward Eduardo Primo Yúfera (interpolated)
    LatLng(39.4531470, -0.3512529), // 3: Carrer d'Eduardo Primo Yúfera — west end (OSM way 437056169)
    LatLng(39.4525944, -0.3491089), // 4: Carrer d'Eduardo Primo Yúfera — east end (OSM way 143066563)
    LatLng(39.4545000, -0.3505000), // 5: esplanade approach, heading N (interpolated)
    LatLng(39.457074305497436, -0.35217545801606326), // 6: DROP POINT
  ];

  // ── State ──────────────────────────────────────────────────────────────────
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  List<Offset> _routeA = [];
  List<Offset> _routeB = [];
  List<Offset> _routeC = [];
  Offset _dropPt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
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
      _routeA = _kRouteA.map(toScreen).toList();
      _routeB = _kRouteB.map(toScreen).toList();
      _routeC = _kRouteC.map(toScreen).toList();
      _dropPt = toScreen(_kDropCoord);
    });
  }

  /// Zoom 16 -> 15.5 ease-out over the first _kZoomEaseSeconds of each loop.
  /// Single tween driven by the existing _ctrl — no second listener.
  double _zoomForT(double t) {
    final zoomT = (t / _kZoomEaseFrac).clamp(0.0, 1.0);
    return _kZoomStart -
        (_kZoomStart - _kZoomEnd) * Curves.easeOut.transform(zoomT);
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
            center: _kDropCoord,
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  // Ease the camera out from 16 to 15.5 as the flag lands and
                  // the three routes converge into frame (R-16).
                  mapCtrl.move(_kDropCoord, _zoomForT(_ctrl.value));

                  final zoom = mapCtrl.camera.zoom;
                  final lat = mapCtrl.camera.center.latitudeInRad;
                  const earthCircumference = 2 * math.pi * 6378137.0;
                  final metersPerPx = (earthCircumference * math.cos(lat)) /
                      (256.0 * math.pow(2.0, zoom));
                  final tailPx = (_ctrl.value * kIntroRouteEstimatedMeters).clamp(0.0, kCometTailMaxMeters) / metersPerPx;
                  return CustomPaint(
                    painter: _IntroFlagDropMapPainter(
                      t: _ctrl.value,
                      accent: widget.accent,
                      dropPt: _dropPt,
                      routeA: _routeA,
                      routeB: _routeB,
                      routeC: _routeC,
                      tailLengthPx: tailPx,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _IntroFlagDropMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final Offset dropPt;
  final List<Offset> routeA;
  final List<Offset> routeB;
  final List<Offset> routeC;
  final double tailLengthPx;

  _IntroFlagDropMapPainter({
    required this.t,
    required this.accent,
    required this.dropPt,
    required this.routeA,
    required this.routeB,
    required this.routeC,
    required this.tailLengthPx,
  });

  // ── Timeline constants ─────────────────────────────────────────────────────
  // t 0.00–0.15 : flag falls + bounces onto the drop point (_kFlagLandT gate)
  // t 0.15      : shockwave ring fires; ONLY NOW do runner comets begin
  // t 0.15–0.80 : all 3 runners move along routes (staggered arrivals)
  //   A arrives t=0.65, B arrives t=0.70, C arrives t=0.75
  // t 0.50      : beacon starts pulsing at drop (ambient, kAccent2 rings)
  // t 0.65      : Runner A arrives — "FLAG DROPPED" label flashes
  // t 0.70      : Runner B arrives — white burst ring
  // t 0.75      : Runner C arrives — "SPRINT!" tag briefly
  // t 0.80–1.00 : all runners at drop, rings decay, global fade-out

  static const double _kFlagLandT = 0.15;
  static const double _arrivalA = 0.65;
  static const double _arrivalB = 0.70;
  static const double _arrivalC = 0.75;
  static const double _beaconStart = 0.50;
  static const double _fadeStart = 0.80;

  // ── Helpers ────────────────────────────────────────────────────────────────

  double _globalFade() {
    if (t < _fadeStart) return 1.0;
    return (1.0 - (t - _fadeStart) / (1.0 - _fadeStart)).clamp(0.0, 1.0);
  }

  /// Returns runner progress (0–1) along its route, clamped at arrival.
  /// Gated by _kFlagLandT (R-18): runners do not move until the flag has
  /// landed, mirroring the existing startT-clamp pattern in this file.
  double _runnerProgress(double arrivalT) {
    if (t >= arrivalT) return 1.0;
    const startT = _kFlagLandT;
    if (t < startT) return 0.0;
    return ((t - startT) / (arrivalT - startT)).clamp(0.0, 1.0);
  }

  /// Returns Offset position along a route list at fractional progress p.
  Offset _posOnRoute(List<Offset> pts, double p) {
    if (pts.isEmpty) return Offset.zero;
    final segs = pts.length - 1;
    final totalLen = p.clamp(0.0, 1.0) * segs;
    final segIdx = totalLen.floor().clamp(0, segs - 1);
    final segFrac = (totalLen - segIdx).clamp(0.0, 1.0);
    return Offset.lerp(pts[segIdx], pts[(segIdx + 1).clamp(0, segs)], segFrac)!;
  }

  void _drawRunnerDot(Canvas canvas, Offset pos, Color color, double fade) {
    if (fade <= 0) return;
    canvas.drawCircle(
        pos,
        12,
        Paint()
          ..color = color.withValues(alpha: 0.22 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(pos, 4.5, Paint()..color = color.withValues(alpha: fade));
    canvas.drawCircle(
        pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.85 * fade));
  }

  void _drawLabel(Canvas canvas, String text, Offset center, Color color,
      double opacity) {
    if (opacity <= 0) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 2,
          color: color.withValues(alpha: opacity),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  // ── Flag drop: translate + bounce + shockwave (t 0.00–0.15, R-18) ─────────
  // The flag falls from above the drop point and settles with a slight
  // overshoot bounce, landing exactly at _kFlagLandT — establishing the
  // prize before any runner comet is allowed to move.
  void _drawFlagDrop(Canvas canvas) {
    final landT = (t / _kFlagLandT).clamp(0.0, 1.0);
    // Overshoot-then-settle curve so the flag "bounces" onto the point.
    final eased = Curves.easeOutBack.transform(landT);
    const startOffsetY = -46.0;
    final flagY = dropPt.dy + startOffsetY * (1.0 - eased);
    final flagBase = Offset(dropPt.dx, flagY);

    // Pole + pennant.
    final poleTop = flagBase.translate(0, -22);
    canvas.drawLine(
      flagBase,
      poleTop,
      Paint()
        ..color = kAccent2
        ..strokeWidth = 2.5,
    );
    final pennant = Path()
      ..moveTo(poleTop.dx, poleTop.dy)
      ..lineTo(poleTop.dx + 16, poleTop.dy + 5)
      ..lineTo(poleTop.dx, poleTop.dy + 10)
      ..close();
    canvas.drawPath(pennant, Paint()..color = kAccent2);
    canvas.drawCircle(flagBase, 3.5, Paint()..color = kAccent2);

    // Shockwave ring — fires once the flag has landed (t >= _kFlagLandT).
    if (t >= _kFlagLandT) {
      final shockT = ((t - _kFlagLandT) / 0.10).clamp(0.0, 1.0);
      if (shockT < 1.0) {
        canvas.drawCircle(
            dropPt,
            shockT * 46,
            Paint()
              ..color = kAccent2.withValues(alpha: (1.0 - shockT) * 0.65)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      }
    }
  }

  // Start-position pulse: visible once runners are allowed to move
  // (t=_kFlagLandT) through the first 0.30 fraction of the loop.
  void _drawStartPulse(Canvas canvas, Offset pos, Color color) {
    if (t < _kFlagLandT || t >= 0.30) return;
    final pulseT = ((t - _kFlagLandT) / (0.30 - _kFlagLandT)).clamp(0.0, 1.0);
    final radius = pulseT * 22;
    canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = color.withValues(alpha: (1.0 - pulseT) * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  // ── Beacon at drop point ───────────────────────────────────────────────────
  void _drawBeacon(Canvas canvas, double fade) {
    if (t < _beaconStart || fade <= 0) return;
    final beaconT = (t - _beaconStart) / (1.0 - _beaconStart);
    final pulseBase = (math.sin(beaconT * math.pi * 6) + 1) / 2;

    // Central glowing dot.
    canvas.drawCircle(
        dropPt,
        6 + pulseBase * 3,
        Paint()
          ..color = kAccent2.withValues(alpha: 0.18 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(
        dropPt, 5, Paint()..color = kAccent2.withValues(alpha: 0.9 * fade));
    canvas.drawCircle(
        dropPt, 2, Paint()..color = Colors.white.withValues(alpha: 0.9 * fade));

    // 3 concentric ring pulses.
    for (int i = 0; i < 3; i++) {
      final delay = i * 0.18;
      final ringProgress = ((beaconT - delay) / 0.54).clamp(0.0, 1.0);
      if (ringProgress > 0) {
        canvas.drawCircle(
            dropPt,
            ringProgress * 55,
            Paint()
              ..color = kAccent2.withValues(alpha: (1.0 - ringProgress) * 0.50 * fade)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
    }
  }

  // White burst ring when a runner arrives.
  void _drawArrivalBurst(Canvas canvas, double arrivalT, double fade) {
    if (t < arrivalT || fade <= 0) return;
    final burstT = ((t - arrivalT) / 0.08).clamp(0.0, 1.0);
    if (burstT >= 1.0) return;
    canvas.drawCircle(
        dropPt,
        burstT * 60,
        Paint()
          ..color = Colors.white.withValues(alpha: (1.0 - burstT) * 0.55 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (routeA.isEmpty) return;

    final fade = _globalFade();

    // ── 1. Flag drop — lands first, establishes the prize (R-18) ───────────
    _drawFlagDrop(canvas);

    // ── 2. Start-position pulses (only once runners are allowed to move) ───
    _drawStartPulse(canvas, routeA.first, kAccent);
    _drawStartPulse(canvas, routeB.first, kSea);
    _drawStartPulse(canvas, routeC.first, kRunnerCPink);

    // ── 3. Runner traces ─────────────────────────────────────────────────────
    final progressA = _runnerProgress(_arrivalA);
    final progressB = _runnerProgress(_arrivalB);
    final progressC = _runnerProgress(_arrivalC);

    drawComet(canvas, routeA, progressA,
        tailLengthPx: tailLengthPx, color: kAccent, decayMul: fade);
    drawComet(canvas, routeB, progressB,
        tailLengthPx: tailLengthPx, color: kSea, decayMul: fade);
    drawComet(canvas, routeC, progressC,
        tailLengthPx: tailLengthPx, color: kRunnerCPink, decayMul: fade);

    // ── 4. Runner dots ───────────────────────────────────────────────────────
    // Show dot while en route; once arrived hold at drop point until fade.
    final posA = progressA < 1.0 ? _posOnRoute(routeA, progressA) : dropPt;
    final posB = progressB < 1.0 ? _posOnRoute(routeB, progressB) : dropPt;
    final posC = progressC < 1.0 ? _posOnRoute(routeC, progressC) : dropPt;

    // Only draw runner if before arrival or if still fading out post-arrival.
    _drawRunnerDot(canvas, posA, kAccent, fade);
    _drawRunnerDot(canvas, posB, kSea, fade);
    _drawRunnerDot(canvas, posC, kRunnerCPink, fade);

    // ── 5. Beacon at drop point (t=0.50+) ────────────────────────────────────
    _drawBeacon(canvas, fade);

    // ── 6. Runner A arrives (t=0.65) — arrival burst + "FLAG DROPPED" ────────
    _drawArrivalBurst(canvas, _arrivalA, fade);
    if (t > _arrivalA && t < 0.80) {
      final lootOpacity = t < 0.725
          ? ((t - _arrivalA) / 0.075).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.725) / 0.075)).clamp(0.0, 1.0);
      _drawLabel(
        canvas,
        'FLAG DROPPED',
        dropPt.translate(0, -28),
        kAccent2,
        lootOpacity * fade,
      );
    }

    // ── 7. Runner B arrives (t=0.70) — white burst ring ──────────────────────
    _drawArrivalBurst(canvas, _arrivalB, fade);

    // ── 8. Runner C arrives (t=0.75) — "SPRINT!" tag briefly near route ──────
    _drawArrivalBurst(canvas, _arrivalC, fade);
    if (t > _arrivalC && t < 0.90) {
      final sprintOpacity = t < 0.825
          ? ((t - _arrivalC) / 0.075).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.825) / 0.075)).clamp(0.0, 1.0);
      // Place tag slightly offset from where runner C came from (south).
      final sprintPos = routeC.length >= 2
          ? routeC[routeC.length - 2].translate(18, -12)
          : dropPt.translate(28, -12);
      _drawLabel(canvas, 'SPRINT!', sprintPos, kRunnerCPink,
          sprintOpacity * fade);
    }
  }

  @override
  bool shouldRepaint(_IntroFlagDropMapPainter old) =>
      old.t != t ||
      old.tailLengthPx != tailLengthPx ||
      old.dropPt != dropPt ||
      old.routeA != routeA ||
      old.routeB != routeB ||
      old.routeC != routeC;
}
