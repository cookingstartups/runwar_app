import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../theme.dart';

// ── Named duration constants ──────────────────────────────────────────────────
const _kIntroFadeDelay = Duration(milliseconds: 400);
const _kIntroFadeDuration = Duration(milliseconds: 200);
const _kIntroLoopPause = Duration(seconds: 2);

// ── Loop helper ───────────────────────────────────────────────────────────────
void _loopController(
  AnimationController ctrl, {
  Duration pause = _kIntroLoopPause,
  required bool Function() mounted,
}) {
  ctrl.reset();
  ctrl.forward().then((_) {
    if (!mounted()) return;
    Future.delayed(pause, () {
      if (!mounted()) return;
      _loopController(ctrl, pause: pause, mounted: mounted);
    });
  });
}

// ── Map controller lifecycle mixin ────────────────────────────────────────────
mixin _IntroMapMixin<T extends StatefulWidget> on State<T> {
  final mapCtrl = MapController();
  bool mapReady = false;

  void markMapReady(VoidCallback computePoints) {
    setState(() {
      computePoints();
      mapReady = true;
    });
  }

  void disposeMapCtrl() => mapCtrl.dispose();
}

String _formatSqm(int sqm) =>
    sqm >= 1000 ? '${(sqm / 1000).toStringAsFixed(1)}k' : sqm.toString();

TileLayer _cartoDbDarkNoLabels(BuildContext context) => TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
      userAgentPackageName: 'app.runwar.runwar_app',
      keepBuffer: 4,
      panBuffer: 2,
      tileDisplay: const TileDisplay.instantaneous(),
    );

Widget _buildIntroMap({
  required BuildContext context,
  required MapController mapController,
  required LatLng center,
  required double zoom,
  required VoidCallback onReady,
  double? maxZoom,
}) =>
    FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        onMapReady: onReady,
      ),
      children: [
        if (maxZoom != null)
          TileLayer(
            urlTemplate:
                'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            maxZoom: maxZoom,
            retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
            userAgentPackageName: 'app.runwar.runwar_app',
            keepBuffer: 4,
            panBuffer: 2,
            tileDisplay: const TileDisplay.instantaneous(),
          )
        else
          _cartoDbDarkNoLabels(context),
      ],
    );

