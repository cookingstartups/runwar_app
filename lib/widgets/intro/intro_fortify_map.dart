import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 5. IntroFortifyMap — fortify animation: runner loops the claimed chunk (slide 3)
// ---------------------------------------------------------------------------
class IntroFortifyMap extends StatefulWidget {
  final Color accent;
  const IntroFortifyMap({required this.accent, super.key});
  @override
  State<IntroFortifyMap> createState() => _IntroFortifyMapState();
}

class _IntroFortifyMapState extends State<IntroFortifyMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroFortifyMap> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Inherited territory: all 3 Ruzafa blocks pre-filled orange.
  // Claimed/fortified chunk: the disputed quad now owned (kSea).
  static const _kDisputedCoords = [
    LatLng(39.4616, -0.3768), // B — NW
    LatLng(39.4616, -0.3752), // E — NE
    LatLng(39.4604, -0.3760), // F — SE
    LatLng(39.4611, -0.3764), // G — SW interior
  ];

  // ── Real-GPS runner route ───────────────────────────────────────────────────
  // Phase 1 (t = 0.0 → 0.2): one-time approach polyline, 6 waypoints.
  static const _kFortifyApproach = [
    LatLng(39.45876687267654,  -0.3714029660927564),  // 0: off-screen south entry
    LatLng(39.46215764898202,  -0.37378187786513245), // 1: north
    LatLng(39.46036136544272,  -0.3781083602643439),  // 2: west turn
    LatLng(39.45972559106001,  -0.377663948174999),   // 3: south
    LatLng(39.460916401822544, -0.3729453374616596),  // 4: east
    LatLng(39.462167740331644, -0.3738210906965453),  // 5: north — arrives at loop start
  ];

  // Phase 2 (t = 0.15 → 0.75): closed-loop circuit traversed 4 times.
  // The closing edge from loop[3] back to loop[0] is implicit.
  static const _kFortifyLoop = [
    LatLng(39.46217783167975,  -0.37378187786513245), // 0: loop start (top)
    LatLng(39.460341182218244, -0.37809528932053965), // 1: west
    LatLng(39.45912365004915,  -0.3772626255741333), // 2: south-west
    LatLng(39.460939442465346, -0.37295328466461247), // 3: east
  ];

  // Phase 3 (t = 0.75 → 1.0): runner exits north toward an off-screen point.
  static const _kFortifyExit = LatLng(39.46536912894788, -0.3760824535918775);

  // Phase boundaries.
  static const double _kApproachEndT = 0.15;
  static const double _kLoopEndT = 0.75;
  static const int _kTotalLaps = 4;

  // Approach segment time weights live on the painter (see
  // _IntroFortifyMapPainter._kApproachWeights). Documented here for context:
  // 6 approach points → 5 segments; segments 0 and 1 run at 1.6× speed
  // (weight 0.625 vs 1.0). Cumulative normalized weights:
  // [0, 0.147, 0.294, 0.529, 0.765, 1.0].

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _claimedChunk = [];
  List<Offset> _approachPts = [];
  List<Offset> _loopPts = [];
  Offset _exitPt = Offset.zero;
  int _level = 0;

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
      _approachPts = _kFortifyApproach.map(toScreen).toList();
      _loopPts = _kFortifyLoop.map(toScreen).toList();
      _exitPt = toScreen(_kFortifyExit);
    });
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 20));
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    _ctrl.addListener(_onTick);
    loopController(_ctrl, mounted: () => mounted);
  }

  // Derive level purely from t. Approach phase (t < 0.15) keeps level at 0.
  // Loop phase (0.15 → 0.75) increments level once per completed lap (4 total).
  // Exit phase (t ≥ 0.75) holds level at _kTotalLaps so the fortified state
  // is fully painted while the runner exits north.
  int _levelFromT(double t) {
    if (t < _kApproachEndT) return 0;
    if (t >= _kLoopEndT) return _kTotalLaps;
    final loopT = ((t - _kApproachEndT) / (_kLoopEndT - _kApproachEndT))
        .clamp(0.0, 1.0);
    return (loopT * _kTotalLaps).floor().clamp(0, _kTotalLaps);
  }

  void _onTick() {
    final newLevel = _levelFromT(_ctrl.value);
    if (newLevel != _level) {
      setState(() => _level = newLevel);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
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
            center: const LatLng(39.4595, -0.3768),
            zoom: 16.0,
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
                final tailPx = (_ctrl.value * kIntroRouteEstimatedMeters).clamp(0.0, kCometTailMaxMeters) / metersPerPx;
                return CustomPaint(
                  painter: _IntroFortifyMapPainter(
                    t: _ctrl.value,
                    level: _level,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    claimedChunk: _claimedChunk,
                    approachPts: _approachPts,
                    loopPts: _loopPts,
                    exitPt: _exitPt,
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
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> claimedChunk;
  final List<Offset> approachPts;
  final List<Offset> loopPts;
  final Offset exitPt;
  final double tailLengthPx;

  _IntroFortifyMapPainter({
    required this.t,
    required this.level,
    required this.accent,
    required this.inheritedPts,
    required this.claimedChunk,
    required this.approachPts,
    required this.loopPts,
    required this.exitPt,
    required this.tailLengthPx,
  });

  // Must mirror state-class constants — phase boundaries + total laps.
  static const double _kApproachEndT = 0.15;
  static const double _kLoopEndT = 0.75;
  static const int _kTotalLaps = 4;

  // Mirrors _IntroFortifyMapState._kApproachWeights — segment time weights.
  static const _kApproachWeights = <double>[0.625, 0.625, 1.0, 1.0, 1.0];

  Offset _chunkCentroid() {
    if (claimedChunk.isEmpty) return Offset.zero;
    double sumX = 0, sumY = 0;
    for (final pt in claimedChunk) {
      sumX += pt.dx;
      sumY += pt.dy;
    }
    return Offset(sumX / claimedChunk.length, sumY / claimedChunk.length);
  }

  /// Arc-length interpolation along an open polyline of [pts] at fraction
  /// [frac] (0..1). When [closed] is true, the closing edge from last back to
  /// first is included.
  Offset _posOnPolyline(List<Offset> pts, double frac, {bool closed = false}) {
    if (pts.isEmpty) return Offset.zero;
    if (pts.length == 1) return pts[0];
    final segCount = closed ? pts.length : pts.length - 1;
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
    return pts[closed ? 0 : pts.length - 1];
  }

  /// Position along the approach polyline using per-segment time weights
  /// instead of arc-length. Segments 0 and 1 consume 0.625/4.25 ≈ 14.7% of
  /// approach time each (vs uniform 20%), so the runner traverses them ~1.6×
  /// faster than the remaining three segments.
  Offset _posOnApproachWeighted(double frac) {
    if (approachPts.isEmpty) return Offset.zero;
    if (approachPts.length == 1) return approachPts[0];

    // Cumulative normalized weights — 6 entries for 5 segments.
    double total = 0;
    for (final w in _kApproachWeights) {
      total += w;
    }
    if (total == 0) return approachPts[0];

    final cum = <double>[0];
    double acc = 0;
    for (final w in _kApproachWeights) {
      acc += w;
      cum.add(acc / total);
    }
    final p = frac.clamp(0.0, 1.0);

    // Find the segment p falls in.
    for (int i = 0; i < _kApproachWeights.length; i++) {
      final lo = cum[i];
      final hi = cum[i + 1];
      if (p <= hi) {
        final span = hi - lo;
        final localFrac = span > 0 ? (p - lo) / span : 0.0;
        return Offset.lerp(approachPts[i], approachPts[i + 1], localFrac)!;
      }
    }
    return approachPts.last;
  }

  /// Position of the runner dot at the master timeline t.
  /// Phase 1 (t < 0.15):       walk approach polyline once (weighted time).
  /// Phase 2 (0.15 ≤ t < 0.75): walk loop polyline 4 times (closed loop).
  /// Phase 3 (t ≥ 0.75):       lerp from loop[0] (top) to exitPt off-screen.
  Offset _runnerPosAtT(double t) {
    if (t < _kApproachEndT) {
      final approachFrac = (t / _kApproachEndT).clamp(0.0, 1.0);
      return _posOnApproachWeighted(approachFrac);
    }
    if (t < _kLoopEndT) {
      if (loopPts.isEmpty) return Offset.zero;
      final loopT = ((t - _kApproachEndT) / (_kLoopEndT - _kApproachEndT))
          .clamp(0.0, 1.0);
      final lapPos = (loopT * _kTotalLaps) % 1.0;
      return _posOnPolyline(loopPts, lapPos, closed: true);
    }
    // Exit phase — runner starts at loop[0] and travels to exitPt.
    if (loopPts.isEmpty) return exitPt;
    final exitFrac = ((t - _kLoopEndT) / (1.0 - _kLoopEndT)).clamp(0.0, 1.0);
    return Offset.lerp(loopPts[0], exitPt, exitFrac)!;
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

    // 1. Claimed chunk — kSea fill. Opacity ramps with level: 0.15 at level 0,
    // up to 0.80 at level 4 (4 laps).
    final fillOpacity = 0.15 + (level / 4.0) * 0.65;
    drawFillColor(canvas, claimedChunk, kSea, fillOpacity);

    // 2. Halo on loop circuit path — kSea glow outline that traces the runner's
    // looping route, intensity grows with level. Only drawn once the runner
    // has entered the loop phase.
    if (level > 0 && loopPts.length >= 2) {
      final haloOpacity = 0.25 + (level / 4.0) * 0.65;
      final haloStroke = 1.5 + (level / 4.0) * 4.0;
      final loopPath = Path()..moveTo(loopPts[0].dx, loopPts[0].dy);
      for (int i = 1; i < loopPts.length; i++) {
        loopPath.lineTo(loopPts[i].dx, loopPts[i].dy);
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

    // Level badge at top-left corner of claimed chunk.
    if (level > 0) {
      drawLevelBadge(canvas, claimedChunk, level, kAccent);
    }

    // 3. Comet-tail trace for the active runner.
    if (t < _kApproachEndT) {
      // Phase 1 — approach polyline.
      final approachFrac = (t / _kApproachEndT).clamp(0.0, 1.0);
      drawComet(canvas, approachPts, approachFrac,
          tailLengthPx: tailLengthPx, color: kSea);
    } else if (t < _kLoopEndT) {
      // Phase 2 — closed-loop circuit. Use lap fraction within current lap.
      final loopT =
          ((t - _kApproachEndT) / (_kLoopEndT - _kApproachEndT)).clamp(0.0, 1.0);
      final lapPos = (loopT * _kTotalLaps) % 1.0;
      // Build a closed polyline (append first point) so the comet tail
      // wraps continuously around the circuit.
      final closedLoop = [...loopPts, loopPts[0]];
      drawComet(canvas, closedLoop, lapPos,
          tailLengthPx: tailLengthPx, color: kSea);
    } else if (loopPts.isNotEmpty) {
      // Phase 3 — exit segment from loop[0] to exitPt.
      final exitFrac =
          ((t - _kLoopEndT) / (1.0 - _kLoopEndT)).clamp(0.0, 1.0);
      drawComet(canvas, [loopPts[0], exitPt], exitFrac,
          tailLengthPx: tailLengthPx, color: kSea);
    }

    // Runner dot — phase 1: approach polyline; phase 2: 4-lap loop circuit;
    // phase 3: lerp toward off-screen exit point.
    final runnerPos = _runnerPosAtT(t);
    canvas.drawCircle(
        runnerPos,
        10,
        Paint()
          ..color = kSea.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(runnerPos, 4, Paint()..color = kSea);
    canvas.drawCircle(
        runnerPos, 1.5, Paint()..color = Colors.white.withValues(alpha: 0.85));

    // 4. At max level (4): pulse ring + "FORTIFIED" label.
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
      old.tailLengthPx != tailLengthPx ||
      old.claimedChunk != claimedChunk ||
      old.approachPts != approachPts ||
      old.loopPts != loopPts ||
      old.exitPt != exitPt;
}
