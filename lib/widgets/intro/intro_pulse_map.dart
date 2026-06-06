import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 1. IntroPulseMap — lasso trace + block capture (slide 1)
// ---------------------------------------------------------------------------
class IntroPulseMap extends StatefulWidget {
  final Color accent;
  const IntroPulseMap({required this.accent, super.key});
  @override
  State<IntroPulseMap> createState() => _IntroPulseMapState();
}

class _IntroPulseMapState extends State<IntroPulseMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroPulseMap> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Three adjacent Ruzafa blocks captured in order (OSM-verified, no backtrack).
  //
  // Block 1 — Buenos Aires / Cuba diagonal / Dénia / Sueca (NW block):
  //   [0] A  Sueca×Buenos Aires NE corner
  //   [1] B  Buenos Aires SW end
  //   [2] C  Cuba/Dénia W junction
  //   [3] D  Sueca×Dénia junction
  //   [4] A  CLOSE 1  (_kBlock1CloseIdx = 4)
  //
  // Block 2 — Sueca E / Cuba SE / Puerto Rico / Buenos Aires N (SE block):
  //   [5] E  Sueca E new segment (SE of A, new territory)
  //   [6] F  Cuba SE diagonal end
  //   [7] G  Puerto Rico SW end
  //   [8] B  CLOSE 2 — northward on Buenos Aires  (_kBlock2CloseIdx = 8)
  //
  // Block 3 — Buenos Aires S / Puerto Rico E / back to G (S block):
  //   [9]  H  Buenos Aires SW far end (south of B)
  //   [10] I  Puerto Rico W approach
  //   [11] G  CLOSE 3  (_kBlock3CloseIdx = 11)
  static const _kRoute = [
    LatLng(39.462077, -0.375522), //  [0] A  — Sueca×Buenos Aires
    LatLng(39.461576, -0.376751), //  [1] B  — Buenos Aires SW
    LatLng(39.462155, -0.377171), //  [2] C  — Cuba/Dénia W junction
    LatLng(39.462671, -0.375937), //  [3] D  — Sueca×Dénia
    LatLng(39.462077, -0.375522), //  [4] A  — BLOCK 1 CLOSES
    LatLng(39.461568, -0.375167), //  [5] E  — Sueca E (new)
    LatLng(39.460440, -0.375966), //  [6] F  — Cuba SE diagonal
    LatLng(39.461050, -0.376394), //  [7] G  — Puerto Rico SW
    LatLng(39.461576, -0.376751), //  [8] B  — BLOCK 2 CLOSES
    LatLng(39.460846, -0.378471), //  [9] H  — Buenos Aires SW far end
    LatLng(39.460335, -0.378112), // [10] I  — Puerto Rico W approach
    LatLng(39.461050, -0.376394), // [11] G  — BLOCK 3 CLOSES
  ];

  List<Offset> _route = [];
  List<Offset> _block1 = [];
  List<Offset> _block2 = [];
  List<Offset> _block3 = [];

  // Incremented each time the animation loop restarts so the painter can
  // invalidate its shared-edge cache (keyed by loopGeneration).
  int _loopGeneration = 0;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12));
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    _startLoop();
  }

  void _startLoop() {
    _ctrl.reset();
    _ctrl.forward().then((_) {
      if (!mounted) return;
      setState(() => _loopGeneration++);
      Future.delayed(kIntroLoopPause, () {
        if (!mounted) return;
        _startLoop();
      });
    });
  }

  void _updatePoints() {
    final cam = mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }
    markMapReady(() {
      _route = _kRoute.map(toScreen).toList();
      _block1 = IntroZones.kS1Block1.map(toScreen).toList();
      _block2 = IntroZones.kS1Block2.map(toScreen).toList();
      _block3 = IntroZones.kS1Block3.map(toScreen).toList();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _ctrl.dispose();
    disposeMapCtrl();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fadeCtrl,
        child: Stack(
        children: [
          buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4599, -0.3756),
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                // meters per pixel at current zoom & center latitude.
                // Standard Web Mercator formula:
                //   mpp = (2π · R · cos(lat)) / (256 · 2^zoom)
                const earthR = 6378137.0;
                final cam = mapCtrl.camera;
                final latRad = cam.center.latitude * math.pi / 180.0;
                final mpp =
                    (2 * math.pi * earthR * math.cos(latRad)) /
                    (256 * math.pow(2, cam.zoom));
                final tailPx = kCometTailMeters / mpp;
                return CustomPaint(
                  painter: _IntroPulseMapPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    route: _route,
                    block1: _block1,
                    block2: _block2,
                    block3: _block3,
                    tailLengthPx: tailPx,
                    loopGeneration: _loopGeneration,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          Positioned(
            top: 64,
            left: 16,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                const windows = [
                  (t0: 0.2982, area: 8951),
                  (t0: 0.5964, area: 12453),
                  (t0: 0.820, area: 10997),
                ];
                const windowSize = 0.12;
                final t = _ctrl.value;
                double opacity = 0.0;
                int area = 0;
                for (final w in windows) {
                  final dt = t - w.t0;
                  if (dt >= 0 && dt < windowSize) {
                    final frac = dt / windowSize;
                    opacity = frac < 0.15
                        ? frac / 0.15
                        : frac > 0.85
                            ? (1.0 - frac) / 0.15
                            : 1.0;
                    area = w.area;
                    break;
                  }
                }
                if (opacity <= 0) return const SizedBox.shrink();
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'WARLORD  +${formatSqm(area)} sqm',
                      style: GoogleFonts.robotoMono(
                        fontSize: 11,
                        color: kAccent,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
}

class _IntroPulseMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<Offset> route;
  final List<Offset> block1;
  final List<Offset> block2;
  final List<Offset> block3;
  final double tailLengthPx;
  final int loopGeneration;

  // Shared-edge cache keyed by "$loopGeneration:$blockIndex" (0, 1, 2).
  // Computed once at the first frame of each block's E&U window.
  // Storing mutable state in the painter is acceptable here because the cache
  // is purely a paint-time optimisation — it has no effect on semantics.
  final Map<String, List<List<Offset>>?> _sharedEdgeCache = {};

  _IntroPulseMapPainter({
    required this.t,
    required this.accent,
    required this.route,
    required this.block1,
    required this.block2,
    required this.block3,
    required this.tailLengthPx,
    required this.loopGeneration,
  });

  // Segment indices where each block loop closes.
  // Block 1 closes at idx 4 (A), block 2 at idx 8 (B), block 3 at idx 11 (G).
  // Blocks 1+2 are traveled-based (runner continues past close, giving ramp headroom).
  // Block 3 is time-based: traveled maxes at the close point (t=0.82), so there
  // is no post-close headroom in traveled space — trigger on t directly instead.
  static const double _block1CloseIdx = 4.0;
  static const double _block2CloseIdx = 8.0;
  static const double _block3CloseT = 0.82; // t at which route completes = block 3 closes

  // E&U start times in controller t-space.
  //   t = (closeIdx / 11) * 0.82  for blocks 1+2 (11 total segments, 0.82 max t).
  static const double _eu1StartT = (_block1CloseIdx / 11.0) * 0.82; // ≈ 0.2982
  static const double _eu2StartT = (_block2CloseIdx / 11.0) * 0.82; // ≈ 0.5964
  static const double _eu3StartT = _block3CloseT;                    // 0.82

  // E&U window in t-space: 400 ms over a 12 s controller ≈ 0.0333.
  static const double _euWindowT = 0.400 / 12.0;

  // Fill opacity ramps over 0.5 segments past each close index; holds at
  // 0.28 permanently (no fade at t>=0.85 so territory stays visible during pause).
  // Used for blocks 1 and 2.
  double _fillOpacity(double traveled, double closeIdx, double t) {
    final frac = ((traveled - closeIdx) / 0.5).clamp(0.0, 1.0);
    return frac * 0.28;
  }

  // Time-based fill opacity for block 3. No fade — territory stays visible.
  double _block3FillOpacity(double t) {
    if (t < _block3CloseT) return 0.0;
    final ramp = ((t - _block3CloseT) / 0.04).clamp(0.0, 1.0);
    return ramp * 0.28;
  }

  // Compute the union opacity envelope for the current frame.
  // During an active E&U window for block N, smoothly tweens the prior union's
  // peak opacity toward the full union's peak using [unionOpacityHandoff].
  // Outside any window falls back to math.max — preserves existing behaviour.
  double _computeUnionOpacity(List<double> ramps, double currentT) {
    const startTs = [_eu1StartT, _eu2StartT, _eu3StartT];
    for (var i = 0; i < ramps.length; i++) {
      final dt = currentT - startTs[i];
      if (dt >= 0 && dt < _euWindowT) {
        final windowT = (dt / _euWindowT).clamp(0.0, 1.0);
        // Prior peak = max of ramps excluding block i.
        final prior = ramps
            .asMap()
            .entries
            .where((e) => e.key != i)
            .map((e) => e.value)
            .fold(0.0, math.max);
        final newFull = ramps.fold(0.0, math.max);
        return unionOpacityHandoff(
          priorOpacity: prior,
          newOpacity: newFull,
          windowT: windowT,
        );
      }
    }
    return ramps.where((o) => o > 0).fold(0.0, math.max);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    // Runner completes all 3 blocks by t=0.82, fills hold until t=0.94, then fade.
    final segs = route.length - 1; // 11 segments
    final routeProgress = (t / 0.82).clamp(0.0, 1.0);
    final traveled = routeProgress * segs;

    // Build a single union path from every block whose close threshold has been
    // reached. Drawing fill+stroke ONCE from this union means contiguous
    // captured blocks render as a single polygon with only an outer perimeter
    // border — no internal seams between blocks that share an edge or vertex.
    Path makePoly(List<Offset> pts) {
      if (pts.isEmpty) return Path();
      final p = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        p.lineTo(pts[i].dx, pts[i].dy);
      }
      return p..close();
    }

    // Per-block fill opacity ramps (kept for the union opacity envelope).
    final fill1Opacity = _fillOpacity(traveled, _block1CloseIdx, t);
    final fill2Opacity = _fillOpacity(traveled, _block2CloseIdx, t);
    final fill3Opacity = _block3FillOpacity(t);

    // A block is "closed" once its close threshold has been crossed — that is,
    // the moment its fill opacity becomes non-zero. Use the same gating as the
    // opacity ramps so the union appears exactly when each block captures.
    var capturedUnion = Path();
    if (fill1Opacity > 0 && block1.isNotEmpty) {
      capturedUnion = Path.combine(
          PathOperation.union, capturedUnion, makePoly(block1));
    }
    if (fill2Opacity > 0 && block2.isNotEmpty) {
      capturedUnion = Path.combine(
          PathOperation.union, capturedUnion, makePoly(block2));
    }
    if (fill3Opacity > 0 && block3.isNotEmpty) {
      capturedUnion = Path.combine(
          PathOperation.union, capturedUnion, makePoly(block3));
    }

    // Single opacity envelope for the union = the peak of any contributing
    // block's ramp. During an active E&U window the opacity is smoothly tweened
    // via [_computeUnionOpacity] to avoid the step-up flicker when a new block
    // ramp overtakes the prior peak. Outside any window falls back to math.max.
    final activeOpacity = _computeUnionOpacity(
      [fill1Opacity, fill2Opacity, fill3Opacity],
      t,
    );
    if (activeOpacity > 0) {
      // Fill — one call across the unioned polygon.
      canvas.drawPath(
        capturedUnion,
        Paint()
          ..color = accent.withValues(alpha: activeOpacity)
          ..style = PaintingStyle.fill,
      );
      // Stroke — one call; outer perimeter only, no internal block seams.
      canvas.drawPath(
        capturedUnion,
        Paint()
          ..color = accent.withValues(
              alpha: (activeOpacity / 0.28).clamp(0.0, 1.0) * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // ── Expand & Unify transitions ─────────────────────────────────────────
    // For each block, if t is within its E&U window, draw the overlay.
    const euCloseStarts = [_eu1StartT, _eu2StartT, _eu3StartT];
    final euBlocks = [block1, block2, block3];

    for (var i = 0; i < 3; i++) {
      final startT = euCloseStarts[i];
      final dt = t - startT;
      if (dt < 0 || dt >= _euWindowT) continue;
      final animT = (dt / _euWindowT).clamp(0.0, 1.0);

      // Build prior-union path (blocks 0..i-1 that have already closed).
      Path priorUnion = Path();
      final priorBlockVerts = <List<Offset>>[];
      for (var j = 0; j < i; j++) {
        if (euBlocks[j].isNotEmpty) {
          priorUnion = Path.combine(
              PathOperation.union, priorUnion, makePoly(euBlocks[j]));
          priorBlockVerts.add(euBlocks[j]);
        }
      }

      // Cache shared edges on the first frame of this window.
      // Key includes loopGeneration to auto-invalidate on loop restart.
      final cacheKey = '$loopGeneration:$i';
      if (!_sharedEdgeCache.containsKey(cacheKey)) {
        final edges = sharedEdgePolylines(
          priorBlocks: priorBlockVerts,
          newBlock: euBlocks[i],
        );
        _sharedEdgeCache[cacheKey] = edges.isEmpty ? null : edges;
      }

      drawExpandUnify(
        canvas,
        priorUnion: priorUnion,
        newBlock: euBlocks[i],
        unionAfter: capturedUnion,
        sharedEdges: _sharedEdgeCache[cacheKey],
        t: animT,
        color: accent,
      );
    }

    // Single comet-tail trace covering all 3 blocks.
    final decayMul = t < 0.94
        ? 1.0
        : (1.0 - ((t - 0.94) / 0.06)).clamp(0.0, 1.0);
    drawComet(
      canvas,
      route,
      routeProgress,
      tailLengthPx: tailLengthPx,
      color: accent,
      decayMul: decayMul,
    );

    // Runner dot:
    //   t < 0.82  — traces route normally
    //   t 0.82–0.94 — continues past close point, turns right, fades out
    //   t >= 0.94  — runner gone; fills continue fading via _fillOpacity
    if (t < 0.82) {
      drawRunner(canvas, route, routeProgress);
    } else if (t < 0.94 && route.length >= 2) {
      final contT = ((t - 0.82) / 0.12).clamp(0.0, 1.0);
      // Direction of the last segment (I → G).
      final dir = route.last - route[route.length - 2];
      final dirLen = dir.distance;
      if (dirLen > 0.01) {
        final unitDir = dir / dirLen;
        // 90° right turn: (dx,dy) → (dy,−dx)
        final rightDir = Offset(unitDir.dy, -unitDir.dx);
        // Gradually blend forward direction into right-turn direction.
        final blended = Offset.lerp(unitDir, rightDir, contT)!;
        final blendNorm = blended / blended.distance;
        final pos = route.last +
            blendNorm * Curves.easeIn.transform(contT) * 34;
        final fade = 1.0 - contT;
        canvas.drawCircle(
            pos,
            12,
            Paint()
              ..color = accent.withValues(alpha: 0.25 * fade)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        canvas.drawCircle(
            pos, 4.5, Paint()..color = accent.withValues(alpha: fade));
        canvas.drawCircle(
            pos,
            1.8,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.8 * fade));
      }
    }

    // Ping burst when block 1 closes — wider window (1.5 segs) for slower pulse.
    final ping1T = traveled - _block1CloseIdx;
    if (ping1T > 0 && ping1T < 1.5) {
      drawPings(canvas, block1, (ping1T / 1.5).clamp(0.0, 1.0));
    }

    // Ping burst when block 2 closes.
    final ping2T = traveled - _block2CloseIdx;
    if (ping2T > 0 && ping2T < 1.5) {
      drawPings(canvas, block2, (ping2T / 1.5).clamp(0.0, 1.0));
    }

    // Ping burst when block 3 closes — time-based (traveled maxes at close point).
    if (t >= _block3CloseT && t < _block3CloseT + 0.112) {
      final pingFrac = ((t - _block3CloseT) / 0.112).clamp(0.0, 1.0);
      drawPings(canvas, block3, pingFrac);
    }
  }

  @override
  bool shouldRepaint(_IntroPulseMapPainter old) =>
      old.t != t ||
      old.route != route ||
      old.block1 != block1 ||
      old.block2 != block2 ||
      old.block3 != block3 ||
      old.tailLengthPx != tailLengthPx ||
      old.loopGeneration != loopGeneration;
}
