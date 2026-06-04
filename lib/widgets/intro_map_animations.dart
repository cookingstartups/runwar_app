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

  // Corner polygons for fill rendering — exactly match the area each lasso loop encloses.
  static const _kBlock1 = [
    LatLng(39.462077, -0.375522), // A
    LatLng(39.461576, -0.376751), // B
    LatLng(39.462155, -0.377171), // C
    LatLng(39.462671, -0.375937), // D
  ];

  static const _kBlock2 = [
    LatLng(39.462077, -0.375522), // A
    LatLng(39.461568, -0.375167), // E
    LatLng(39.460440, -0.375966), // F
    LatLng(39.461050, -0.376394), // G
    LatLng(39.461576, -0.376751), // B
  ];

  static const _kBlock3 = [
    LatLng(39.461576, -0.376751), // B
    LatLng(39.460846, -0.378471), // H
    LatLng(39.460335, -0.378112), // I
    LatLng(39.461050, -0.376394), // G
  ];

  List<Offset> _route = [];
  List<Offset> _block1 = [];
  List<Offset> _block2 = [];
  List<Offset> _block3 = [];
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 12))
          ..repeat();
  }

  void _updatePoints() {
    final cam = _mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }
    setState(() {
      _route = _kRoute.map(toScreen).toList();
      _block1 = _kBlock1.map(toScreen).toList();
      _block2 = _kBlock2.map(toScreen).toList();
      _block3 = _kBlock3.map(toScreen).toList();
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
            center: const LatLng(39.4500, -0.3760),
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
  static const int _block1CloseIdx = 4;
  static const int _block2CloseIdx = 8;
  static const int _block3CloseIdx = 11; // also == route.length - 1

  // Fill opacity driven by how far past each close index the runner has traveled.
  // Ramp window of 0.5 segments; fades out over t=0.93–1.0.
  double _fillOpacity(double traveled, double closeIdx, double t) {
    final frac = ((traveled - closeIdx) / 0.5).clamp(0.0, 1.0);
    final fade =
        t > 0.93 ? (1.0 - (t - 0.93) / 0.07).clamp(0.0, 1.0) : 1.0;
    return frac * fade * 0.28;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    // Runner completes all 3 blocks by t=0.90, fills hold to t=0.93, then fade.
    final segs = route.length - 1; // 11 segments
    final routeProgress = (t / 0.90).clamp(0.0, 1.0);
    final traveled = routeProgress * segs;

    // Block fills — appear as the runner closes each loop.
    final fill1Opacity = _fillOpacity(traveled, _block1CloseIdx.toDouble(), t);
    final fill2Opacity = _fillOpacity(traveled, _block2CloseIdx.toDouble(), t);
    final fill3Opacity = _fillOpacity(traveled, _block3CloseIdx.toDouble(), t);
    drawFill(canvas, block1, fill1Opacity);
    drawFill(canvas, block2, fill2Opacity);
    drawFill(canvas, block3, fill3Opacity);

    // Single trace covering all 3 blocks.
    drawTrace(canvas, route, routeProgress);

    // Runner dot — visible while tracing (before fade-out window).
    if (t < 0.93) {
      drawRunner(canvas, route, routeProgress);
    }

    // Ping burst when block 1 closes.
    final ping1T = traveled - _block1CloseIdx;
    if (ping1T > 0 && ping1T < 0.10 * segs) {
      drawPings(canvas, block1, (ping1T / (0.10 * segs)).clamp(0.0, 1.0));
    }

    // Ping burst when block 2 closes.
    final ping2T = traveled - _block2CloseIdx;
    if (ping2T > 0 && ping2T < 0.8) {
      drawPings(canvas, block2, (ping2T / 0.8).clamp(0.0, 1.0));
    }

    // Ping burst when block 3 closes.
    final ping3T = traveled - _block3CloseIdx;
    if (ping3T > 0 && ping3T < 0.8) {
      drawPings(canvas, block3, (ping3T / 0.8).clamp(0.0, 1.0));
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

  // Static owned territory — two orange blocks already captured (slide 1 legacy).
  static const _kOwnedBlock1 = [
    LatLng(39.4503, -0.3774),
    LatLng(39.4497, -0.3780),
    LatLng(39.4503, -0.3785),
    LatLng(39.4509, -0.3779),
  ];
  static const _kOwnedBlock2 = [
    LatLng(39.4509, -0.3779),
    LatLng(39.4503, -0.3785),
    LatLng(39.4497, -0.3791),
    LatLng(39.4503, -0.3796),
    LatLng(39.4511, -0.3788),
  ];

  // Attacker route — blue rival (kSea) enters from off-screen left, runs a
  // lasso that overlaps part of the owned territory, closes at t=0.70.
  //
  //   pt0 — off-screen far left (off map, w < 0)
  //   pt1 — enters map near western edge on Carrer de Sueca approach
  //   pt2 — LASSO ANCHOR (corner to which lasso closes)
  //   pt3 — continues south overlapping owned block edge
  //   pt4 — loops east past owned territory
  //   pt5 — turns north-west cutting through overlap zone
  //   pt6 — pt7 approaches anchor
  //   pt7 — LASSO CLOSE = pt2
  static const _kAttackerRoute = [
    LatLng(39.4493, -0.3820), // 0: off-screen left entry
    LatLng(39.4493, -0.3795), // 1: enters map western edge
    LatLng(39.4497, -0.3783), // 2: LASSO ANCHOR
    LatLng(39.4491, -0.3781), // 3: south along owned edge
    LatLng(39.4488, -0.3775), // 4: loops east past owned territory
    LatLng(39.4490, -0.3769), // 5: turns north-east
    LatLng(39.4496, -0.3770), // 6: heading back north-west
    LatLng(39.4497, -0.3783), // 7: LASSO CLOSE = pt2
  ];

  // The polygon enclosed by the attacker's lasso (pts 2–7).
  static const _kAttackerLasso = [
    LatLng(39.4497, -0.3783), // 2
    LatLng(39.4491, -0.3781), // 3
    LatLng(39.4488, -0.3775), // 4
    LatLng(39.4490, -0.3769), // 5
    LatLng(39.4496, -0.3770), // 6
  ];

  // Disputed area — approximate overlap between attacker lasso and owned blocks.
  static const _kDisputedArea = [
    LatLng(39.4497, -0.3783),
    LatLng(39.4494, -0.3782),
    LatLng(39.4491, -0.3781),
    LatLng(39.4492, -0.3778),
    LatLng(39.4497, -0.3779),
    LatLng(39.4499, -0.3780),
  ];

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
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
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
      _ownedBlock1 = _kOwnedBlock1.map(toScreen).toList();
      _ownedBlock2 = _kOwnedBlock2.map(toScreen).toList();
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
          center: const LatLng(39.4491, -0.3760),
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
  final List<Offset> ownedBlock1;
  final List<Offset> ownedBlock2;
  final List<Offset> attackerRoute;
  final List<Offset> attackerLasso;
  final List<Offset> disputedArea;

  _IntroCaptureMapPainter({
    required this.t,
    required this.accent,
    required this.ownedBlock1,
    required this.ownedBlock2,
    required this.attackerRoute,
    required this.attackerLasso,
    required this.disputedArea,
  });

  // t=0.00–0.70: attacker runs; lasso closes at t=0.70
  // t=0.70: disputed area snaps on
  // t=0.72–0.85: "DISPUTED" label visible
  // t=0.90–1.00: all fades
  static const double _lassoCloseT = 0.70;

  double _disputedOpacity(double t) {
    if (t < _lassoCloseT) return 0.0;
    if (t < _lassoCloseT + 0.03) {
      return ((t - _lassoCloseT) / 0.03) * 0.35;
    }
    if (t < 0.90) return 0.35;
    return ((1.0 - (t - 0.90) / 0.10) * 0.35).clamp(0.0, 0.35);
  }

  double _globalFade(double t) {
    if (t < 0.90) return 1.0;
    return (1.0 - (t - 0.90) / 0.10).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (attackerRoute.isEmpty) return;

    final fade = _globalFade(t);

    // 1. Static orange owned territory fills — always visible.
    drawFillColor(canvas, ownedBlock1, kAccent, 0.22 * fade);
    drawFillColor(canvas, ownedBlock2, kAccent, 0.22 * fade);

    // 2. Attacker (blue) trail: runner traces route up to lasso close.
    final routeProgress = (t / _lassoCloseT).clamp(0.0, 1.0);
    if (t < _lassoCloseT) {
      drawTraceColor(canvas, attackerRoute, routeProgress, kSea);
      // Runner dot
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
      // After close — show full attacker lasso outline.
      drawTraceColor(canvas, attackerRoute, 1.0, kSea.withValues(alpha: fade));
    }

    // 3. Disputed area fill — snaps on at t=0.70 in amber/yellow.
    drawFillColor(canvas, disputedArea, kAccent2, _disputedOpacity(t));

    // 4. "DISPUTED" label at centroid of disputed area.
    if (t > 0.72 && t < 0.85 && disputedArea.isNotEmpty) {
      double sumX = 0, sumY = 0;
      for (final pt in disputedArea) {
        sumX += pt.dx;
        sumY += pt.dy;
      }
      final centroid = Offset(sumX / disputedArea.length, sumY / disputedArea.length);

      final labelOpacity = t < 0.785
          ? ((t - 0.72) / 0.065).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.785) / 0.065)).clamp(0.0, 1.0);

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
            Offset(centroid.dx - tp.width / 2, centroid.dy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroCaptureMapPainter old) =>
      old.t != t ||
      old.attackerRoute != attackerRoute ||
      old.disputedArea != disputedArea ||
      old.ownedBlock1 != ownedBlock1 ||
      old.ownedBlock2 != ownedBlock2;
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

  // Static owned territory (~100m south of slide 2 blocks, lat ~39.4482).
  static const _kOwnedBlock1 = [
    LatLng(39.4490, -0.3774),
    LatLng(39.4484, -0.3780),
    LatLng(39.4490, -0.3785),
    LatLng(39.4496, -0.3779),
  ];
  static const _kOwnedBlock2 = [
    LatLng(39.4496, -0.3779),
    LatLng(39.4490, -0.3785),
    LatLng(39.4484, -0.3791),
    LatLng(39.4490, -0.3796),
    LatLng(39.4498, -0.3788),
  ];

  // Blue attacker partial lasso — runs from t=0.0 to t=0.45 (interrupted).
  static const _kAttackerRoute = [
    LatLng(39.4480, -0.3810), // 0: off-screen left
    LatLng(39.4482, -0.3793), // 1: enters map area
    LatLng(39.4485, -0.3782), // 2: approaches owned territory
    LatLng(39.4480, -0.3778), // 3: overlapping south edge
    LatLng(39.4478, -0.3772), // 4: loops east — partial close never completes
  ];

  // Partial disputed area at the overlap zone (appears at t=0.45, rejected at t=0.50).
  static const _kPartialDisputedArea = [
    LatLng(39.4485, -0.3782),
    LatLng(39.4482, -0.3781),
    LatLng(39.4480, -0.3778),
    LatLng(39.4483, -0.3776),
    LatLng(39.4486, -0.3779),
  ];

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
      _ownedBlock1 = _toScreen(_kOwnedBlock1);
      _ownedBlock2 = _toScreen(_kOwnedBlock2);
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
          center: const LatLng(39.4482, -0.3760),
          zoom: 14.0,
          onReady: _onMapReady,
        ),
        if (_mapReady)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _IntroRivalsMapPainter(
                t: _ctrl.value,
                accent: widget.accent,
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
  final List<Offset> ownedBlock1;
  final List<Offset> ownedBlock2;
  final List<Offset> attackerRoute;
  final List<Offset> partialDisputed;

  _IntroRivalsMapPainter({
    required this.t,
    required this.accent,
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
      old.partialDisputed != partialDisputed;
}

// ---------------------------------------------------------------------------
// 4. IntroFlagDropMap — GPS beacon urgency on real map (slide 4 CTF drop)
// ---------------------------------------------------------------------------
class IntroFlagDropMap extends StatefulWidget {
  final Color accent;
  const IntroFlagDropMap({required this.accent, super.key});
  @override
  State<IntroFlagDropMap> createState() => _IntroFlagDropMapState();
}

class _IntroFlagDropMapState extends State<IntroFlagDropMap>
    with SingleTickerProviderStateMixin {
  static const _kDropCoord = LatLng(39.4553, -0.3510);

  late final AnimationController _ctrl;
  final _mapCtrl = MapController();
  Offset _dropPt = Offset.zero;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 2800))
        ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _updatePoint() {
    final p = _mapCtrl.camera.latLngToScreenPoint(_kDropCoord);
    setState(() {
      _dropPt = Offset(p.x.toDouble(), p.y.toDouble());
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
          center: const LatLng(39.4553, -0.3510),
          zoom: 15.0,
          onReady: _updatePoint,
          maxZoom: 19,
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
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    );
  }
}

class _IntroFlagDropMapPainter extends CustomPainter {
  final double t;
  final Color accent;
  final Offset dropPt;

  const _IntroFlagDropMapPainter(
      {required this.t, required this.accent, required this.dropPt});

  @override
  void paint(Canvas canvas, Size size) {
    if (dropPt == Offset.zero) return;

    final w = size.width;
    final h = size.height;
    final cx = dropPt.dx;
    final cy = dropPt.dy;

    final dropPhase = (t / 0.25).clamp(0.0, 1.0);
    final markerY = Offset.lerp(
      Offset(cx, -20),
      Offset(cx, cy),
      Curves.bounceOut.transform(dropPhase),
    )!
        .dy;

    if (t > 0.25 && t < 0.35) {
      final flashOpacity = (1 - (t - 0.25) / 0.1) * 0.3;
      canvas.drawCircle(
          Offset(cx, cy),
          50,
          Paint()
            ..color = accent.withValues(alpha: flashOpacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20));
    }

    for (int i = 0; i < 3; i++) {
      final delay = i * 0.22;
      final ringT =
          (t > 0.3 ? (t - 0.3 - delay) / 0.55 : 0.0).clamp(0.0, 1.0);
      if (ringT > 0) {
        canvas.drawCircle(
            Offset(cx, cy),
            ringT * (w * 0.42),
            Paint()
              ..color = accent.withValues(alpha: (1.0 - ringT) * 0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 + (1 - ringT) * 1.5);
      }
    }

    if (t > 0.15) {
      final markerOpacity = dropPhase.clamp(0.3, 1.0);
      canvas.drawLine(
          Offset(cx, markerY),
          Offset(cx, markerY + 22),
          Paint()
            ..color = kFg.withValues(alpha: markerOpacity * 0.9)
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round);
      final pulseSin = (math.sin(t * math.pi * 4) + 1) / 2;
      canvas.drawCircle(
          Offset(cx, markerY),
          14 + pulseSin * 4,
          Paint()
            ..color = accent.withValues(alpha: 0.2 * markerOpacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(Offset(cx, markerY), 10,
          Paint()..color = accent.withValues(alpha: markerOpacity));
      canvas.drawCircle(
          Offset(cx, markerY),
          4,
          Paint()..color = Colors.white.withValues(alpha: markerOpacity * 0.9));
    }

    if (dropPhase > 0.8) {
      final shadowOp = ((dropPhase - 0.8) / 0.2).clamp(0.0, 1.0) * 0.25;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 24), width: 30, height: 8),
        Paint()
          ..color = accent.withValues(alpha: shadowOp)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    if (t > 0.4) {
      final textOp = ((t - 0.4) / 0.15).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: '▸ NEW OBJECT DROP',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            letterSpacing: 2,
            color: accent.withValues(alpha: textOp * 0.85),
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy + h * 0.22));
    }

    if (t > 0.5) {
      const coords = '39.4553° N, 0.3510° W';
      final tickerOp = ((math.sin(t * math.pi * 8) + 1) / 2) * 0.5 + 0.3;
      final fadeIn = ((t - 0.5) / 0.15).clamp(0.0, 1.0);
      final tp2 = TextPainter(
        text: TextSpan(
          text: coords,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 8,
            letterSpacing: 1,
            color: kFgMuted.withValues(alpha: tickerOp * fadeIn),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp2.paint(canvas, Offset(cx - tp2.width / 2, cy + h * 0.30));
    }
  }

  @override
  bool shouldRepaint(_IntroFlagDropMapPainter old) =>
      old.t != t || old.dropPt != dropPt || old.accent != accent;
}

