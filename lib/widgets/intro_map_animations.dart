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

  // Block 1 route: Cuba–Sueca–Dénia triangle near Ruzafa, Valencia.
  // Loop closes at LatLng(39.462671, -0.375937) — Sueca/Dénia SE junction.
  static const _kRoute = [
    LatLng(39.462155, -0.377171),
    LatLng(39.461576, -0.376751),
    LatLng(39.461123, -0.376444),
    LatLng(39.461568, -0.375167),
    LatLng(39.462077, -0.375522),
    LatLng(39.462671, -0.375937),
    LatLng(39.462155, -0.377171),
  ];

  static const _kBlock1 = [
    LatLng(39.462155, -0.377171),
    LatLng(39.461576, -0.376751),
    LatLng(39.461123, -0.376444),
    LatLng(39.462671, -0.375937),
  ];

  // Block 2 route: adjacent block to the east, sharing the Sueca/Dénia SE
  // corner with block 1. Bounded by Carrer de Sueca (SW edge), Gran Via de
  // les Germanies (north edge), and Carrer de Dénia (SE diagonal back).
  // Starts and ends at LatLng(39.462671, -0.375937) for seamless runner flow.
  static const _kRoute2 = [
    LatLng(39.462671, -0.375937), // SW — shared junction with block 1
    LatLng(39.463469, -0.376515), // NW mid — Carrer de Sueca heading NE
    LatLng(39.463595, -0.376553), // NW corner — Sueca meets Gran Via
    LatLng(39.464001, -0.376109), // NE corner — Gran Via primary junction
    LatLng(39.463243, -0.374594), // SE corner — Carrer de Dénia / Cadis node
    LatLng(39.462671, -0.375937), // back to start (closed)
  ];

  static const _kBlock2 = [
    LatLng(39.462671, -0.375937), // SW
    LatLng(39.463595, -0.376553), // NW
    LatLng(39.464001, -0.376109), // NE
    LatLng(39.463243, -0.374594), // SE
  ];

  List<Offset> _route = [];
  List<Offset> _block1 = [];
  List<Offset> _route2 = [];
  List<Offset> _block2 = [];
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
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
      _route2 = _kRoute2.map(toScreen).toList();
      _block2 = _kBlock2.map(toScreen).toList();
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
            center: const LatLng(39.4638, -0.3771),
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
                  route2: _route2,
                  block2: _block2,
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
  final List<Offset> route2;
  final List<Offset> block2;

  _IntroPulseMapPainter({
    required this.t,
    required this.accent,
    required this.route,
    required this.block1,
    required this.route2,
    required this.block2,
  });

  // Phase 1: runner completes loop 1 at t=0.55 — fill snaps on immediately.
  static const double _fillPhase1 = 0.55;
  // Phase 2: runner completes loop 2 at t=0.88 — fill 2 snaps on immediately.
  static const double _fillPhase2 = 0.88;

  // Block 1 fill opacity:
  //   t < 0.55              → 0
  //   0.55–0.58             → snap 0→0.28 (quick flash, ≤0.03t ramp)
  //   0.58–0.94             → hold 0.28
  //   0.94–1.00             → fade to 0
  double _block1Opacity(double t) {
    if (t < _fillPhase1) return 0.0;
    if (t < _fillPhase1 + 0.03) return ((t - _fillPhase1) / 0.03) * 0.28;
    if (t < 0.94) return 0.28;
    return ((1.0 - (t - 0.94) / 0.06) * 0.28).clamp(0.0, 0.28);
  }

  // Block 2 fill opacity:
  //   t < 0.88              → 0
  //   0.88–0.91             → snap 0→0.28 (quick flash, ≤0.03t ramp)
  //   0.91–0.94             → hold 0.28
  //   0.94–1.00             → fade to 0
  double _block2Opacity(double t) {
    if (t < _fillPhase2) return 0.0;
    if (t < _fillPhase2 + 0.03) return ((t - _fillPhase2) / 0.03) * 0.28;
    if (t < 0.94) return 0.28;
    return ((1.0 - (t - 0.94) / 0.06) * 0.28).clamp(0.0, 0.28);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    // --- Phase 1: runner traces loop 1 (t = 0.00 → 0.55) ---
    // Scale route progress so the runner completes the full loop by t=0.55.
    final routeProgress = (t / 0.55).clamp(0.0, 1.0);

    drawFill(canvas, block1, _block1Opacity(t));
    drawTrace(canvas, route, routeProgress);

    // Phase 1 runner: visible only while loop 1 is in progress.
    if (t < _fillPhase1) {
      drawRunner(canvas, route, routeProgress);
    }

    // Ping burst when block 1 captures.
    if (t > _fillPhase1 && t < _fillPhase1 + 0.10) {
      drawPings(canvas, block1, ((t - _fillPhase1) / 0.10).clamp(0.0, 1.0));
    }

    // --- Phase 2: runner traces loop 2 (t = 0.55 → 0.88) ---
    // Seamless continuation — route2 starts at the same coord loop1 ends.
    if (route2.isNotEmpty) {
      final route2Progress =
          t >= _fillPhase1 ? ((t - _fillPhase1) / 0.33).clamp(0.0, 1.0) : 0.0;

      if (t >= _fillPhase1) {
        drawTrace(canvas, route2, route2Progress);
      }

      // Phase 2 runner: visible from loop 1 close until loop 2 close.
      if (t >= _fillPhase1 && t < _fillPhase2) {
        drawRunner(canvas, route2, route2Progress);
      }

      drawFill(canvas, block2, _block2Opacity(t));

      // Ping burst when block 2 captures.
      if (t > _fillPhase2 && t < _fillPhase2 + 0.08) {
        drawPings(canvas, block2, ((t - _fillPhase2) / 0.08).clamp(0.0, 1.0));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroPulseMapPainter old) =>
      old.t != t ||
      old.route != route ||
      old.block1 != block1 ||
      old.route2 != route2 ||
      old.block2 != block2;
}

// ---------------------------------------------------------------------------
// 2. IntroCaptureMap — rival attacker lasso capture (slide 2)
//    Rival (kSea blue) enters from off-screen left, runs east along real
//    Ruzafa streets, draws a lasso closing back onto an earlier waypoint,
//    then the enclosed area snaps to captured fill.
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

  // Full route — rival enters from off-screen left (pt0, lon ~-0.380) and runs
  // east along real Ruzafa streets. The route closes at pt6 == pt2 to form the
  // lasso polygon.
  //
  // Street mapping (OSM-verified, Overpass query around:300,39.4635,-0.3748):
  //   pt0  — off-screen west entry (~140 m west of left edge at zoom 16)
  //   pt1  — Carrer de Cadis / Gran Via approach from west
  //   pt2  — Carrer de Cadis / Carrer de Castelló junction  ← LASSO ANCHOR
  //   pt3  — Carrer de Cadis south junction (Cadis/Xella node)
  //   pt4  — Carrer de Sevilla / Cadis east node
  //   pt5  — Carrer de Sevilla heading north-west back
  //   pt6  — = pt2: lasso closes here (Cadis/Castelló junction again)
  static const _kRoute = [
    LatLng(39.464000, -0.380000), // 0: off-screen left
    LatLng(39.464200, -0.376200), // 1: Cadis/Gran Via approach
    LatLng(39.464220, -0.375291), // 2: Cadis/Castelló junction  ← LASSO ANCHOR
    LatLng(39.463243, -0.374594), // 3: Cadis south junction
    LatLng(39.463829, -0.374090), // 4: Sevilla/Cadis east
    LatLng(39.464402, -0.374410), // 5: Sevilla heading NW back
    LatLng(39.464220, -0.375291), // 6: LASSO CLOSE = pt2
  ];

  // Sub-polygon for the captured fill — the loop from index 2 through 6.
  static const _kLassoPolygon = [
    LatLng(39.464220, -0.375291), // 2
    LatLng(39.463243, -0.374594), // 3
    LatLng(39.463829, -0.374090), // 4
    LatLng(39.464402, -0.374410), // 5
  ];

  List<Offset> _route = [];
  List<Offset> _lassoPolygon = [];
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
      _route = _kRoute.map(toScreen).toList();
      _lassoPolygon = _kLassoPolygon.map(toScreen).toList();
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
          center: const LatLng(39.4635, -0.3748),
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
                route: _route,
                lassoPolygon: _lassoPolygon,
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
  final List<Offset> route;
  final List<Offset> lassoPolygon;

  _IntroCaptureMapPainter({
    required this.t,
    required this.accent,
    required this.route,
    required this.lassoPolygon,
  });

  // t=0.00–0.70: runner traces full route (lasso closes at t=0.70)
  // t=0.70: fill snaps on (0.03t ramp)
  // t=0.70–0.88: fill holds at 0.28, runner disappears
  // t=0.88–1.00: fill fades to 0, reset
  static const double _lassoCloseT = 0.70;

  double _fillOpacity(double t) {
    if (t < _lassoCloseT) return 0.0;
    if (t < _lassoCloseT + 0.03) {
      return ((t - _lassoCloseT) / 0.03) * 0.28;
    }
    if (t < 0.88) return 0.28;
    return ((1.0 - (t - 0.88) / 0.12) * 0.28).clamp(0.0, 0.28);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    // Route progress: runner completes the full route by t=0.70.
    final routeProgress = (t / _lassoCloseT).clamp(0.0, 1.0);

    // Captured area fill — snaps on when lasso closes.
    drawFill(canvas, lassoPolygon, _fillOpacity(t));

    // Trace: draw from start up to current progress.
    drawTrace(canvas, route, routeProgress);

    // Runner dot: visible only while tracing (before lasso close).
    if (t < _lassoCloseT) {
      drawRunner(canvas, route, routeProgress);
    }

    // "OWNED" label at polygon centroid — appears briefly after capture.
    if (t > 0.72 && t < 0.82 && lassoPolygon.isNotEmpty) {
      double sumX = 0, sumY = 0;
      for (final pt in lassoPolygon) {
        sumX += pt.dx;
        sumY += pt.dy;
      }
      final centroid =
          Offset(sumX / lassoPolygon.length, sumY / lassoPolygon.length);

      final labelOpacity = t < 0.77
          ? ((t - 0.72) / 0.05).clamp(0.0, 1.0)
          : ((1.0 - (t - 0.77) / 0.05) * 1.0).clamp(0.0, 1.0);

      if (labelOpacity > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'OWNED',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 2,
              color: accent.withValues(alpha: labelOpacity),
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
            canvas,
            Offset(
                centroid.dx - tp.width / 2, centroid.dy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroCaptureMapPainter old) =>
      old.t != t || old.route != route || old.lassoPolygon != lassoPolygon;
}

// ---------------------------------------------------------------------------
// 3. IntroRivalsMap — 3 runners on city-wide real map (slide 3)
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
  List<Offset> _pts1 = [], _pts2 = [], _pts3 = [];
  bool _mapReady = false;

  static const _kRunner1Coords = [
    LatLng(39.4802, -0.3773),
    LatLng(39.4790, -0.3782),
    LatLng(39.4787, -0.3763),
    LatLng(39.4795, -0.3761),
    LatLng(39.4802, -0.3773),
  ];
  static const _kRunner2Coords = [
    LatLng(39.4820, -0.3710),
    LatLng(39.4820, -0.3660),
    LatLng(39.4780, -0.3660),
    LatLng(39.4780, -0.3710),
    LatLng(39.4820, -0.3710),
  ];
  static const _kRunner3Coords = [
    LatLng(39.4750, -0.3820),
    LatLng(39.4750, -0.3790),
    LatLng(39.4720, -0.3790),
    LatLng(39.4720, -0.3820),
    LatLng(39.4750, -0.3820),
  ];

  List<Offset> _toScreen(List<LatLng> coords) => coords
      .map((ll) => _mapCtrl.camera.latLngToScreenPoint(ll))
      .map((p) => Offset(p.x, p.y))
      .toList();

  void _onMapReady() {
    setState(() {
      _pts1 = _toScreen(_kRunner1Coords);
      _pts2 = _toScreen(_kRunner2Coords);
      _pts3 = _toScreen(_kRunner3Coords);
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
          center: const LatLng(39.4768, -0.3762),
          zoom: 14,
          onReady: _onMapReady,
        ),
        if (_mapReady)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _IntroRivalsMapPainter(
                t: _ctrl.value,
                accent: widget.accent,
                pts1: _pts1,
                pts2: _pts2,
                pts3: _pts3,
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
  final List<Offset> pts1, pts2, pts3;

  _IntroRivalsMapPainter({
    required this.t,
    required this.accent,
    required this.pts1,
    required this.pts2,
    required this.pts3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pts1.isEmpty || pts2.isEmpty || pts3.isEmpty) return;

    final w = size.width;
    final runner1Color = accent;
    const runner2Color = kSea;
    const runner3Color = Color(0xFFFF3B7A);

    final r1 = _smoothPath(pts1, (t + 0.0) % 1.0);
    final r2 = _smoothPath(pts2, (t + 0.33) % 1.0);
    final r3 = _smoothPath(pts3, (t + 0.66) % 1.0);

    drawRunnerAt(canvas, r1, runner1Color);
    drawRunnerAt(canvas, r2, runner2Color);
    drawRunnerAt(canvas, r3, runner3Color);

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
    liveTp.paint(canvas, Offset(w - liveTp.width - 12, 10));
  }

  @override
  bool shouldRepaint(_IntroRivalsMapPainter old) =>
      old.t != t || old.pts1 != pts1 || old.pts2 != pts2 || old.pts3 != pts3;
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
  static const _kDropCoord = LatLng(39.4795, -0.3757);

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
          center: _kDropCoord,
          zoom: 16,
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
      const coords = '39.4795° N, 0.3757° W';
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

// ---------------------------------------------------------------------------
// Shared helper — interpolate position along a closed/open polyline
// ---------------------------------------------------------------------------
Offset _smoothPath(List<Offset> pts, double t) {
  if (pts.length < 2) return pts.first;
  final segs = pts.length - 1;
  final total = t * segs;
  final i = total.floor().clamp(0, segs - 1);
  return Offset.lerp(pts[i], pts[(i + 1).clamp(0, segs)], total - i)!;
}