mixin _IntroPainterHelpers {
  Color get accent;

  void drawFill(Canvas canvas, List<Offset> pts, double opacity) {
    if (opacity <= 0 || pts.isEmpty) return;
    final fp = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      fp.lineTo(pts[i].dx, pts[i].dy);
    }
    fp.close();
    canvas.drawPath(
      fp,
      Paint()
        ..color = accent.withValues(alpha: opacity)
        ..style = PaintingStyle.fill,
    );
  }

  void drawFillColor(Canvas canvas, List<Offset> pts, Color color, double opacity) {
    if (opacity <= 0 || pts.isEmpty) return;
    final fp = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      fp.lineTo(pts[i].dx, pts[i].dy);
    }
    fp.close();
    canvas.drawPath(
      fp,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill,
    );
  }

  void drawTrace(Canvas canvas, List<Offset> pts, double routeT) {
    if (pts.isEmpty) return;
    final segs = pts.length - 1;
    final totalLen = routeT.clamp(0.0, 1.0) * segs;
    final routeP = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rp = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < segs; i++) {
      if (totalLen > i) {
        final segT = (totalLen - i).clamp(0.0, 1.0);
        rp.lineTo(
          Offset.lerp(pts[i], pts[i + 1], segT)!.dx,
          Offset.lerp(pts[i], pts[i + 1], segT)!.dy,
        );
      }
    }
    canvas.drawPath(rp, routeP);
  }

  void drawTraceColor(Canvas canvas, List<Offset> pts, double routeT, Color color) {
    if (pts.isEmpty) return;
    final segs = pts.length - 1;
    final totalLen = routeT.clamp(0.0, 1.0) * segs;
    final routeP = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rp = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < segs; i++) {
      if (totalLen > i) {
        final segT = (totalLen - i).clamp(0.0, 1.0);
        rp.lineTo(
          Offset.lerp(pts[i], pts[i + 1], segT)!.dx,
          Offset.lerp(pts[i], pts[i + 1], segT)!.dy,
        );
      }
    }
    canvas.drawPath(rp, routeP);
  }

  void drawRunner(Canvas canvas, List<Offset> pts, double routeT) {
    if (pts.isEmpty) return;
    final segs = pts.length - 1;
    final totalLen = routeT.clamp(0.0, 1.0) * segs;
    final segIdx = totalLen.floor().clamp(0, segs - 1);
    final segFrac = (totalLen - segIdx).clamp(0.0, 1.0);
    final pos =
        Offset.lerp(pts[segIdx], pts[(segIdx + 1).clamp(0, segs)], segFrac)!;
    canvas.drawCircle(
        pos,
        12,
        Paint()
          ..color = accent.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawCircle(pos, 4.5, Paint()..color = accent);
    canvas.drawCircle(
        pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.8));
  }

  void drawPings(Canvas canvas, List<Offset> pts, double pingT) {
    if (pts.length < 3) return;
    final corners = [pts[0], pts[pts.length ~/ 2], pts[pts.length - 2]];
    for (final corner in corners) {
      canvas.drawCircle(
          corner,
          pingT * 28,
          Paint()
            ..color = accent.withValues(alpha: (1 - pingT) * 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  void drawRunnerAt(Canvas canvas, Offset pos, Color color) {
    canvas.drawCircle(
        pos,
        10,
        Paint()
          ..color = color.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(pos, 4, Paint()..color = color);
    canvas.drawCircle(
        pos, 1.5, Paint()..color = Colors.white.withValues(alpha: 0.85));
  }

  /// Draw a list of inherited (already-owned) zone polygons as muted fills.
  /// Uses kAccent at alpha 0.55 so they read as "prior territory" without
  /// competing with the current slide's active animation.
  void drawInheritedBlocks(Canvas canvas, List<List<Offset>> blocks) {
    for (final block in blocks) {
      drawFillColor(canvas, block, kAccent, 0.28);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared GPS polygon data — referenced by multiple slide painters.
// ---------------------------------------------------------------------------
abstract final class IntroZones {
  // ── Slide 1 blocks (Ruzafa) — from IntroPulseMap ──────────────────────────
  static const kS1Block1 = [
    LatLng(39.462077, -0.375522), // A
    LatLng(39.461576, -0.376751), // B
    LatLng(39.462155, -0.377171), // C
    LatLng(39.462671, -0.375937), // D
  ];

  static const kS1Block2 = [
    LatLng(39.462077, -0.375522), // A
    LatLng(39.461568, -0.375167), // E
    LatLng(39.460440, -0.375966), // F
    LatLng(39.461050, -0.376394), // G
    LatLng(39.461576, -0.376751), // B
  ];

  static const kS1Block3 = [
    LatLng(39.461576, -0.376751), // B
    LatLng(39.460846, -0.378471), // H
    LatLng(39.460335, -0.378112), // I
    LatLng(39.461050, -0.376394), // G
  ];

  static const kS1All = [kS1Block1, kS1Block2, kS1Block3];

  // ── Slide 2 net-new blocks — empty; dispute is over existing territory ──────
  static const kS2OwnedBlock1 = <LatLng>[];
  static const kS2OwnedBlock2 = <LatLng>[];

  /// Slide 2 sees: same territory as slide 1 (no new captures yet — conflict
  /// is over existing orange blocks).
  static const kS2All = [...kS1All];

  // ── Slide 3 net-new blocks — north of kS1All, Carrer de Cuba area ──────────
  // Player has pushed north from Ruzafa into the Cuba/Sueca corridor.
  static const kS3OwnedBlock1 = [
    LatLng(39.4627, -0.3755), // NE corner
    LatLng(39.4622, -0.3762), // SW corner
    LatLng(39.4628, -0.3766), // S corner
    LatLng(39.4633, -0.3759), // E corner
  ];

  static const kS3OwnedBlock2 = [
    LatLng(39.4628, -0.3766),
    LatLng(39.4622, -0.3762),
    LatLng(39.4623, -0.3773),
    LatLng(39.4630, -0.3778),
    LatLng(39.4635, -0.3771),
  ];

  /// Slide 3 sees: all of slides 1+2 + slide 3's own blocks.
  static const kS3All = [
    ...kS2All,
    kS3OwnedBlock1,
    kS3OwnedBlock2,
  ];
}

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
    with TickerProviderStateMixin, _IntroMapMixin<IntroPulseMap> {
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

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: _kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12));
    Future.delayed(_kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    _loopController(_ctrl, mounted: () => mounted);
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
          _buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4599, -0.3756),
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _IntroPulseMapPainter(
                  t: _ctrl.value,
                  accent: widget.accent,
                  route: _route,
                  block1: _block1,
                  block2: _block2,
                  block3: _block3,
                ),
                child: const SizedBox.expand(),
              ),
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
                      'WARLORD  +${_formatSqm(area)} sqm',
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

class _IntroPulseMapPainter extends CustomPainter with _IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<Offset> route;
  final List<Offset> block1;
  final List<Offset> block2;
  final List<Offset> block3;

  _IntroPulseMapPainter({
    required this.t,
    required this.accent,
    required this.route,
    required this.block1,
    required this.block2,
    required this.block3,
  });

  // Segment indices where each block loop closes.
  // Block 1 closes at idx 4 (A), block 2 at idx 8 (B), block 3 at idx 11 (G).
  // Blocks 1+2 are traveled-based (runner continues past close, giving ramp headroom).
  // Block 3 is time-based: traveled maxes at the close point (t=0.82), so there
  // is no post-close headroom in traveled space — trigger on t directly instead.
  static const double _block1CloseIdx = 4.0;
  static const double _block2CloseIdx = 8.0;
  static const double _block3CloseT = 0.82; // t at which route completes = block 3 closes

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
    // block's ramp. Keeps the existing fade-in behavior per block while still
    // drawing the merged outline only once.
    final activeOpacity = [fill1Opacity, fill2Opacity, fill3Opacity]
        .where((o) => o > 0)
        .fold(0.0, math.max);
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

    // Single trace covering all 3 blocks.
    drawTrace(canvas, route, routeProgress);

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
      old.block3 != block3;
}

// ---------------------------------------------------------------------------
// 2. IntroCaptureMap — attacker creates disputed territory (slide 2)
//    Existing orange territory shown. Blue rival runner enters from left,
//    draws a lasso overlapping part of owned territory. Overlap → DISPUTED.
// ---------------------------------------------------------------------------
class IntroCaptureMap extends StatefulWidget {
  final Color accent;
  const IntroCaptureMap({required this.accent, super.key});
  @override
  State<IntroCaptureMap> createState() => _IntroCaptureMapState();
}

class _IntroCaptureMapState extends State<IntroCaptureMap>
    with TickerProviderStateMixin, _IntroMapMixin<IntroCaptureMap> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Attacker route — blue rival (kSea) follows the same 4-waypoint loop circuit
  // used by IntroFortifyMap (slide 3) so the attacker's traversal matches the
  // defender's repeating fortify loop. The attacker enters from off-screen
  // south, arrives at the top of the loop, runs one full circuit, then closes
  // the lasso back at the loop start.
  // pt0 → pt1: straight north (entry from off-screen south)
  // pt1 → pt2: west (top → west of loop)
  // pt2 → pt3: south (west → south-west of loop)
  // pt3 → pt4: east (south-west → east of loop)
  // pt4 → pt5: lasso close (east → back to top, pt5 ≈ pt1)
  static const _kAttackerRoute = [
    LatLng(39.45876687267654,   -0.3714029660927564),    // 0: off-screen south — entry
    LatLng(39.46217783167975,   -0.37378187786513245),   // 1: loop[0] — top (loop start)
    LatLng(39.460341182218244,  -0.37809528932053965),   // 2: loop[1] — west
    LatLng(39.45912365004915,   -0.3772626255741333),    // 3: loop[2] — south-west
    LatLng(39.460939442465346,  -0.37295328466461247),   // 4: loop[3] — east
    LatLng(39.46217783167975,   -0.37378187786513245),   // 5: lasso close = loop[0]
  ];

  // Lasso polygon — closed loop pt1 → pt2 → pt3 → pt4 → pt5 (≈ pt1).
  // Matches IntroFortifyMap's _kFortifyLoop circuit exactly.
  static const _kAttackerLasso = [
    LatLng(39.46217783167975,   -0.37378187786513245),   // pt1 — loop[0] top
    LatLng(39.460341182218244,  -0.37809528932053965),   // pt2 — loop[1] west
    LatLng(39.45912365004915,   -0.3772626255741333),    // pt3 — loop[2] south-west
    LatLng(39.460939442465346,  -0.37295328466461247),   // pt4 — loop[3] east
    LatLng(39.46217783167975,   -0.37378187786513245),   // pt5 — close = loop[0]
  ];

  // Disputed area — exact Sutherland-Hodgman intersection of _kAttackerLasso
  // with the union of defender blocks (kS1Block2 ∪ kS1Block3). kS1Block1 does
  // not overlap the lasso. The intersections (lasso ∩ B2, 5 verts) and
  // (lasso ∩ B3, 3 verts) share the edge G ↔ lasso-crossing-of-B-G; merging
  // along that shared edge fuses them into a single 6-vertex CCW polygon.
  static const _kDisputedArea = [
    LatLng(39.461568000000000, -0.375167000000000),   // E — kS1Block2 vertex (inside lasso)
    LatLng(39.461583456798429, -0.375177780281812),   // lasso edge (pt4→pt5) crossing A–E
    LatLng(39.461062095301116, -0.376402209168246),   // lasso edge (pt3→pt4) crossing B–G
    LatLng(39.460375379397249, -0.378014976497241),   // lasso edge (pt1→pt2) crossing I–G
    LatLng(39.461050000000000, -0.376394000000000),   // G — shared B2/B3 vertex
    LatLng(39.460439999999998, -0.375966000000000),   // F — kS1Block2 vertex (inside lasso)
  ];

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _ownedBlock1 = [];
  List<Offset> _ownedBlock2 = [];
  List<Offset> _attackerRoute = [];
  List<Offset> _attackerLasso = [];
  List<Offset> _disputedArea = [];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: _kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    Future.delayed(_kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    _loopController(_ctrl, mounted: () => mounted);
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
      // Inherited blocks from slide 1 — rendered as pre-filled territory.
      _inheritedPts = IntroZones.kS1All
          .map((block) => block.map(toScreen).toList())
          .toList();
      _ownedBlock1 = IntroZones.kS2OwnedBlock1.map(toScreen).toList();
      _ownedBlock2 = IntroZones.kS2OwnedBlock2.map(toScreen).toList();
      _attackerRoute = _kAttackerRoute.map(toScreen).toList();
      _attackerLasso = _kAttackerLasso.map(toScreen).toList();
      _disputedArea = _kDisputedArea.map(toScreen).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Stack(
        children: [
          _buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4632, -0.3773),
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _IntroCaptureMapPainter(
                  t: _ctrl.value,
                  accent: widget.accent,
                  inheritedPts: _inheritedPts,
                  ownedBlock1: _ownedBlock1,
                  ownedBlock2: _ownedBlock2,
                  attackerRoute: _attackerRoute,
                  attackerLasso: _attackerLasso,
                  disputedArea: _disputedArea,
                ),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

class _IntroCaptureMapPainter extends CustomPainter with _IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> ownedBlock1;
  final List<Offset> ownedBlock2;
  final List<Offset> attackerRoute;
  final List<Offset> attackerLasso;
  final List<Offset> disputedArea;

  _IntroCaptureMapPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.ownedBlock1,
    required this.ownedBlock2,
    required this.attackerRoute,
    required this.attackerLasso,
    required this.disputedArea,
  });

  // Timeline (route has 5 segments; close is at traveled == _kLassoCloseSegIdx == 4):
  //   traveled 0→4   : attacker runs; lasso closes when traveled reaches 4
  //   t 0.60–0.78    : disputed phase — fill cross-fades kAccent orange → amber
  //   t 0.78–0.90    : border flash — dashed yellow/black alternating, fill stays amber
  //   t 0.90–1.0     : claimed — fill + border lerp to kSea blue
  //   t 0.88–1.00    : global fade

  // Route finishes drawing by t=0.70; remaining t budget used for post-close effects.
  static const double _kRouteCompleteT = 0.70;

  // Segment index in _kAttackerRoute where the path closes the loop.
  // Segment 4 = pt4→pt5, with pt5 ≈ pt1.
  static const int _kLassoCloseSegIdx = 4;

  double _disputedOpacity(double traveled) {
    if (traveled < _kLassoCloseSegIdx) return 0.0;
    final ramp = ((traveled - _kLassoCloseSegIdx) / 0.3).clamp(0.0, 1.0);
    return ramp * 0.35;
  }

  double _globalFade(double t) {
    if (t < 0.88) return 1.0;
    return (1.0 - (t - 0.88) / 0.12).clamp(0.0, 1.0);
  }

  /// 3-phase fill color:
  ///   0.60–0.78: kAccent orange → amber Color(0xFFFFB200)
  ///   0.78–0.90: amber (flash phase; fill stays amber)
  ///   0.90–1.0 : amber → kSea blue
  Color _disputedFillColor(double t) {
    if (t < 0.60) return kAccent;
    if (t < 0.78) {
      final lerpT = (t - 0.60) / 0.18;
      return Color.lerp(kAccent, const Color(0xFFFFB200), lerpT)!;
    }
    if (t < 0.90) return const Color(0xFFFFB200);
    final lerpT = (t - 0.90) / 0.10;
    return Color.lerp(const Color(0xFFFFB200), kSea, lerpT)!;
  }

  void _drawDashedPath(
      Canvas canvas, Path path, double dashLen, double gapLen, Paint paint) {
    for (final metric in path.computeMetrics()) {
      double dist = 0.0;
      bool drawing = true;
      while (dist < metric.length) {
        final end = (dist + (drawing ? dashLen : gapLen)).clamp(0.0, metric.length);
        if (drawing) {
          canvas.drawPath(metric.extractPath(dist, end), paint);
        }
        dist = end;
        drawing = !drawing;
      }
    }
  }

  Path _makePoly(List<Offset> pts) {
    if (pts.isEmpty) return Path();
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    return p..close();
  }

  /// Shoelace formula — absolute area of a screen-space polygon (px²).
  /// Used to detect a degenerate disputed polygon (touching but no overlap).
  double _polygonArea(List<Offset> pts) {
    if (pts.length < 3) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() * 0.5;
  }

  /// _kUnifyT — t at which the disputed area's lerp toward kSea is "complete
  /// enough" that we replace the separate attacker-only + disputed renders
  /// with one unioned blue polygon. The 3-phase color lerp reaches full kSea
  /// at t=1.0; we unify slightly earlier at 0.95 so the merge is visible
  /// before the global fade-out (which begins at t=0.88 and finishes at 1.0)
  /// drives opacity to zero.
  static const double _kUnifyT = 0.95;

  @override
  void paint(Canvas canvas, Size size) {
    if (attackerRoute.isEmpty) return;

    final segs = attackerRoute.length - 1; // 4 segments for 5-point route
    final routeProgress = (t / _kRouteCompleteT).clamp(0.0, 1.0);
    final traveled = routeProgress * segs;
    final lassoIsClosed = traveled >= _kLassoCloseSegIdx;
    final fade = _globalFade(t);

    // 0. Inherited blocks from slide 1 — pre-filled, no animation.
    drawInheritedBlocks(canvas, inheritedPts);

    // 1. Static orange owned territory fills for this slide — always visible.
    drawFillColor(canvas, ownedBlock1, kAccent, 0.22 * fade);
    drawFillColor(canvas, ownedBlock2, kAccent, 0.22 * fade);

    // 2. Attacker trail: runner traces route until close; afterwards full trace stays.
    if (!lassoIsClosed) {
      drawTraceColor(canvas, attackerRoute, routeProgress, kSea);
      // Runner dot moving along the route.
      final segIdx = traveled.floor().clamp(0, segs - 1);
      final segFrac = (traveled - segIdx).clamp(0.0, 1.0);
      final pos = Offset.lerp(
        attackerRoute[segIdx],
        attackerRoute[(segIdx + 1).clamp(0, segs)],
        segFrac,
      )!;
      canvas.drawCircle(
          pos,
          12,
          Paint()
            ..color = kSea.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      canvas.drawCircle(pos, 4.5, Paint()..color = kSea);
      canvas.drawCircle(
          pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.8));
    } else {
      // Lasso outline stays visible.
      drawTraceColor(canvas, attackerRoute, 1.0, kSea.withValues(alpha: fade));
      // Runner continues past the close point, fades over 0.08 of t.
      final closeT = (_kLassoCloseSegIdx / segs) * _kRouteCompleteT;
      if (t < closeT + 0.08 && attackerRoute.length >= 2) {
        final contT = ((t - closeT) / 0.08).clamp(0.0, 1.0);
        final dir = attackerRoute.last - attackerRoute[attackerRoute.length - 2];
        final dirLen = dir.distance;
        if (dirLen > 0.01) {
          final unitDir = dir / dirLen;
          final pos = attackerRoute.last +
              unitDir * Curves.easeIn.transform(contT) * 22;
          final runnerFade = 1.0 - contT;
          canvas.drawCircle(
              pos,
              12,
              Paint()
                ..color = kSea.withValues(alpha: 0.25 * runnerFade)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
          canvas.drawCircle(
              pos, 4.5, Paint()..color = kSea.withValues(alpha: runnerFade));
          canvas.drawCircle(
              pos,
              1.8,
              Paint()
                ..color = Colors.white.withValues(alpha: 0.8 * runnerFade));
        }
      }
    }

    // ── Dispute detection ────────────────────────────────────────────────
    // A "genuine" dispute requires the clipped polygon to have ≥3 vertices
    // and a non-zero screen-space area. Touching at a single vertex or
    // along an edge yields a degenerate polygon (area ≈ 0) and is NOT a
    // dispute — the attacker simply claims their full lasso area in kSea.
    final hasGenuineDispute = disputedArea.length >= 3 &&
        _polygonArea(disputedArea) > 1.0; // > 1 px² in screen space

    // Build screen-space paths for the lasso and the disputed clip. The
    // attacker-only path = lasso \ disputed (set difference); if there is
    // no genuine dispute we treat the whole lasso as attacker-only.
    Path? attackerOnlyPath;
    Path? disputedPath;
    if (lassoIsClosed && attackerLasso.isNotEmpty) {
      final lassoPath = _makePoly(attackerLasso);
      if (hasGenuineDispute) {
        disputedPath = _makePoly(disputedArea);
        attackerOnlyPath =
            Path.combine(PathOperation.difference, lassoPath, disputedPath);
      } else {
        attackerOnlyPath = lassoPath;
      }
    }

    // 3a. Attacker-only kSea fill (instant — no ramp) the moment the lasso
    //     closes. Once the disputed VFX has resolved to blue (t >= _kUnifyT)
    //     we stop drawing the pieces separately and emit a single unioned
    //     polygon below so there is no seam between the two regions.
    if (lassoIsClosed && t < _kUnifyT && attackerOnlyPath != null) {
      canvas.drawPath(
        attackerOnlyPath,
        Paint()
          ..color = kSea.withValues(alpha: 0.55 * fade)
          ..style = PaintingStyle.fill,
      );
    }

    // 3b. Disputed fill — 3-phase claim VFX (only when there's a genuine
    //     overlap polygon and the unify threshold hasn't been crossed).
    if (hasGenuineDispute && t < _kUnifyT) {
      final dispOp = _disputedOpacity(traveled) * fade;
      if (dispOp > 0) {
        final dispColor = _disputedFillColor(t);
        drawFillColor(canvas, disputedArea, dispColor, dispOp);

        final dispPath = disputedPath ?? _makePoly(disputedArea);

        if (t >= 0.78 && t < 0.90) {
          // Border flash: dashed yellow/black alternating every ~80ms.
          final flashOnYellow = (((t - 0.78) / 0.01).floor() % 2 == 0);
          final borderColor =
              flashOnYellow ? const Color(0xFFFFD400) : Colors.black;
          final borderPaint = Paint()
            ..color = borderColor.withValues(alpha: dispOp.clamp(0.0, 1.0))
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
          _drawDashedPath(canvas, dispPath, 8.0, 5.0, borderPaint);
        } else if (t >= 0.90) {
          // Claimed: solid kSea border.
          final claimedBorderOp = dispOp.clamp(0.0, 1.0);
          canvas.drawPath(
            dispPath,
            Paint()
              ..color = kSea.withValues(alpha: claimedBorderOp)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke,
          );
        } else if (lassoIsClosed) {
          // Disputed phase: amber dashed border.
          final borderPaint = Paint()
            ..color = const Color(0xFFFFB200).withValues(alpha: dispOp.clamp(0.0, 1.0))
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
          _drawDashedPath(canvas, dispPath, 8.0, 5.0, borderPaint);
        }
      }
    }

    // 3c. Unified blue polygon — once the disputed VFX has resolved
    //     to kSea, render (attacker-only ∪ disputed) as a single shape so
    //     the seam disappears (one fill, one outer stroke). When there is
    //     no genuine dispute, attackerOnlyPath already equals the full
    //     lasso, so the union below collapses to that same shape and the
    //     branch still produces the correct unified blue polygon.
    if (lassoIsClosed && t >= _kUnifyT && attackerOnlyPath != null) {
      final unifiedPath = disputedPath != null
          ? Path.combine(PathOperation.union, attackerOnlyPath, disputedPath)
          : attackerOnlyPath;
      canvas.drawPath(
        unifiedPath,
        Paint()
          ..color = kSea.withValues(alpha: 0.70 * fade)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        unifiedPath,
        Paint()
          ..color = kSea.withValues(alpha: 0.90 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Ping burst when lasso closes — only on a genuine dispute (no flash
    // on a clean attacker claim).
    final pingT = traveled - _kLassoCloseSegIdx;
    if (pingT > 0 && pingT < 1.5 && hasGenuineDispute) {
      drawPings(canvas, disputedArea, (pingT / 1.5).clamp(0.0, 1.0));
    }

    // 4. Centroid of disputed area — used for labels. Only meaningful when
    //    a genuine dispute exists; otherwise labels are suppressed below.
    Offset disputedCentroid = Offset.zero;
    if (hasGenuineDispute) {
      double sumX = 0, sumY = 0;
      for (final pt in disputedArea) {
        sumX += pt.dx;
        sumY += pt.dy;
      }
      disputedCentroid =
          Offset(sumX / disputedArea.length, sumY / disputedArea.length);
    }

    // 5. "DISPUTED" label — t=0.62–0.75. Only on a genuine dispute.
    if (t > 0.62 && t < 0.75 && hasGenuineDispute) {
      final labelOpacity = t < 0.685
          ? ((t - 0.62) / 0.065).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.685) / 0.065)).clamp(0.0, 1.0);

      if (labelOpacity > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'DISPUTED',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 2,
              color: const Color(0xFFFFB200).withValues(alpha: labelOpacity),
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
            canvas,
            Offset(disputedCentroid.dx - tp.width / 2,
                disputedCentroid.dy - tp.height / 2));
      }
    }

    // 6. "CLAIMED" label — t=0.90–1.0 in kSea. Only on a genuine dispute.
    if (t > 0.90 && hasGenuineDispute) {
      final claimedOpacity = ((t - 0.90) / 0.05).clamp(0.0, 1.0) * fade;

      if (claimedOpacity > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'CLAIMED',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 2,
              color: kSea.withValues(alpha: claimedOpacity),
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
            canvas,
            Offset(disputedCentroid.dx - tp.width / 2,
                disputedCentroid.dy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroCaptureMapPainter old) =>
      old.t != t ||
      old.attackerRoute != attackerRoute ||
      old.attackerLasso != attackerLasso ||
      old.disputedArea != disputedArea ||
      old.ownedBlock1 != ownedBlock1 ||
      old.ownedBlock2 != ownedBlock2 ||
      old.inheritedPts != inheritedPts;
}

// ---------------------------------------------------------------------------
// 3. IntroRivalsMap — FORTIFY rejects attack (slide 3)
//    Owned orange territory + blue attacker mid-run creates a dispute.
//    At t≈0.50 defender activates FORTIFY: radial burst, disputed fill rejects,
//    orange pulses brighter, "CLAIM REJECTED" + "FORTIFIED" labels flash.
// ---------------------------------------------------------------------------
class IntroRivalsMap extends StatefulWidget {
  final Color accent;
  const IntroRivalsMap({required this.accent, super.key});
  @override
  State<IntroRivalsMap> createState() => _IntroRivalsMapState();
}

class _IntroRivalsMapState extends State<IntroRivalsMap>
    with TickerProviderStateMixin, _IntroMapMixin<IntroRivalsMap> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Blue attacker partial lasso — approaches from west along Carrer de Cuba
  // area (lat ~39.463), interrupted at t=0.45 by FORTIFY.
  static const _kAttackerRoute = [
    LatLng(39.4630, -0.3800), // 0: off-screen west
    LatLng(39.4630, -0.3790), // 1: enters map from west on Cuba
    LatLng(39.4630, -0.3780), // 2: heading east on Cuba
    LatLng(39.4631, -0.3773), // 3: approaches kS3OwnedBlock2 west edge
    LatLng(39.4630, -0.3767), // 4: overlapping — partial lasso interrupted
  ];

  // Partial disputed area at the overlap zone (appears at t=0.45, rejected at t=0.50).
  static const _kPartialDisputedArea = [
    LatLng(39.4630, -0.3773),
    LatLng(39.4628, -0.3771),
    LatLng(39.4629, -0.3768),
    LatLng(39.4632, -0.3769),
    LatLng(39.4632, -0.3773),
  ];

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _ownedBlock1 = [];
  List<Offset> _ownedBlock2 = [];
  List<Offset> _attackerRoute = [];
  List<Offset> _partialDisputed = [];

  List<Offset> _toScreen(List<LatLng> coords) => coords
      .map((ll) => mapCtrl.camera.latLngToScreenPoint(ll))
      .map((p) => Offset(p.x, p.y))
      .toList();

  void _onMapReady() {
    markMapReady(() {
      // Inherited blocks from slides 1+2 — rendered as pre-filled territory.
      _inheritedPts = IntroZones.kS2All
          .map((block) => _toScreen(block))
          .toList();
      _ownedBlock1 = _toScreen(IntroZones.kS3OwnedBlock1);
      _ownedBlock2 = _toScreen(IntroZones.kS3OwnedBlock2);
      _attackerRoute = _toScreen(_kAttackerRoute);
      _partialDisputed = _toScreen(_kPartialDisputedArea);
    });
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: _kIntroFadeDuration);
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat();
    Future.delayed(_kIntroFadeDelay, () {
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

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Stack(
        children: [
          _buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4665, -0.3768),
            zoom: 16.0,
            onReady: _onMapReady,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _IntroRivalsMapPainter(
                  t: _ctrl.value,
                  accent: widget.accent,
                  inheritedPts: _inheritedPts,
                  ownedBlock1: _ownedBlock1,
                  ownedBlock2: _ownedBlock2,
                  attackerRoute: _attackerRoute,
                  partialDisputed: _partialDisputed,
                ),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

class _IntroRivalsMapPainter extends CustomPainter with _IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> ownedBlock1;
  final List<Offset> ownedBlock2;
  final List<Offset> attackerRoute;
  final List<Offset> partialDisputed;

  _IntroRivalsMapPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.ownedBlock1,
    required this.ownedBlock2,
    required this.attackerRoute,
    required this.partialDisputed,
  });

  // Phase boundaries
  static const double _attackerEndT = 0.45;
  static const double _partialDisputeT = 0.45;
  static const double _fortifyT = 0.50;

  // Orange territory pulse during FORTIFY: 0.22 → 0.45 → 0.30
  double _ownedOpacity(double t) {
    if (t < _fortifyT) return 0.22;
    if (t < _fortifyT + 0.05) {
      // ramp up to 0.45
      return 0.22 + ((t - _fortifyT) / 0.05) * 0.23;
    }
    if (t < _fortifyT + 0.10) {
      // ramp down to 0.30
      return 0.45 - ((t - (_fortifyT + 0.05)) / 0.05) * 0.15;
    }
    if (t < 0.90) return 0.30;
    return (0.30 * (1.0 - (t - 0.90) / 0.10)).clamp(0.0, 0.30);
  }

  // Disputed opacity — appears at 0.45, rejected (fades) at 0.50
  double _disputedOpacity(double t) {
    if (t < _partialDisputeT) return 0.0;
    if (t < _fortifyT) {
      return ((t - _partialDisputeT) / 0.05) * 0.20;
    }
    // FORTIFY rejection: rapid fade over 0.05t
    return (0.20 * (1.0 - (t - _fortifyT) / 0.05)).clamp(0.0, 0.20);
  }

  // Centroid of owned territory for shield rings
  Offset _ownedCentroid() {
    if (ownedBlock1.isEmpty) return Offset.zero;
    final all = [...ownedBlock1, ...ownedBlock2];
    double sumX = 0, sumY = 0;
    for (final pt in all) {
      sumX += pt.dx;
      sumY += pt.dy;
    }
    return Offset(sumX / all.length, sumY / all.length);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (ownedBlock1.isEmpty) return;

    final centroid = _ownedCentroid();

    // 0. Inherited blocks from slides 1+2 — pre-filled, no animation.
    drawInheritedBlocks(canvas, inheritedPts);

    // 1. Static orange owned territory — opacity pulses during FORTIFY.
    final ownedOp = _ownedOpacity(t);
    drawFillColor(canvas, ownedBlock1, kAccent, ownedOp);
    drawFillColor(canvas, ownedBlock2, kAccent, ownedOp);

    // 2. Attacker trace + runner dot (t=0.0–0.45).
    if (t < _attackerEndT && attackerRoute.isNotEmpty) {
      final routeProgress = (t / _attackerEndT).clamp(0.0, 1.0);
      drawTraceColor(canvas, attackerRoute, routeProgress, kSea);
      // Runner dot
      final segs = attackerRoute.length - 1;
      final totalLen = routeProgress * segs;
      final segIdx = totalLen.floor().clamp(0, segs - 1);
      final segFrac = (totalLen - segIdx).clamp(0.0, 1.0);
      final pos = Offset.lerp(
        attackerRoute[segIdx],
        attackerRoute[(segIdx + 1).clamp(0, segs)],
        segFrac,
      )!;
      canvas.drawCircle(
          pos,
          12,
          Paint()
            ..color = kSea.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      canvas.drawCircle(pos, 4.5, Paint()..color = kSea);
      canvas.drawCircle(
          pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.8));
    }

    // 3. Partial disputed area fill.
    drawFillColor(canvas, partialDisputed, kAccent2, _disputedOpacity(t));

    // 4. FORTIFY activation effects (t=0.50+).
    if (t >= _fortifyT) {
      // White flash ring expanding from centroid.
      final flashT = ((t - _fortifyT) / 0.08).clamp(0.0, 1.0);
      if (flashT < 1.0) {
        canvas.drawCircle(
            centroid,
            flashT * 120,
            Paint()
              ..color = Colors.white.withValues(alpha: (1.0 - flashT) * 0.5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0);
      }

      // 3 concentric expanding shield rings in kAccent orange.
      for (int i = 0; i < 3; i++) {
        final ringT = ((t - _fortifyT - i * 0.06) / 0.18).clamp(0.0, 1.0);
        if (ringT > 0) {
          canvas.drawCircle(
              centroid,
              ringT * 80,
              Paint()
                ..color = kAccent.withValues(alpha: (1 - ringT) * 0.5)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.0);
        }
      }
    }

    // 5. "CLAIM REJECTED" label — t=0.52–0.70.
    if (t > 0.52 && t < 0.70 && partialDisputed.isNotEmpty) {
      double sumX = 0, sumY = 0;
      for (final pt in partialDisputed) {
        sumX += pt.dx;
        sumY += pt.dy;
      }
      final labelCenter = Offset(sumX / partialDisputed.length, sumY / partialDisputed.length);

      final rejOpacity = t < 0.61
          ? ((t - 0.52) / 0.09).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.61) / 0.09)).clamp(0.0, 1.0);
      if (rejOpacity > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'CLAIM REJECTED',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              letterSpacing: 2,
              color: kAccent.withValues(alpha: rejOpacity),
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(labelCenter.dx - tp.width / 2, labelCenter.dy - tp.height / 2 - 14));
      }
    }

    // 6. "FORTIFIED" label — t=0.55–0.80.
    if (t > 0.55 && t < 0.80 && ownedBlock1.isNotEmpty) {
      final fortOpacity = t < 0.675
          ? ((t - 0.55) / 0.125).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.675) / 0.125)).clamp(0.0, 1.0);
      if (fortOpacity > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'FORTIFIED',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              letterSpacing: 1.5,
              color: kFgMuted.withValues(alpha: fortOpacity),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(centroid.dx - tp.width / 2, centroid.dy + 12));
      }
    }

    // 7. "LIVE" pulse indicator (top-right).
    final livePulse = (math.sin(t * math.pi * 8)).abs();
    final liveTp = TextPainter(
      text: TextSpan(
        text: '● LIVE',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9,
          letterSpacing: 1.5,
          color: kAccent.withValues(alpha: 0.6 + livePulse * 0.4),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    liveTp.paint(canvas, Offset(size.width - liveTp.width - 12, 10));
  }

  @override
  bool shouldRepaint(_IntroRivalsMapPainter old) =>
      old.t != t ||
      old.ownedBlock1 != ownedBlock1 ||
      old.ownedBlock2 != ownedBlock2 ||
      old.attackerRoute != attackerRoute ||
      old.partialDisputed != partialDisputed ||
      old.inheritedPts != inheritedPts;
}

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

const Color _kRunnerCPink = Color(0xFFFF3B7A);

class IntroFlagDropMap extends StatefulWidget {
  final Color accent;
  const IntroFlagDropMap({required this.accent, super.key});
  @override
  State<IntroFlagDropMap> createState() => _IntroFlagDropMapState();
}

class _IntroFlagDropMapState extends State<IntroFlagDropMap>
    with TickerProviderStateMixin, _IntroMapMixin<IntroFlagDropMap> {
  // ── Fixed coordinates ──────────────────────────────────────────────────────
  static const _kDropCoord = LatLng(39.4553, -0.3510);

  // Routes below are OSM-verified — every interior waypoint lies on a real
  // street centerline (Overpass API, queried 2026-06-05 against Valencia
  // bbox 39.4450..39.4640 / -0.3650..-0.3380). The final snap from the last
  // on-street node to _kDropCoord crosses the pedestrian plaza inside the
  // Ciutat de les Arts complex — the drop sits on a pedestrian island that
  // no vehicular street reaches directly, so a short plaza-crossing is
  // unavoidable and physically walkable.

  // Runner A — NW approach via Passeig de l'Albereda.
  // The Albereda runs N→S along the dry Turia riverbed and curves SE around
  // the Ciutat de les Arts, reaching ~248m of the drop on its eastern arc.
  static const _kRouteA = [
    LatLng(39.46400, -0.35850), // 0: off-screen NW start
    LatLng(39.46273, -0.35757), // 1: Passeig de l'Albereda — north
    LatLng(39.46037, -0.35514), // 2: Passeig de l'Albereda — mid descent SE
    LatLng(39.45774, -0.35018), // 3: Passeig de l'Albereda — south curve
    LatLng(39.45635, -0.34842), // 4: Passeig de l'Albereda — east approach
    LatLng(39.4553,  -0.3510),  // 5: DROP POINT (plaza snap)
  ];

  // Runner B — NE approach along Carrer de Luis García-Berlanga Martí.
  // This avenue runs E→W on the south flank of the Ciutat de les Arts,
  // passing within ~310m of the drop at its closest point.
  static const _kRouteB = [
    LatLng(39.45650, -0.33800), // 0: off-screen NE start
    LatLng(39.45546, -0.34164), // 1: García-Berlanga — east end
    LatLng(39.45531, -0.34449), // 2: García-Berlanga — mid stretch
    LatLng(39.45681, -0.34791), // 3: García-Berlanga — closest pass to drop
    LatLng(39.4553,  -0.3510),  // 4: DROP POINT (plaza snap)
  ];

  // Runner C — SW approach along Avinguda d'Antonio Ferrandis (Actor)
  // then north on Avinguda del Professor López Piñero.
  // Antonio Ferrandis runs W→E south of the Ciutat de les Arts; López Piñero
  // turns N from there and approaches the drop within ~181m.
  static const _kRouteC = [
    LatLng(39.44700, -0.36250), // 0: off-screen SW start
    LatLng(39.44924, -0.36103), // 1: Av. d'Antonio Ferrandis — west end
    LatLng(39.45077, -0.35818), // 2: Av. d'Antonio Ferrandis — mid (heading E)
    LatLng(39.45245, -0.35358), // 3: Av. d'Antonio Ferrandis — east end
    LatLng(39.45390, -0.35209), // 4: Av. del Professor López Piñero — north
    LatLng(39.4553,  -0.3510),  // 5: DROP POINT (plaza snap)
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
    _fadeCtrl = AnimationController(vsync: this, duration: _kIntroFadeDuration);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    Future.delayed(_kIntroFadeDelay, () {
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
          _buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4545, -0.3520),
            zoom: 14.0,
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

class _IntroFlagDropMapPainter extends CustomPainter with _IntroPainterHelpers {
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
    _drawStartPulse(canvas, routeC.first, _kRunnerCPink);

    // ── 2. Runner traces ─────────────────────────────────────────────────────
    final progressA = _runnerProgress(_arrivalA);
    final progressB = _runnerProgress(_arrivalB);
    final progressC = _runnerProgress(_arrivalC);

    _drawRouteTrace(canvas, routeA, progressA, kAccent, fade);
    _drawRouteTrace(canvas, routeB, progressB, kSea, fade);
    _drawRouteTrace(canvas, routeC, progressC, _kRunnerCPink, fade);

    // ── 3. Runner dots ───────────────────────────────────────────────────────
    // Show dot while en route; once arrived hold at drop point until fade.
    final posA = progressA < 1.0 ? _posOnRoute(routeA, progressA) : dropPt;
    final posB = progressB < 1.0 ? _posOnRoute(routeB, progressB) : dropPt;
    final posC = progressC < 1.0 ? _posOnRoute(routeC, progressC) : dropPt;

    // Only draw runner if before arrival or if still fading out post-arrival.
    _drawRunnerDot(canvas, posA, kAccent, fade);
    _drawRunnerDot(canvas, posB, kSea, fade);
    _drawRunnerDot(canvas, posC, _kRunnerCPink, fade);

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
      _drawLabel(canvas, 'SPRINT!', sprintPos, _kRunnerCPink,
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
    with TickerProviderStateMixin, _IntroMapMixin<IntroFortifyMap> {
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
    _fadeCtrl = AnimationController(vsync: this, duration: _kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 20));
    Future.delayed(_kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    _ctrl.addListener(_onTick);
    _loopController(_ctrl, mounted: () => mounted);
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
          _buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4595, -0.3756),
            zoom: 16.0,
            onReady: _onMapReady,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _IntroFortifyMapPainter(
                  t: _ctrl.value,
                  level: _level,
                  accent: widget.accent,
                  inheritedPts: _inheritedPts,
                  claimedChunk: _claimedChunk,
                  approachPts: _approachPts,
                  loopPts: _loopPts,
                  exitPt: _exitPt,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          Positioned(
            top: 64,
            right: 16,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                // Hide during approach (level 0) and exit phase (t ≥ 0.75).
                if (_level < 1 || _ctrl.value >= _kLoopEndT) {
                  return const SizedBox.shrink();
                }
                return Text(
                  'LVL $_level',
                  style: GoogleFonts.bebasNeue(
                    fontSize: 28,
                    color: kSea,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroFortifyMapPainter extends CustomPainter with _IntroPainterHelpers {
  final double t;
  final int level;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> claimedChunk;
  final List<Offset> approachPts;
  final List<Offset> loopPts;
  final Offset exitPt;

  _IntroFortifyMapPainter({
    required this.t,
    required this.level,
    required this.accent,
    required this.inheritedPts,
    required this.claimedChunk,
    required this.approachPts,
    required this.loopPts,
    required this.exitPt,
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

    // 3. Runner dot — phase 1: approach polyline; phase 2: 4-lap loop circuit;
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
      old.claimedChunk != claimedChunk ||
      old.approachPts != approachPts ||
      old.loopPts != loopPts ||
      old.exitPt != exitPt;
}

// ---------------------------------------------------------------------------
// 6. IntroDefenseMap — shield rejects attacker (EARN YOUR EDGE slide)
// ---------------------------------------------------------------------------
class IntroDefenseMap extends StatefulWidget {
  final Color accent;
  const IntroDefenseMap({required this.accent, super.key});
  @override
  State<IntroDefenseMap> createState() => _IntroDefenseMapState();
}

class _IntroDefenseMapState extends State<IntroDefenseMap>
    with TickerProviderStateMixin, _IntroMapMixin<IntroDefenseMap> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Same attacker route and lasso as IntroCaptureMap (Change 2).
  static const _kAttackerRoute = [
    LatLng(39.4588, -0.3795), // 0: off-screen south
    LatLng(39.4608, -0.3785), // 1: Buenos Aires S
    LatLng(39.4613, -0.3777), // 2: Buenos Aires mid
    LatLng(39.4616, -0.3768), // 3: TURN EAST
    LatLng(39.4616, -0.3752), // 4: NE corner
    LatLng(39.4604, -0.3752), // 5: SE corner
    LatLng(39.4604, -0.3760), // 6: TURN WEST
    LatLng(39.4610, -0.3783), // 7: LASSO CLOSES
  ];

  static const _kDisputedCoords = [
    LatLng(39.4616, -0.3768), // B — NW
    LatLng(39.4616, -0.3752), // E — NE
    LatLng(39.4604, -0.3760), // F — SE
    LatLng(39.4611, -0.3764), // G — SW interior
  ];

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _attackerRoute = [];
  List<Offset> _disputedArea = [];

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
      _attackerRoute = _kAttackerRoute.map(toScreen).toList();
      _disputedArea = _kDisputedCoords.map(toScreen).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: _kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    Future.delayed(_kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    _loopController(_ctrl, mounted: () => mounted);
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
          _buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4627, -0.3756),
            zoom: 16.0,
            onReady: _onMapReady,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _IntroDefenseMapPainter(
                  t: _ctrl.value,
                  accent: widget.accent,
                  inheritedPts: _inheritedPts,
                  attackerRoute: _attackerRoute,
                  disputedArea: _disputedArea,
                ),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

class _IntroDefenseMapPainter extends CustomPainter with _IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> attackerRoute;
  final List<Offset> disputedArea;

  _IntroDefenseMapPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.attackerRoute,
    required this.disputedArea,
  });

  // Timeline:
  //   0.00–0.55: attacker route + lasso draws; disputed amber fill at lasso close (~0.50).
  //   0.55–0.65: "SHIELD ACTIVATED" stamp top-center; white flash ring at chunk centroid.
  //   0.65–0.85: 3 hex shield rings expand; attacker lerps back south; route fades.
  //   0.85–1.00: disputed fill → orange; "CLAIM REJECTED" + "DEFENDED FROM HOME" labels.
  static const double _kRouteCompleteT = 0.55;
  static const int _kLassoCloseSegIdx = 6;

  Offset _disputedCentroid() {
    if (disputedArea.isEmpty) return Offset.zero;
    double sumX = 0, sumY = 0;
    for (final pt in disputedArea) {
      sumX += pt.dx;
      sumY += pt.dy;
    }
    return Offset(sumX / disputedArea.length, sumY / disputedArea.length);
  }

  /// Draw a regular hexagon centered at [center] with given [radius].
  void _drawHexRing(Canvas canvas, Offset center, double radius, Paint paint) {
    if (radius <= 0) return;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (attackerRoute.isEmpty) return;

    final segs = attackerRoute.length - 1;
    final centroid = _disputedCentroid();

    // 0. Inherited blocks — pre-filled orange.
    drawInheritedBlocks(canvas, inheritedPts);

    // Phase 1: 0.00–0.55 — attacker runs and lasso forms.
    final routeProgress = (t / _kRouteCompleteT).clamp(0.0, 1.0);
    final traveled = routeProgress * segs;
    final lassoIsClosed = traveled >= _kLassoCloseSegIdx;

    // Route fade after shield activates.
    final routeFade = t < 0.65 ? 1.0 : (1.0 - (t - 0.65) / 0.20).clamp(0.0, 1.0);

    if (routeFade > 0) {
      drawTraceColor(canvas, attackerRoute, routeProgress, kSea.withValues(alpha: routeFade));
    }

    // Attacker runner dot: moves along route until lasso close, then lerps back south.
    if (t < 0.65) {
      if (!lassoIsClosed && attackerRoute.isNotEmpty) {
        final segIdx = traveled.floor().clamp(0, segs - 1);
        final segFrac = (traveled - segIdx).clamp(0.0, 1.0);
        final pos = Offset.lerp(
          attackerRoute[segIdx],
          attackerRoute[(segIdx + 1).clamp(0, segs)],
          segFrac,
        )!;
        canvas.drawCircle(
            pos, 12,
            Paint()
              ..color = kSea.withValues(alpha: 0.25)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        canvas.drawCircle(pos, 4.5, Paint()..color = kSea);
        canvas.drawCircle(pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.8));
      }
    } else if (t < 0.85) {
      // Lerp attacker back to off-screen south.
      final retreatT = ((t - 0.65) / 0.20).clamp(0.0, 1.0);
      final startPos = attackerRoute.isNotEmpty ? attackerRoute.last : Offset.zero;
      final endPos = attackerRoute.isNotEmpty ? attackerRoute.first : Offset.zero;
      final pos = Offset.lerp(startPos, endPos, retreatT)!;
      final runnerFade = (1.0 - retreatT).clamp(0.0, 1.0);
      if (runnerFade > 0) {
        canvas.drawCircle(
            pos, 12,
            Paint()
              ..color = kSea.withValues(alpha: 0.25 * runnerFade)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        canvas.drawCircle(pos, 4.5, Paint()..color = kSea.withValues(alpha: runnerFade));
      }
    }

    // Disputed amber fill (0.50–0.85), then snaps back to orange (0.85+).
    if (lassoIsClosed && disputedArea.isNotEmpty) {
      final dispRamp = ((traveled - _kLassoCloseSegIdx) / 0.3).clamp(0.0, 1.0);
      if (t < 0.85) {
        drawFillColor(canvas, disputedArea, const Color(0xFFFFB200), dispRamp * 0.35);
      } else {
        final snapT = ((t - 0.85) / 0.05).clamp(0.0, 1.0);
        final dispColor = Color.lerp(const Color(0xFFFFB200), kAccent, snapT)!;
        drawFillColor(canvas, disputedArea, dispColor, 0.35);
      }
    }

    // Phase 2: 0.55–0.65 — "SHIELD ACTIVATED" stamp + white flash ring.
    if (t >= 0.55 && t < 0.75) {
      final shieldFade = t < 0.60
          ? ((t - 0.55) / 0.05).clamp(0.0, 1.0)
          : t < 0.70 ? 1.0
          : (1.0 - (t - 0.70) / 0.05).clamp(0.0, 1.0);
      if (shieldFade > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'SHIELD ACTIVATED',
            style: GoogleFonts.bebasNeue(
              fontSize: 32,
              color: accent.withValues(alpha: shieldFade),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width);
        tp.paint(canvas, Offset((size.width - tp.width) / 2, 48));
      }
    }

    // White flash ring at centroid when shield activates.
    if (t >= 0.55 && t < 0.65 && centroid != Offset.zero) {
      final flashT = ((t - 0.55) / 0.10).clamp(0.0, 1.0);
      canvas.drawCircle(
          centroid,
          flashT * 100,
          Paint()
            ..color = Colors.white.withValues(alpha: (1.0 - flashT) * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
    }

    // Phase 3: 0.65–0.85 — 3 concentric hex shield rings.
    if (t >= 0.65 && centroid != Offset.zero) {
      for (int i = 0; i < 3; i++) {
        final ringT = ((t - 0.65 - i * 0.06) / 0.18).clamp(0.0, 1.0);
        if (ringT > 0) {
          _drawHexRing(
              canvas,
              centroid,
              ringT * 80,
              Paint()
                ..color = accent.withValues(alpha: (1.0 - ringT) * 0.5)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.0);
        }
      }
    }

    // Phase 4: 0.85–1.00 — "CLAIM REJECTED" + "DEFENDED FROM HOME".
    if (t >= 0.85) {
      final labelFade = ((t - 0.85) / 0.05).clamp(0.0, 1.0);

      if (labelFade > 0 && size.width > 0) {
        final tp1 = TextPainter(
          text: TextSpan(
            text: 'CLAIM REJECTED',
            style: GoogleFonts.bebasNeue(
              fontSize: 18,
              color: accent.withValues(alpha: labelFade),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp1.paint(canvas, const Offset(12, 12));

        final tp2 = TextPainter(
          text: TextSpan(
            text: 'DEFENDED FROM HOME',
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              color: accent.withValues(alpha: labelFade),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp2.paint(canvas, Offset(12, 12 + tp1.height + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroDefenseMapPainter old) =>
      old.t != t ||
      old.attackerRoute != attackerRoute ||
      old.disputedArea != disputedArea ||
      old.inheritedPts != inheritedPts;
}

// ---------------------------------------------------------------------------
// 6C. IntroDefenseMapC — SHIELD Variant C (Cinematic Flash + Shatter)
// ---------------------------------------------------------------------------
// Same defense-scene scaffold as IntroDefenseMap, but the shield activation
// reads as a single cinematic strike:
//   - 120ms white screen flash
//   - SHIELD stamp scales 0.3→1.0 at the disputed centroid
//   - attacker's blue lasso shatters into 7 outward-flying shards
class IntroDefenseMapC extends StatefulWidget {
  final Color accent;
  const IntroDefenseMapC({required this.accent, super.key});
  @override
  State<IntroDefenseMapC> createState() => _IntroDefenseMapCState();
}

class _IntroDefenseMapCState extends State<IntroDefenseMapC>
    with TickerProviderStateMixin, _IntroMapMixin<IntroDefenseMapC> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Player 3 route — Renfe Norte → adjacent block lasso (per spec).
  static const _kP3RouteC = [
    LatLng(39.4658, -0.3766), // 0: Renfe Norte entrance
    LatLng(39.4648, -0.3760), // 1
    LatLng(39.4638, -0.3758), // 2
    LatLng(39.4631, -0.3758), // 3: lasso start
    LatLng(39.4631, -0.3750), // 4
    LatLng(39.4623, -0.3750), // 5
    LatLng(39.4623, -0.3758), // 6: closes
  ];

  static const _kDisputedC = [
    LatLng(39.4631, -0.3758),
    LatLng(39.4631, -0.3752),
    LatLng(39.4626, -0.3752),
    LatLng(39.4626, -0.3758),
  ];

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _attackerRoute = [];
  List<Offset> _disputedArea = [];

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
      _attackerRoute = _kP3RouteC.map(toScreen).toList();
      _disputedArea = _kDisputedC.map(toScreen).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: _kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 9));
    Future.delayed(_kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    _loopController(_ctrl, mounted: () => mounted);
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
          _buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4635, -0.3758),
            zoom: 16.0,
            onReady: _onMapReady,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _IntroDefenseMapCPainter(
                  t: _ctrl.value,
                  accent: widget.accent,
                  inheritedPts: _inheritedPts,
                  attackerRoute: _attackerRoute,
                  disputedArea: _disputedArea,
                ),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

class _IntroDefenseMapCPainter extends CustomPainter with _IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> attackerRoute;
  final List<Offset> disputedArea;

  _IntroDefenseMapCPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.attackerRoute,
    required this.disputedArea,
  });

  // Timeline (9s loop, t ∈ [0,1]):
  //   0.00–0.20  inherited orange territory only
  //   0.10–0.40  P3 (pink-red) runs from Renfe Norte; lasso draws
  //   0.40–0.55  dispute phase: amber fill + dashed amber border
  //   0.55–0.57  120ms white screen flash (alpha 0.85→0)
  //   0.55–0.60  SHIELD stamp scales 0.3→1.0, alpha 0→1
  //   0.60–0.68  SHIELD stamp held at 1.0
  //   0.68–0.70  SHIELD stamp fades 1→0
  //   0.65–0.80  7 lasso shards fly outward and fade
  //   0.85–1.00  snap to orange, DEFENDED label
  static const double _kRouteCompleteT = 0.40;
  static const int _kLassoCloseSegIdx = 6;
  static const Color _kP3 = Color(0xFFFF3B7A);

  Offset _disputedCentroid() {
    if (disputedArea.isEmpty) return Offset.zero;
    double sumX = 0, sumY = 0;
    for (final pt in disputedArea) {
      sumX += pt.dx;
      sumY += pt.dy;
    }
    return Offset(sumX / disputedArea.length, sumY / disputedArea.length);
  }

  /// Draw a dashed polygon outline (used for the amber dispute border).
  void _drawDashedPolygon(
      Canvas canvas, List<Offset> pts, Paint paint,
      {double dash = 6.0, double gap = 4.0}) {
    if (pts.length < 2) return;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final segLen = (b - a).distance;
      if (segLen <= 0) continue;
      final dir = (b - a) / segLen;
      double travelled = 0;
      while (travelled < segLen) {
        final start = a + dir * travelled;
        final end = a + dir * (travelled + dash).clamp(0.0, segLen);
        canvas.drawLine(start, end, paint);
        travelled += dash + gap;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (attackerRoute.isEmpty) return;

    final segs = attackerRoute.length - 1;
    final centroid = _disputedCentroid();

    // 0. Inherited blocks — pre-filled orange.
    drawInheritedBlocks(canvas, inheritedPts);

    // Phase 1: 0.10–0.40 — P3 runs and lasso forms.
    // Map [0.10, 0.40] → [0, 1] for route progress.
    final routeProgress = t < 0.10
        ? 0.0
        : ((t - 0.10) / (_kRouteCompleteT - 0.10)).clamp(0.0, 1.0);
    final traveled = routeProgress * segs;
    final lassoIsClosed = traveled >= _kLassoCloseSegIdx;

    // Route fade: visible while drawing; held until shield fires; gone after shatter.
    final routeFade = t < 0.65
        ? 1.0
        : t < 0.66
            ? (1.0 - (t - 0.65) / 0.01).clamp(0.0, 1.0)
            : 0.0;

    if (routeFade > 0 && routeProgress > 0) {
      drawTraceColor(canvas, attackerRoute, routeProgress, _kP3.withValues(alpha: routeFade));
    }

    // P3 runner dot — visible while running (0.10–0.40), then lerps back at retreat.
    if (t >= 0.10 && t < 0.55) {
      if (!lassoIsClosed) {
        final segIdx = traveled.floor().clamp(0, segs - 1);
        final segFrac = (traveled - segIdx).clamp(0.0, 1.0);
        final pos = Offset.lerp(
          attackerRoute[segIdx],
          attackerRoute[(segIdx + 1).clamp(0, segs)],
          segFrac,
        )!;
        canvas.drawCircle(
            pos,
            12,
            Paint()
              ..color = _kP3.withValues(alpha: 0.25)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        canvas.drawCircle(pos, 4.5, Paint()..color = _kP3);
        canvas.drawCircle(pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.8));
      }
    } else if (t >= 0.55 && t < 0.75) {
      // P3 retreats off-screen south after shield fires.
      final retreatT = ((t - 0.55) / 0.20).clamp(0.0, 1.0);
      final startPos = attackerRoute.last;
      final endPos = attackerRoute.first;
      final pos = Offset.lerp(startPos, endPos, retreatT)!;
      final runnerFade = (1.0 - retreatT).clamp(0.0, 1.0);
      if (runnerFade > 0) {
        canvas.drawCircle(
            pos,
            12,
            Paint()
              ..color = _kP3.withValues(alpha: 0.25 * runnerFade)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        canvas.drawCircle(pos, 4.5, Paint()..color = _kP3.withValues(alpha: runnerFade));
      }
    }

    // Phase 2: 0.40–0.55 — dispute phase (amber fill + dashed amber border).
    // Amber fill persists through to 0.85, then snaps to orange.
    if (lassoIsClosed && disputedArea.isNotEmpty) {
      const amber = Color(0xFFFFB200);
      if (t < 0.85) {
        // Amber fill ramps in 0.40 → 0.55, then holds.
        final fillRamp = ((t - 0.40) / 0.15).clamp(0.0, 1.0);
        drawFillColor(canvas, disputedArea, amber, fillRamp * 0.35);

        // Dashed amber border — visible during dispute (0.40–0.65).
        if (t < 0.65) {
          final borderAlpha = t < 0.55
              ? ((t - 0.40) / 0.15).clamp(0.0, 1.0)
              : (1.0 - (t - 0.55) / 0.10).clamp(0.0, 1.0);
          if (borderAlpha > 0) {
            _drawDashedPolygon(
                canvas,
                disputedArea,
                Paint()
                  ..color = amber.withValues(alpha: borderAlpha * 0.9)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2.0);
          }
        }
      } else {
        // Snap to orange at 0.85.
        final snapT = ((t - 0.85) / 0.05).clamp(0.0, 1.0);
        final dispColor = Color.lerp(amber, kAccent, snapT)!;
        drawFillColor(canvas, disputedArea, dispColor, 0.35);
      }
    }

    // Phase 3a: 0.55–0.57 — 120ms full-canvas white flash.
    if (t >= 0.55 && t < 0.57) {
      final flashAlpha = ((1.0 - (t - 0.55) / 0.02).clamp(0.0, 1.0)) * 0.85;
      if (flashAlpha > 0) {
        canvas.drawRect(
            Offset.zero & size,
            Paint()..color = Colors.white.withValues(alpha: flashAlpha));
      }
    }

    // Phase 3b: 0.55–0.70 — SHIELD stamp scales in at centroid.
    if (t >= 0.55 && t < 0.70 && centroid != Offset.zero) {
      final scaleT = t < 0.60
          ? ((t - 0.55) / 0.05).clamp(0.0, 1.0) * 0.7 + 0.3
          : 1.0;
      final stampAlpha = t < 0.60
          ? ((t - 0.55) / 0.05).clamp(0.0, 1.0)
          : t < 0.68
              ? 1.0
              : (1.0 - (t - 0.68) / 0.02).clamp(0.0, 1.0);
      if (stampAlpha > 0) {
        canvas.save();
        canvas.translate(centroid.dx, centroid.dy);
        canvas.scale(scaleT);
        canvas.translate(-centroid.dx, -centroid.dy);
        final tp = TextPainter(
          text: TextSpan(
            text: 'SHIELD',
            style: GoogleFonts.bebasNeue(
              fontSize: 48,
              color: kAccent.withValues(alpha: stampAlpha),
              shadows: [
                Shadow(
                  color: kAccent.withValues(alpha: stampAlpha * 0.6),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(centroid.dx - tp.width / 2, centroid.dy - tp.height / 2),
        );
        canvas.restore();
      }
    }

    // Phase 4: 0.65–0.80 — 7 lasso shards fly outward and fade.
    if (t >= 0.65 && t < 0.80 && centroid != Offset.zero) {
      final shardT = ((t - 0.65) / 0.15).clamp(0.0, 1.0);
      final shardAlpha = (1.0 - shardT).clamp(0.0, 1.0);
      if (shardAlpha > 0) {
        final shardPaint = Paint()
          ..color = kSea.withValues(alpha: shardAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 7; i++) {
          final angle = (2 * math.pi / 7) * i;
          final dir = Offset(math.cos(angle), math.sin(angle));
          final origin = centroid + dir * (shardT * 55);
          final end = origin + dir * 18;
          canvas.drawLine(origin, end, shardPaint);
        }
      }
    }

    // Phase 5: 0.85–1.00 — DEFENDED label.
    if (t >= 0.85) {
      final labelFade = ((t - 0.85) / 0.05).clamp(0.0, 1.0);
      if (labelFade > 0 && size.width > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'DEFENDED',
            style: GoogleFonts.bebasNeue(
              fontSize: 22,
              color: accent.withValues(alpha: labelFade),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, const Offset(12, 12));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroDefenseMapCPainter old) =>
      old.t != t ||
      old.attackerRoute != attackerRoute ||
      old.disputedArea != disputedArea ||
      old.inheritedPts != inheritedPts;
}

// ---------------------------------------------------------------------------
// 7. IntroPhysicalEventsMap — 3 runners race to finish (Real Events slide)
//    Pure CustomPaint — no flutter_map.
// ---------------------------------------------------------------------------
class IntroPhysicalEventsMap extends StatefulWidget {
  final Color accent;
  const IntroPhysicalEventsMap({required this.accent, super.key});
  @override
  State<IntroPhysicalEventsMap> createState() => _IntroPhysicalEventsMapState();
}

class _IntroPhysicalEventsMapState extends State<IntroPhysicalEventsMap>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: _kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    Future.delayed(_kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    _loopController(_ctrl, mounted: () => mounted);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _IntroPhysicalEventsPainter(
            t: _ctrl.value,
            accent: widget.accent,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _IntroPhysicalEventsPainter extends CustomPainter {
  final double t;
  final Color accent;

  const _IntroPhysicalEventsPainter({required this.t, required this.accent});

  static const _kRunnerColors = [kAccent, kSea, kAccent2];
  static const _kStartOffsets = [0.15, 0.10, 0.05]; // x-factor stagger at t=0

  void _drawHexGrid(Canvas canvas, Size size) {
    const double hexR = 22.0;
    final paint = Paint()
      ..color = kAccent2.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    final double hexH = hexR * math.sqrt(3);
    int col = 0;
    for (double x = -hexR; x < size.width + hexR * 2; x += hexR * 1.5, col++) {
      final yOffset = (col % 2 == 0) ? 0.0 : hexH / 2;
      for (double y = -hexH + yOffset; y < size.height + hexH; y += hexH) {
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = (math.pi / 3) * i - math.pi / 2;
          final px = x + hexR * math.cos(angle);
          final py = y + hexR * math.sin(angle);
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawRunner(Canvas canvas, Offset pos, Color color, double alpha) {
    if (alpha <= 0) return;
    // Head.
    canvas.drawCircle(pos.translate(0, -20), 8,
        Paint()..color = color.withValues(alpha: alpha));
    // Body.
    canvas.drawRect(
        Rect.fromCenter(center: pos.translate(0, -6), width: 16, height: 28),
        Paint()..color = color.withValues(alpha: alpha));
    // Legs (diagonal lines).
    final legPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        pos.translate(-5, 8), pos.translate(-12, 28), legPaint);
    canvas.drawLine(
        pos.translate(5, 8), pos.translate(12, 28), legPaint);
  }

  void _drawFinishLine(Canvas canvas, double x, Size size) {
    const checkerH = 8.0;
    const checkerW = 12.0;
    int row = 0;
    for (double y = 0; y < size.height; y += checkerH, row++) {
      for (int col = 0; col < 2; col++) {
        final isDark = (row + col) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x + col * checkerW, y, checkerW, checkerH),
          Paint()
            ..color = isDark ? Colors.black : Colors.white
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  void _drawPodium(Canvas canvas, Offset bottomCenter, double opacity) {
    if (opacity <= 0) return;
    final heights = [60.0, 80.0, 40.0]; // 2nd, 1st, 3rd
    final labels = ['2', '1', '3'];
    const w = 36.0;
    final strokePaint = Paint()
      ..color = kAccent2.withValues(alpha: opacity)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = kAccent2.withValues(alpha: opacity * 0.15)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 3; i++) {
      final x = bottomCenter.dx + (i - 1) * (w + 4);
      final rect = Rect.fromLTWH(x - w / 2, bottomCenter.dy - heights[i], w, heights[i]);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: kAccent2.withValues(alpha: opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, bottomCenter.dy - heights[i] - 20));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = kBg,
    );

    // Faint diagonal hex grid.
    _drawHexGrid(canvas, size);

    // Finish line at x = 0.78 * size.width.
    final finishX = 0.78 * size.width;
    _drawFinishLine(canvas, finishX, size);

    // 3 runners.
    final runnerY = size.height * 0.50;
    for (int i = 0; i < 3; i++) {
      final color = _kRunnerColors[i];
      final startX = _kStartOffsets[i] * size.width;
      final endX = finishX;
      final progress = (t / 0.65).clamp(0.0, 1.0);
      final runnerX = startX + (endX - startX) * progress;
      final pos = Offset(runnerX, runnerY + (i - 1) * 14.0);

      // Motion blur ghost stamps.
      for (int g = 1; g <= 4; g++) {
        final ghostAlphas = [0.07, 0.14, 0.22, 0.35];
        _drawRunner(canvas, pos.translate(-12.0 * g, 0), color, ghostAlphas[g - 1]);
      }
      _drawRunner(canvas, pos, color, 1.0);
    }

    // Stopwatch top-left.
    final totalSecs = (t * 14).floor();
    final frames = ((t * 1488).floor() % 100);
    final stopwatch =
        '00:${totalSecs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
    final swTp = TextPainter(
      text: TextSpan(
        text: stopwatch,
        style: GoogleFonts.robotoMono(
          fontSize: 18,
          color: kAccent2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    swTp.paint(canvas, const Offset(12, 12));

    // Podium (t >= 0.78).
    if (t >= 0.78) {
      final podiumOpacity = ((t - 0.78) / 0.07).clamp(0.0, 1.0);
      _drawPodium(
          canvas, Offset(size.width / 2, size.height - 16), podiumOpacity);
    }

    // "COMING SOON" stamp (t >= 0.85).
    if (t >= 0.85) {
      final stampOpacity = ((t - 0.85) / 0.05).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: 'COMING SOON',
          style: GoogleFonts.bebasNeue(
            fontSize: 40,
            color: kAccent2.withValues(alpha: stampOpacity),
          ).copyWith(
            shadows: [
              Shadow(
                color: kAccent2.withValues(alpha: stampOpacity * 0.7),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(
          canvas,
          Offset(
              (size.width - tp.width) / 2, size.height / 2 - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_IntroPhysicalEventsPainter old) => old.t != t;
}
