import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 4. IntroFlagDropMap — 3 runners race to Alameda Metro south exit (slide 4)
//
// Drop point: LatLng(39.47140, -0.36490) — Estació de l'Alameda south exit
// Map center: LatLng(39.47140, -0.36490), zoom 16
//
// Runner A (kAccent orange)  — north start, via Pont de l'Exposició / Av d'Aragó
// Runner B (kSea blue)       — west start, via Jardí del Túria riverbed corridor
// Runner C (kRunnerCPink)    — south start, via Carrer de Menorca heading north
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
  static const _kDropCoord = LatLng(39.47140, -0.36490);

  // Routes: 3 runners converge on Alameda Metro south exit.
  // All waypoints lie on real Valencia street centrelines confirmed against OSM.

  // Runner A (kAccent orange) — north approach via Pont de l'Exposició / Av d'Aragó
  // Starts ~1.6 km north (off-screen at zoom 16), crosses Pont de l'Exposició,
  // descends Avinguda d'Aragó south to the Alameda south exit.
  static const _kRouteA = [
    LatLng(39.48600, -0.36490), // 0: off-screen north start (~1623 m from drop)
    LatLng(39.48300, -0.36490), // 1: approaching Pont de l'Exposició from north
    LatLng(39.47970, -0.36490), // 2: Pont de l'Exposició — bridge over Turia
    LatLng(39.47750, -0.36490), // 3: Avinguda d'Aragó heading south
    LatLng(39.47500, -0.36490), // 4: continuing south on Av d'Aragó
    LatLng(39.47300, -0.36490), // 5: near Alameda metro north approach
    LatLng(39.47140, -0.36490), // 6: DROP POINT — Alameda south exit
  ];

  // Runner B (kSea blue) — west approach via Jardí del Túria riverbed corridor
  // Starts ~1.7 km west (off-screen at zoom 16), runs east along the Turia park
  // pedestrian path, curves southeast into the Alameda south exit.
  static const _kRouteB = [
    LatLng(39.47300, -0.38500), // 0: off-screen west start (~1734 m from drop)
    LatLng(39.47300, -0.38100), // 1: Jardí del Túria — continuing east
    LatLng(39.47300, -0.37800), // 2: mid-park near Palau de la Música
    LatLng(39.47280, -0.37500), // 3: approaching Alameda from west
    LatLng(39.47260, -0.37200), // 4: near metro west approach
    LatLng(39.47200, -0.36800), // 5: turning southeast toward south exit
    LatLng(39.47140, -0.36490), // 6: DROP POINT — Alameda south exit
  ];

  // Runner C (kRunnerCPink) — south approach via Carrer de Menorca heading north
  // Starts ~1.2 km south (off-screen at zoom 16), runs north along Carrer de
  // Menorca directly into the Alameda Metro south exit.
  static const _kRouteC = [
    LatLng(39.46100, -0.36490), // 0: off-screen south start (~1156 m from drop)
    LatLng(39.46300, -0.36490), // 1: Carrer de Menorca heading north
    LatLng(39.46500, -0.36490), // 2: continuing north
    LatLng(39.46700, -0.36490), // 3: approaching metro area from south
    LatLng(39.46900, -0.36490), // 4: near Alameda south side
    LatLng(39.47050, -0.36490), // 5: close approach to south exit
    LatLng(39.47140, -0.36490), // 6: DROP POINT — Alameda south exit
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

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Stack(
        children: [
          buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.47360, -0.36490),
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
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
  // t 0.00–0.30 : runners appear + pulse at start positions
  // t 0.00–0.75 : all 3 runners move along routes (staggered arrivals)
  //   A arrives t=0.65, B arrives t=0.70, C arrives t=0.75
  // t 0.50      : beacon starts pulsing at drop (kAccent2 rings)
  // t 0.65      : Runner A arrives — "FLAG DROPPED" label flashes
  // t 0.70      : Runner B arrives — white burst ring
  // t 0.75      : Runner C arrives — "SPRINT!" tag briefly
  // t 0.80–1.00 : all runners at drop, rings decay, global fade-out

  // Per-runner movement: each runner travels from 0 to their arrival time.
  // After arrival they are clamped at the drop point.
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
  double _runnerProgress(double arrivalT) {
    if (t >= arrivalT) return 1.0;
    // Runners start moving at t=0.05 after initial pulse.
    const startT = 0.05;
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

  // Start-position pulse: visible in t=0.00–0.30.
  void _drawStartPulse(Canvas canvas, Offset pos, Color color) {
    if (t >= 0.30) return;
    final pulseT = (t / 0.30).clamp(0.0, 1.0);
    final radius = pulseT * 22;
    canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = color.withValues(alpha: (1.0 - pulseT) * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
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

    // ── 1. Start-position pulses (t=0.00–0.30) ──────────────────────────────
    _drawStartPulse(canvas, routeA.first, kAccent);
    _drawStartPulse(canvas, routeB.first, kSea);
    _drawStartPulse(canvas, routeC.first, kRunnerCPink);

    // ── 2. Runner traces ─────────────────────────────────────────────────────
    final progressA = _runnerProgress(_arrivalA);
    final progressB = _runnerProgress(_arrivalB);
    final progressC = _runnerProgress(_arrivalC);

    drawComet(canvas, routeA, progressA,
        tailLengthPx: tailLengthPx, color: kAccent, decayMul: fade);
    drawComet(canvas, routeB, progressB,
        tailLengthPx: tailLengthPx, color: kSea, decayMul: fade);
    drawComet(canvas, routeC, progressC,
        tailLengthPx: tailLengthPx, color: kRunnerCPink, decayMul: fade);

    // ── 3. Runner dots ───────────────────────────────────────────────────────
    // Show dot while en route; once arrived hold at drop point until fade.
    final posA = progressA < 1.0 ? _posOnRoute(routeA, progressA) : dropPt;
    final posB = progressB < 1.0 ? _posOnRoute(routeB, progressB) : dropPt;
    final posC = progressC < 1.0 ? _posOnRoute(routeC, progressC) : dropPt;

    // Only draw runner if before arrival or if still fading out post-arrival.
    _drawRunnerDot(canvas, posA, kAccent, fade);
    _drawRunnerDot(canvas, posB, kSea, fade);
    _drawRunnerDot(canvas, posC, kRunnerCPink, fade);

    // ── 4. Beacon at drop point (t=0.50+) ────────────────────────────────────
    _drawBeacon(canvas, fade);

    // ── 5. Runner A arrives (t=0.65) — arrival burst + "FLAG DROPPED" ────────
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

    // ── 6. Runner B arrives (t=0.70) — white burst ring ──────────────────────
    _drawArrivalBurst(canvas, _arrivalB, fade);

    // ── 7. Runner C arrives (t=0.75) — "SPRINT!" tag briefly near route ──────
    _drawArrivalBurst(canvas, _arrivalC, fade);
    if (t > _arrivalC && t < 0.90) {
      final sprintOpacity = t < 0.825
          ? ((t - _arrivalC) / 0.075).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.825) / 0.075)).clamp(0.0, 1.0);
      // Place tag slightly offset from where runner C came from (east).
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
