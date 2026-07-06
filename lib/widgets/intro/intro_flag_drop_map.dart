import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_ctf_trisection.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 7. IntroFlagDropMap - flag drops at Plaça de la Marató (the plaza fronting
//    L'Hemisfèric), the map trisects into 3 faction sectors, 3 runners lock
//    to a faction color and race in from real Valencia streets, first
//    arrival becomes the carrier and must run the flag to its own base while
//    a rival closes in for a steal attempt (slide 7).
//
// Stylized abbreviation of the real carry-and-return CTF mechanic - same
// short-loop visual economy as every other onboarding slide, not a literal
// chain-steal simulation.
//
// Drop point: LatLng(39.4567170, -0.3553929) - Plaça de la Marató, the
// pedestrian plaza at the south foot of Pont de Montolivet, directly
// fronting L'Hemisfèric across the reflecting pool. A real, shared OSM
// junction (way 12206878) - not an interpolated point.
//
// Camera: initializes at zoom 16, centered on _kCameraCenter - a point
// shifted north of the true drop coordinate so the drop point renders at
// the vertical center of the bottom half of the screen (clear of this
// slide's top-pinned tag/headline/body text), eases out to zoom 15.5 over
// ~1.2s of each 8s loop. The flag/routes still draw at the real _kDropCoord.
//
// Faction A (kSea blue)     - north, across Pont de Montolivet.
// Faction B (kRunnerCPink)  - southeast, Avinguda del Professor López
//   Piñero (the avenue L'Hemisfèric's own address sits on).
// Faction C (kLimeGreen)    - southwest, the same avenue's other
//   roundabout arm.
//
// Beat order (8s loop, normalized t 0.00–1.00):
//   0.00–0.18  trisection reveal    - 3 faction wedges fade in around the drop
//   0.18–0.45  faction color lock   - runners advance, already tinted
//   0.45–0.55  flag drop + capture  - flag lands, first arrival becomes carrier
//   0.55–0.62  base spawn           - carrier's base pops in; rivals show "?"
//   0.62–0.85  carry + steal        - carrier runs home, a rival closes in
//   0.85–1.00  hold + fade          - global fade-out, loop restarts
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
  // Plaça de la Marató - real, shared OSM junction (way 12206878) at the
  // south foot of Pont de Montolivet, directly fronting L'Hemisfèric.
  static const _kDropCoord = LatLng(39.4567170, -0.3553929);

  // Camera: drop at zoom 16, ease out to 15.5 over the first ~1.2s of the 8s
  // loop (same ease-out mechanic as before; loop length grew from 5s to 8s
  // to fit the new 6-beat structure).
  static const double _kZoomStart = 16.0;
  static const double _kZoomEnd = 15.5;
  static const double _kZoomEaseSeconds = 1.2;
  static const double _kLoopSeconds = 8.0;
  static const double _kZoomEaseFrac = _kZoomEaseSeconds / _kLoopSeconds;

  // Camera reframing - the drop point must render at the vertical center of
  // the bottom half of the screen, not full-screen center (this slide's
  // layout pins the tag/headline/body to the top). _kCameraCenter is
  // _kDropCoord shifted north by a fixed latitude delta, derived once at
  // mount time from the real screen height and the fixed zoom, so the map
  // centers elsewhere while the flag/beacon/routes still draw at the real
  // drop coordinate.
  static const double _kDropAnchorYFraction = 0.70;
  static const double _kMetersPerLatDegree = 111320.0;
  LatLng? _cameraCenter;

  LatLng _resolveCameraCenter(BuildContext context) {
    final cached = _cameraCenter;
    if (cached != null) return cached;
    final height = MediaQuery.sizeOf(context).height;
    final latRad = _kDropCoord.latitude * math.pi / 180.0;
    const earthCircumference = 2 * math.pi * 6378137.0;
    final metersPerPx = (earthCircumference * math.cos(latRad)) /
        (256.0 * math.pow(2.0, _kZoomStart));
    final dyPx = height * (_kDropAnchorYFraction - 0.5);
    final dyMeters = dyPx * metersPerPx;
    final dLatDeg = dyMeters / _kMetersPerLatDegree;
    final resolved =
        LatLng(_kDropCoord.latitude + dLatDeg, _kDropCoord.longitude);
    _cameraCenter = resolved;
    return resolved;
  }

  // Routes: 3 runners converge on Plaça de la Marató. All waypoints verified
  // real OSM nodes (Overpass API, 2026-07-06) - zero interpolated
  // connectors, an improvement over the superseded route set.

  // Faction A (kSea blue) - north approach, across Pont de Montolivet (the
  // bridge whose south landing is the plaza itself).
  static const _kRouteA = [
    LatLng(39.4596015, -0.3538110), // 0: off-screen N - Pont de Montolivet, north bank (OSM way 14362238)
    LatLng(39.4580320, -0.3544554), // 1: bridge span (OSM way 14362238)
    LatLng(39.4572324, -0.3550851), // 2: bridge span, approaching south bank (OSM way 14362238)
    LatLng(39.4569010, -0.3554983), // 3: Pont de Montolivet south landing (OSM way 14362238 / 14309842 shared node)
    LatLng(39.4567170, -0.3553929), // 4: DROP POINT - Plaça de la Marató (OSM way 12206878)
  ];

  // Faction B (kRunnerCPink) - southeast approach along Avinguda del
  // Professor López Piñero (the avenue L'Hemisfèric's own postal address
  // sits on).
  static const _kRouteB = [
    LatLng(39.4538975, -0.3520855), // 0: off-screen SE - Avinguda del Professor López Piñero (OSM way 12164350)
    LatLng(39.4543253, -0.3527726), // 1: avenue, continuing NW (OSM way 12164350)
    LatLng(39.4551182, -0.3539987), // 2: avenue, mid-span (OSM way 12164350)
    LatLng(39.4558789, -0.3551243), // 3: avenue, approaching the plaza (OSM way 12164350)
    LatLng(39.4564443, -0.3557174), // 4: avenue/plaza junction (OSM way 12164350, shared node w/ way 100780355)
    LatLng(39.4567170, -0.3553929), // 5: DROP POINT
  ];

  // Faction C (kLimeGreen) - southwest approach, the same avenue's other
  // roundabout arm (a real, distinct compass bearing, not a duplicate of B).
  static const _kRouteC = [
    LatLng(39.4539054, -0.3530441), // 0: off-screen S - Avinguda del Professor López Piñero, SW arm (OSM way 39734853)
    LatLng(39.4546061, -0.3541866), // 1: avenue, SW arm, mid-span (OSM way 39734853)
    LatLng(39.4553072, -0.3553569), // 2: avenue, SW arm, approaching plaza (OSM way 39734853)
    LatLng(39.4562169, -0.3561967), // 3: Plaça de la Marató, SW roundabout node (OSM way 39734853 / 100775034 shared node)
    LatLng(39.4565371, -0.3557189), // 4: Plaça de la Marató, connecting to the bridge foot (OSM way 100775034 / 98711540 / 12206878 shared node)
    LatLng(39.4567170, -0.3553929), // 5: DROP POINT
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
      duration: const Duration(seconds: 8),
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
    final cameraCenter = _resolveCameraCenter(context);
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Stack(
        children: [
          buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: cameraCenter,
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  // Ease the camera out from 16 to 15.5 as the loop plays -
                  // centered on _kCameraCenter, not the drop coordinate.
                  mapCtrl.move(cameraCenter, _zoomForT(_ctrl.value));

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

  // ── Timeline constants (8s loop, normalized t) ─────────────────────────────
  // t 0.00–0.18 : trisection reveal - 3 faction wedges fade in around dropPt
  // t 0.18–0.45 : faction color lock - runners advance, already tinted
  //   A (blue) arrives t=0.33, B (pink) arrives t=0.39, C (lime) arrives t=0.45
  // t 0.45–0.55 : flag drop + capture - flag falls/bounces, lands t=0.50;
  //   "FLAG DROPPED" flashes, then "CAPTURED" in the carrier's faction color
  // t 0.55–0.62 : base spawn - carrier's base pops in (visible); the other
  //   two factions' bases pop in as unlabeled "?" markers (base-secrecy rule)
  // t 0.62–0.85 : carry + steal - carrier runs home; the runner-up rival
  //   breaks off and closes in; INTERCEPT burst at t=0.80
  // t 0.85–1.00 : hold + fade - global fade-out, loop restarts

  static const double _kTrisectionEnd = 0.18;
  static const double _kLockStart = 0.18;
  static const double _arrivalA = 0.33; // faction blue - becomes carrier
  static const double _arrivalB = 0.39; // faction pink - becomes the interceptor
  static const double _arrivalC = 0.45; // faction lime
  static const double _kFlagDropStart = 0.45;
  static const double _kFlagFallFrac = 0.05; // fall + bounce duration
  static const double _kFlagLandT = _kFlagDropStart + _kFlagFallFrac; // 0.50
  static const double _kCapturedFlashEnd = 0.55;
  static const double _kBaseSpawnStart = 0.55;
  static const double _kBaseSpawnEnd = 0.62;
  static const double _kCarryStart = 0.62;
  static const double _kCarryEnd = 0.85;
  static const double _kInterceptT = 0.80;
  static const double _fadeStart = 0.85;

  static const double _kBaseRadiusPx = 78.0;
  static const double _kWedgeRadiusPx = 200.0;

  // ── Helpers ────────────────────────────────────────────────────────────────

  double _globalFade() {
    if (t < _fadeStart) return 1.0;
    return (1.0 - (t - _fadeStart) / (1.0 - _fadeStart)).clamp(0.0, 1.0);
  }

  /// Runner progress (0–1) along its route during the faction-lock beat,
  /// clamped at arrival. Movement starts at _kLockStart - the flag drop now
  /// happens AFTER the lock beat, unlike the superseded single-point
  /// mechanic where runners moved toward an already-landed flag.
  double _runnerProgress(double arrivalT) {
    if (t >= arrivalT) return 1.0;
    const startT = _kLockStart;
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

  // ── Flag drop: translate + bounce + shockwave (t 0.45–0.55) ───────────────
  // The flag falls onto the drop point after the faction-lock beat and holds
  // (with its shockwave ring) until capture is confirmed at _kCapturedFlashEnd
  // - same fall/bounce mechanic as the superseded file, re-anchored to this
  // later window.
  void _drawFlagDrop(Canvas canvas) {
    if (t < _kFlagDropStart || t >= _kCapturedFlashEnd) return;
    final landT = ((t - _kFlagDropStart) / _kFlagFallFrac).clamp(0.0, 1.0);
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

    // Shockwave ring - fires once the flag has landed.
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

  // Start-position pulse: visible for a short window once runners are
  // allowed to move (t=_kLockStart).
  void _drawStartPulse(Canvas canvas, Offset pos, Color color) {
    const windowEnd = _kLockStart + 0.15;
    if (t < _kLockStart || t >= windowEnd) return;
    final pulseT =
        ((t - _kLockStart) / (windowEnd - _kLockStart)).clamp(0.0, 1.0);
    final radius = pulseT * 22;
    canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = color.withValues(alpha: (1.0 - pulseT) * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  // White burst ring when a runner arrives at the drop point.
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

    // ── 1. Trisection wedges - sweep in, then hold as background overlay ───
    final revealScale = t < _kTrisectionEnd
        ? Curves.easeOut.transform((t / _kTrisectionEnd).clamp(0.0, 1.0))
        : 1.0;
    drawCtfTrisection(
      canvas,
      center: dropPt,
      radius: _kWedgeRadiusPx,
      revealScale: revealScale,
      opacity: fade,
    );

    // ── 2. Start-position pulses (faction-lock beat only) ───────────────────
    _drawStartPulse(canvas, routeA.first, kSea);
    _drawStartPulse(canvas, routeB.first, kRunnerCPink);
    _drawStartPulse(canvas, routeC.first, kLimeGreen);

    // ── 3. Faction color lock: runners advance already tinted ───────────────
    final progressA = _runnerProgress(_arrivalA);
    final progressB = _runnerProgress(_arrivalB);
    final progressC = _runnerProgress(_arrivalC);

    if (t < _kCarryStart) {
      drawComet(canvas, routeA, progressA,
          tailLengthPx: tailLengthPx, color: kSea, decayMul: fade);
      drawComet(canvas, routeB, progressB,
          tailLengthPx: tailLengthPx, color: kRunnerCPink, decayMul: fade);
      drawComet(canvas, routeC, progressC,
          tailLengthPx: tailLengthPx, color: kLimeGreen, decayMul: fade);
    }

    // Base offsets - fixed screen-space points inside each faction's own
    // wedge, one radius out from the drop point along its sector bearing.
    final carrierBase = dropPt + ctfFactionBlue.baseDirection * _kBaseRadiusPx;
    final pinkBase = dropPt + ctfFactionPink.baseDirection * _kBaseRadiusPx;
    final limeBase = dropPt + ctfFactionLime.baseDirection * _kBaseRadiusPx;
    final interceptPoint = Offset.lerp(dropPt, carrierBase, 0.55)!;

    // ── 4. Runner positions ──────────────────────────────────────────────────
    // Before the carry beat: en-route or holding at the drop point.
    // During the carry beat: carrier (A) runs to its base; the interceptor
    // (B) breaks off toward the point of closest approach; C holds.
    Offset posA, posB, posC;
    if (t < _kCarryStart) {
      posA = progressA < 1.0 ? _posOnRoute(routeA, progressA) : dropPt;
      posB = progressB < 1.0 ? _posOnRoute(routeB, progressB) : dropPt;
      posC = progressC < 1.0 ? _posOnRoute(routeC, progressC) : dropPt;
    } else {
      final carryT =
          ((t - _kCarryStart) / (_kCarryEnd - _kCarryStart)).clamp(0.0, 1.0);
      posA = Offset.lerp(dropPt, carrierBase, Curves.easeInOut.transform(carryT))!;
      const interceptWindow =
          (_kInterceptT - _kCarryStart) / (_kCarryEnd - _kCarryStart);
      final interceptT = (carryT / interceptWindow).clamp(0.0, 1.0);
      posB = Offset.lerp(
          dropPt, interceptPoint, Curves.easeOut.transform(interceptT))!;
      posC = dropPt;
    }

    // Carry-beat run-in trails (straight, replaces the route comet once the
    // runners have left their real-world streets and are running the last
    // stretch home through the sector).
    if (t >= _kCarryStart) {
      canvas.drawLine(dropPt, posA,
          Paint()..color = kSea.withValues(alpha: 0.5 * fade)..strokeWidth = 2.0);
      canvas.drawLine(dropPt, posB,
          Paint()
            ..color = kRunnerCPink.withValues(alpha: 0.5 * fade)
            ..strokeWidth = 2.0);
    }

    // ── 5. Runner dots ───────────────────────────────────────────────────────
    _drawRunnerDot(canvas, posA, kSea, fade);
    _drawRunnerDot(canvas, posB, kRunnerCPink, fade);
    _drawRunnerDot(canvas, posC, kLimeGreen, fade);

    // ── 6. Flag drop + capture (t 0.45–0.55) ─────────────────────────────────
    _drawFlagDrop(canvas);
    _drawArrivalBurst(canvas, _arrivalA, fade);
    if (t >= _kFlagLandT && t < _kFlagLandT + 0.03) {
      final op = ((t - _kFlagLandT) / 0.015).clamp(0.0, 1.0);
      _drawLabel(canvas, 'FLAG DROPPED', dropPt.translate(0, -34), kAccent2,
          op * fade);
    } else if (t >= _kFlagLandT + 0.03 && t < _kCapturedFlashEnd) {
      const windowStart = _kFlagLandT + 0.03;
      final op = t < windowStart + 0.01
          ? ((t - windowStart) / 0.01).clamp(0.0, 1.0)
          : (1.0 -
                  (t - (windowStart + 0.01)) /
                      (_kCapturedFlashEnd - windowStart - 0.01))
              .clamp(0.0, 1.0);
      _drawLabel(canvas, 'CAPTURED', dropPt.translate(0, -34), kSea, op * fade);
    }

    // ── 7. Base spawn (t 0.55–0.62) ──────────────────────────────────────────
    if (t >= _kBaseSpawnStart) {
      final spawnScale = t < _kBaseSpawnEnd
          ? Curves.easeOutBack.transform(
              ((t - _kBaseSpawnStart) / (_kBaseSpawnEnd - _kBaseSpawnStart))
                  .clamp(0.0, 1.0))
          : 1.0;
      drawCtfBaseMarker(canvas, carrierBase, kSea, spawnScale * fade,
          revealed: true);
      drawCtfBaseMarker(canvas, pinkBase, kFgMuted, spawnScale * fade,
          revealed: false);
      drawCtfBaseMarker(canvas, limeBase, kFgMuted, spawnScale * fade,
          revealed: false);
    }

    // ── 8. Carry + steal attempt (t 0.62–0.85) - INTERCEPT burst at t=0.80 ──
    if (t >= _kInterceptT && t < _kInterceptT + 0.05) {
      final burstT = ((t - _kInterceptT) / 0.05).clamp(0.0, 1.0);
      canvas.drawCircle(
          posB,
          14 + burstT * 20,
          Paint()
            ..color = Colors.white.withValues(alpha: (1.0 - burstT) * 0.75 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2);
      _drawLabel(canvas, 'INTERCEPT!', posB.translate(0, -20), kRunnerCPink,
          (1.0 - burstT) * fade);
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
