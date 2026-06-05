import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../theme.dart';

TileLayer _cartoDbDarkNoLabels(BuildContext context) => TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
      userAgentPackageName: 'app.runwar.runwar_app',
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final _mapCtrl = MapController();

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
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _startLoop();
  }

  void _startLoop() {
    _ctrl.reset();
    _ctrl.forward().then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        _startLoop();
      });
    });
  }

  void _updatePoints() {
    final cam = _mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }
    setState(() {
      _route = _kRoute.map(toScreen).toList();
      _block1 = IntroZones.kS1Block1.map(toScreen).toList();
      _block2 = IntroZones.kS1Block2.map(toScreen).toList();
      _block3 = IntroZones.kS1Block3.map(toScreen).toList();
      _mapReady = true;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          _buildIntroMap(
            context: context,
            mapController: _mapCtrl,
            center: const LatLng(39.4650, -0.3768),
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (_mapReady)
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
        ],
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

  // Fill opacity ramps over 0.5 segments past each close index; holds until
  // t=0.94, then fades out over 0.94–1.0. Used for blocks 1 and 2.
  double _fillOpacity(double traveled, double closeIdx, double t) {
    final frac = ((traveled - closeIdx) / 0.5).clamp(0.0, 1.0);
    final fade =
        t > 0.94 ? (1.0 - (t - 0.94) / 0.06).clamp(0.0, 1.0) : 1.0;
    return frac * fade * 0.28;
  }

  // Time-based fill opacity for block 3. Because traveled maxes at exactly the
  // close point (t=0.82), there is no traveled headroom after close — ramp on t.
  double _block3FillOpacity(double t) {
    if (t < _block3CloseT) return 0.0;
    final ramp = ((t - _block3CloseT) / 0.04).clamp(0.0, 1.0);
    final fade = t > 0.94 ? (1.0 - (t - 0.94) / 0.06).clamp(0.0, 1.0) : 1.0;
    return ramp * fade * 0.28;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    // Runner completes all 3 blocks by t=0.82, fills hold until t=0.94, then fade.
    final segs = route.length - 1; // 11 segments
    final routeProgress = (t / 0.82).clamp(0.0, 1.0);
    final traveled = routeProgress * segs;

    // Block fills — appear as the runner closes each loop.
    final fill1Opacity = _fillOpacity(traveled, _block1CloseIdx, t);
    final fill2Opacity = _fillOpacity(traveled, _block2CloseIdx, t);
    final fill3Opacity = _block3FillOpacity(t);
    drawFill(canvas, block1, fill1Opacity);
    drawFill(canvas, block2, fill2Opacity);
    drawFill(canvas, block3, fill3Opacity);

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final _mapCtrl = MapController();

  // Attacker route — blue rival (kSea) follows real Ruzafa streets.
  //
  //   pt0–pt4 — straight approach up Carrer de Cuba heading NW (unchanged)
  //   pt4     — CORNER: TURN RIGHT onto cross-street heading NE
  //   pt5–pt6 — 2 city blocks NE along Carrer de Sueca / cross-street
  //   pt6     — TURN RIGHT heading SE (south-east, 1 block)
  //   pt7     — TURN RIGHT heading SW back toward Cuba diagonal
  //   pt8     — LASSO CLOSES: crosses own Cuba approach path
  //   pt9     — continues a few metres past close → fades out
  static const _kAttackerRoute = [
    LatLng(39.4556, -0.3732), //  0: off-screen south approach
    LatLng(39.4577, -0.3740), //  1: Carrer de Cuba south
    LatLng(39.4586, -0.3747), //  2: Cuba mid
    LatLng(39.4598, -0.3755), //  3: Cuba NW
    LatLng(39.4604, -0.3760), //  4: Cuba — CORNER: turn right (NE)
    LatLng(39.4611, -0.3754), //  5: 1 block NE (Sueca cross-street)
    LatLng(39.4618, -0.3748), //  6: 2 blocks NE — overlapping kS1Block2 east edge
    LatLng(39.4612, -0.3741), //  7: TURN RIGHT: 1 block SE
    LatLng(39.4605, -0.3748), //  8: TURN RIGHT: heading SW back toward Cuba
    LatLng(39.4602, -0.3757), //  9: LASSO CLOSES (crosses own Cuba approach path)
    LatLng(39.4601, -0.3764), // 10: continues past close → FADE
  ];

  // The polygon enclosed by the lasso (pts 4–9).
  static const _kAttackerLasso = [
    LatLng(39.4604, -0.3760), // 4: SW corner (Cuba turn)
    LatLng(39.4618, -0.3748), // 6: NE corner
    LatLng(39.4612, -0.3741), // 7: SE corner
    LatLng(39.4605, -0.3748), // 8: S
  ];

  // Disputed area — overlap of attacker lasso with kS1Block2 (A/E vertices).
  static const _kDisputedArea = [
    LatLng(39.4618, -0.3752), // near E vertex of kS1Block2
    LatLng(39.4621, -0.3755), // near A vertex
    LatLng(39.4615, -0.3758), // SE edge
    LatLng(39.4612, -0.3756), // S
    LatLng(39.4611, -0.3752), // SE of E
  ];

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _ownedBlock1 = [];
  List<Offset> _ownedBlock2 = [];
  List<Offset> _attackerRoute = [];
  List<Offset> _attackerLasso = [];
  List<Offset> _disputedArea = [];
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _updatePoints() {
    final cam = _mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }
    setState(() {
      // Inherited blocks from slide 1 — rendered as pre-filled territory.
      _inheritedPts = IntroZones.kS1All
          .map((block) => block.map(toScreen).toList())
          .toList();
      _ownedBlock1 = IntroZones.kS2OwnedBlock1.map(toScreen).toList();
      _ownedBlock2 = IntroZones.kS2OwnedBlock2.map(toScreen).toList();
      _attackerRoute = _kAttackerRoute.map(toScreen).toList();
      _attackerLasso = _kAttackerLasso.map(toScreen).toList();
      _disputedArea = _kDisputedArea.map(toScreen).toList();
      _mapReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildIntroMap(
          context: context,
          mapController: _mapCtrl,
          center: const LatLng(39.4650, -0.3768),
          zoom: 16.0,
          onReady: _updatePoints,
        ),
        if (_mapReady)
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

  // t=0.00–0.60: attacker runs; lasso closes at t=0.60
  // t=0.60: disputed area snaps on (amber fill + dashed border)
  // t=0.62–0.75: "DISPUTED" label visible
  // t=0.75–0.85: ownership changes → disputed area lerps orange→blue
  // t=0.85–0.92: "CLAIMED" label flashes in kSea
  // t=0.88–1.00: global fade + orange territory fades in disputed area
  static const double _lassoCloseT = 0.60;

  double _disputedOpacity(double t) {
    if (t < _lassoCloseT) return 0.0;
    if (t < _lassoCloseT + 0.03) {
      return ((t - _lassoCloseT) / 0.03) * 0.35;
    }
    if (t < 0.88) return 0.35;
    return ((1.0 - (t - 0.88) / 0.12) * 0.35).clamp(0.0, 0.35);
  }

  double _globalFade(double t) {
    if (t < 0.88) return 1.0;
    return (1.0 - (t - 0.88) / 0.12).clamp(0.0, 1.0);
  }

  Color _disputedFillColor(double t) {
    if (t < 0.75) return kAccent2;
    if (t > 0.85) return kSea;
    final lerpT = (t - 0.75) / 0.10;
    return Color.lerp(kAccent2, kSea, lerpT)!;
  }

  void _drawDashedPolygon(
      Canvas canvas, List<Offset> pts, Color color, double opacity) {
    if (pts.isEmpty || opacity <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    const dashLen = 8.0;
    const gapLen = 5.0;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final d = (b - a);
      final total = d.distance;
      double drawn = 0.0;
      bool drawing = true;
      while (drawn < total) {
        final segEnd =
            (drawn + (drawing ? dashLen : gapLen)).clamp(0.0, total);
        if (drawing) {
          canvas.drawLine(
            a + d * (drawn / total),
            a + d * (segEnd / total),
            paint,
          );
        }
        drawn = segEnd;
        drawing = !drawing;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (attackerRoute.isEmpty) return;

    final fade = _globalFade(t);

    // 0. Inherited blocks from slide 1 — pre-filled, no animation.
    drawInheritedBlocks(canvas, inheritedPts);

    // 1. Static orange owned territory fills for this slide — always visible.
    drawFillColor(canvas, ownedBlock1, kAccent, 0.22 * fade);
    drawFillColor(canvas, ownedBlock2, kAccent, 0.22 * fade);

    // 2. Attacker (blue) trail: runner traces route, then continues past close.
    //   t < _lassoCloseT        : runner moving along route
    //   t [close, close+0.08]   : runner continues past close, turns, fades
    //   t > close+0.08          : lasso outline only
    final routeProgress = (t / _lassoCloseT).clamp(0.0, 1.0);
    if (t < _lassoCloseT) {
      drawTraceColor(canvas, attackerRoute, routeProgress, kSea);
      if (attackerRoute.length >= 2) {
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
    } else {
      // Lasso outline stays visible.
      drawTraceColor(canvas, attackerRoute, 1.0, kSea.withValues(alpha: fade));
      // Runner continues past close, fades over 0.08 of t.
      if (t < _lassoCloseT + 0.08 && attackerRoute.length >= 2) {
        final contT = ((t - _lassoCloseT) / 0.08).clamp(0.0, 1.0);
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
                ..color =
                    Colors.white.withValues(alpha: 0.8 * runnerFade));
        }
      }
    }

    // 3. Disputed area fill — snaps on at t=0.60, lerps amber→blue at t=0.75–0.85.
    final dispOp = _disputedOpacity(t);
    final dispColor = _disputedFillColor(t);
    drawFillColor(canvas, disputedArea, dispColor, dispOp);

    // 3b. Dashed border on disputed area — amber border until ownership changes,
    //     then turns blue after t=0.75.
    if (t >= _lassoCloseT && disputedArea.isNotEmpty) {
      final borderColor = t < 0.75 ? kAccent2 : kSea;
      _drawDashedPolygon(canvas, disputedArea, borderColor, dispOp.clamp(0.0, 1.0));
    }

    // 4. Compute centroid of disputed area (used for labels).
    Offset disputedCentroid = Offset.zero;
    if (disputedArea.isNotEmpty) {
      double sumX = 0, sumY = 0;
      for (final pt in disputedArea) {
        sumX += pt.dx;
        sumY += pt.dy;
      }
      disputedCentroid =
          Offset(sumX / disputedArea.length, sumY / disputedArea.length);
    }

    // 5. "DISPUTED" label — t=0.62–0.75.
    if (t > 0.62 && t < 0.75 && disputedArea.isNotEmpty) {
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
              color: kAccent2.withValues(alpha: labelOpacity),
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

    // 6. "CLAIMED" label — t=0.85–0.92 in kSea.
    if (t > 0.85 && t < 0.92 && disputedArea.isNotEmpty) {
      final claimedOpacity = t < 0.885
          ? ((t - 0.85) / 0.035).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.885) / 0.035)).clamp(0.0, 1.0);

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final _mapCtrl = MapController();

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
  bool _mapReady = false;

  List<Offset> _toScreen(List<LatLng> coords) => coords
      .map((ll) => _mapCtrl.camera.latLngToScreenPoint(ll))
      .map((p) => Offset(p.x, p.y))
      .toList();

  void _onMapReady() {
    setState(() {
      // Inherited blocks from slides 1+2 — rendered as pre-filled territory.
      _inheritedPts = IntroZones.kS2All
          .map((block) => _toScreen(block))
          .toList();
      _ownedBlock1 = _toScreen(IntroZones.kS3OwnedBlock1);
      _ownedBlock2 = _toScreen(IntroZones.kS3OwnedBlock2);
      _attackerRoute = _toScreen(_kAttackerRoute);
      _partialDisputed = _toScreen(_kPartialDisputedArea);
      _mapReady = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildIntroMap(
          context: context,
          mapController: _mapCtrl,
          center: const LatLng(39.4665, -0.3768),
          zoom: 16.0,
          onReady: _onMapReady,
        ),
        if (_mapReady)
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
    with SingleTickerProviderStateMixin {
  // ── Fixed coordinates ──────────────────────────────────────────────────────
  static const _kDropCoord = LatLng(39.4553, -0.3510);

  // Runner A — north start near Av. de França / Gran Via junction.
  // Route: Gran Via → Av. de França (south) → Av. del Congrés Eucarístic →
  //        Pont de l'Exposició → drop point.
  static const _kRouteA = [
    LatLng(39.4640, -0.3560), // 0: start — Gran Via / Av. de França
    LatLng(39.4618, -0.3548), // 1: south on Av. de França
    LatLng(39.4595, -0.3535), // 2: continues south
    LatLng(39.4575, -0.3523), // 3: Av. del Congrés Eucarístic turn
    LatLng(39.4560, -0.3515), // 4: approaching Pont de l'Exposició
    LatLng(39.4553, -0.3510), // 5: DROP POINT
  ];

  // Runner B — northwest start near Ruzafa / Carrer de la Reina.
  // Route: east along Carrer de la Reina → Av. de les Corts Valencianes →
  //        Av. del Saler south → drop point.
  static const _kRouteB = [
    LatLng(39.4600, -0.3680), // 0: start — Ruzafa area
    LatLng(39.4598, -0.3645), // 1: east on Carrer de la Reina
    LatLng(39.4592, -0.3610), // 2: continues east
    LatLng(39.4580, -0.3575), // 3: Av. de les Corts Valencianes junction
    LatLng(39.4568, -0.3545), // 4: south on Av. del Saler
    LatLng(39.4553, -0.3510), // 5: DROP POINT
  ];

  // Runner C — east start near beach/port area.
  // Route: west along Av. del Port → Av. de França turn north → drop point.
  static const _kRouteC = [
    LatLng(39.4500, -0.3380), // 0: start — near port/beach
    LatLng(39.4508, -0.3410), // 1: west on Av. del Port
    LatLng(39.4516, -0.3440), // 2: continues west
    LatLng(39.4525, -0.3465), // 3: Av. de França turn north
    LatLng(39.4537, -0.3488), // 4: north on Av. de França
    LatLng(39.4553, -0.3510), // 5: DROP POINT
  ];

  // ── State ──────────────────────────────────────────────────────────────────
  late final AnimationController _ctrl;
  final _mapCtrl = MapController();

  List<Offset> _routeA = [];
  List<Offset> _routeB = [];
  List<Offset> _routeC = [];
  Offset _dropPt = Offset.zero;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _updatePoints() {
    final cam = _mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }
    setState(() {
      _routeA = _kRouteA.map(toScreen).toList();
      _routeB = _kRouteB.map(toScreen).toList();
      _routeC = _kRouteC.map(toScreen).toList();
      _dropPt = toScreen(_kDropCoord);
      _mapReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildIntroMap(
          context: context,
          mapController: _mapCtrl,
          center: const LatLng(39.4540, -0.3520),
          zoom: 14.0,
          onReady: _updatePoints,
        ),
        if (_mapReady)
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
