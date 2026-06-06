import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 4. IntroFlagDropMap — 3 runners race to L'Hemisfèric drop point (slide 4)
//
// Drop point: LatLng(39.4553, -0.3510) — L'Hemisfèric, Ciutat de les Arts
// Map center: LatLng(39.4540, -0.3520), zoom 14
//
// Runner A (kAccent orange)  — north start, runs south along Av. de França
// Runner B (kSea blue)       — northwest start near Ruzafa, runs east
// Runner C (pink 0xFFFF3B7A) — east start near port, runs west
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
  static const _kDropCoord = LatLng(39.4710, -0.3712);

  // Routes: 3 runners converge on Plaça de la Porta de la Mar roundabout
  // from south (Comte d'Altea), east (Colom/Port), and north (Navarro Reverter).
  // All waypoints lie on real street centerlines ~150–200m from the roundabout.

  // Runner A (kAccent orange) — from south via Carrer del Comte d'Altea
  // Starts ~200m south, runs north along Comte d'Altea toward the roundabout.
  static const _kRouteA = [
    LatLng(39.4689, -0.3712), // 0: off-screen south start
    LatLng(39.4695, -0.3712), // 1: Comte d'Altea heading north
    LatLng(39.4701, -0.3713), // 2: approaching roundabout
    LatLng(39.4706, -0.3712), // 3: roundabout south entry
    LatLng(39.4710, -0.3712), // 4: DROP POINT — roundabout center
  ];

  // Runner B (kSea blue) — from east via Carrer de Colom / Avinguda del Port
  // Starts ~200m east, runs west along Colom toward the roundabout.
  static const _kRouteB = [
    LatLng(39.4710, -0.3690), // 0: off-screen east start
    LatLng(39.4710, -0.3697), // 1: Colom heading west
    LatLng(39.4710, -0.3703), // 2: mid stretch
    LatLng(39.4710, -0.3708), // 3: roundabout east entry
    LatLng(39.4710, -0.3712), // 4: DROP POINT
  ];

  // Runner C (pink-red 0xFFFF3B7A) — from north via Carrer de Navarro Reverter
  // Starts ~180m north, runs south toward the roundabout.
  static const _kRouteC = [
    LatLng(39.4728, -0.3712), // 0: off-screen north start
    LatLng(39.4723, -0.3712), // 1: Navarro Reverter heading south
    LatLng(39.4718, -0.3712), // 2: mid stretch
    LatLng(39.4714, -0.3712), // 3: roundabout north entry
    LatLng(39.4710, -0.3712), // 4: DROP POINT
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
            center: const LatLng(39.46875, -0.3712),
            zoom: 17.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => CustomPaint(
                  painter: _IntroFlagDropMapPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    dropPt: _dropPt,
                    routeA: _routeA,
                    routeB: _routeB,
                    routeC: _routeC,
                  ),
                  child: const SizedBox.expand(),
                ),
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

  _IntroFlagDropMapPainter({
    required this.t,
    required this.accent,
    required this.dropPt,
    required this.routeA,
    required this.routeB,
    required this.routeC,
  });

  // ── Timeline constants ─────────────────────────────────────────────────────
  // t 0.00–0.30 : runners appear + pulse at start positions
  // t 0.00–0.75 : all 3 runners move along routes (staggered arrivals)
  //   A arrives t=0.65, B arrives t=0.70, C arrives t=0.75
  // t 0.50      : beacon starts pulsing at drop (kAccent2 rings)
  // t 0.65      : Runner A arrives — "LOOT DROPPED" label flashes
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

  void _drawRouteTrace(Canvas canvas, List<Offset> pts, double progress,
      Color color, double fade) {
    if (pts.isEmpty || fade <= 0) return;
    final segs = pts.length - 1;
    final totalLen = progress.clamp(0.0, 1.0) * segs;
    final p = Paint()
      ..color = color.withValues(alpha: 0.65 * fade)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < segs; i++) {
      if (totalLen > i) {
        final segT = (totalLen - i).clamp(0.0, 1.0);
        final pt = Offset.lerp(pts[i], pts[i + 1], segT)!;
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(path, p);
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

    _drawRouteTrace(canvas, routeA, progressA, kAccent, fade);
    _drawRouteTrace(canvas, routeB, progressB, kSea, fade);
    _drawRouteTrace(canvas, routeC, progressC, kRunnerCPink, fade);

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

    // ── 5. Runner A arrives (t=0.65) — arrival burst + "LOOT DROPPED" ────────
    _drawArrivalBurst(canvas, _arrivalA, fade);
    if (t > _arrivalA && t < 0.80) {
      final lootOpacity = t < 0.725
          ? ((t - _arrivalA) / 0.075).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.725) / 0.075)).clamp(0.0, 1.0);
      _drawLabel(
        canvas,
        'LOOT DROPPED',
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
      old.dropPt != dropPt ||
      old.routeA != routeA ||
      old.routeB != routeB ||
      old.routeC != routeC;
}
