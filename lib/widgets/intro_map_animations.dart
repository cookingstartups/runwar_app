import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../theme.dart';

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

  static const _kRoute = [
    LatLng(39.4787577, -0.3762760),
    LatLng(39.4788475, -0.3765466),
    LatLng(39.4789977, -0.3771593),
    LatLng(39.4789949, -0.3774266),
    LatLng(39.4790307, -0.3781721),
    LatLng(39.4795237, -0.3779472),
    LatLng(39.4802212, -0.3773612),
    LatLng(39.4799543, -0.3771725),
    LatLng(39.4794183, -0.3765902),
    LatLng(39.4795250, -0.3761129),
    LatLng(39.4789167, -0.3760236),
    LatLng(39.4787577, -0.3762760),
  ];

  static const _kBlock1 = [
    LatLng(39.4787577, -0.3762760),
    LatLng(39.4790307, -0.3781721),
    LatLng(39.4802212, -0.3773612),
    LatLng(39.4795250, -0.3761129),
    LatLng(39.4789167, -0.3760236),
  ];

  List<Offset> _route = [];
  List<Offset> _block1 = [];
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..repeat();
  }

  void _updatePoints() {
    final cam = _mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }
    setState(() {
      _route  = _kRoute.map(toScreen).toList();
      _block1 = _kBlock1.map(toScreen).toList();
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
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: const LatLng(39.4790, -0.3758),
              initialZoom: 16,
              onMapReady: _updatePoints,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
                userAgentPackageName: 'app.runwar.runwar_app',
              ),
            ],
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
                ),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      );
}

class _IntroPulseMapPainter extends CustomPainter {
  final double t;
  final Color accent;
  final List<Offset> route;
  final List<Offset> block1;

  _IntroPulseMapPainter({
    required this.t,
    required this.accent,
    required this.route,
    required this.block1,
  });

  static const double _fillPhase1 = 0.82;

  double _blockOpacity(double t, double fillPhase) {
    if (t < fillPhase) return 0;
    if (t < fillPhase + 0.04) return ((t - fillPhase) / 0.04) * 0.22;
    if (t < 0.95) return 0.22;
    return (1.0 - (t - 0.95) / 0.05).clamp(0, 1) * 0.22;
  }

  void _drawFill(Canvas canvas, List<Offset> pts, double opacity) {
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

  void _drawTrace(Canvas canvas, List<Offset> pts, double routeT) {
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

  void _drawRunner(Canvas canvas, List<Offset> pts, double routeT) {
    if (pts.isEmpty) return;
    final segs = pts.length - 1;
    final totalLen = routeT.clamp(0.0, 1.0) * segs;
    final segIdx = totalLen.floor().clamp(0, segs - 1);
    final segFrac = (totalLen - segIdx).clamp(0.0, 1.0);
    final pos = Offset.lerp(pts[segIdx], pts[(segIdx + 1).clamp(0, segs)], segFrac)!;
    canvas.drawCircle(
        pos,
        12,
        Paint()
          ..color = accent.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawCircle(pos, 4.5, Paint()..color = accent);
    canvas.drawCircle(pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.8));
  }

  void _drawPings(Canvas canvas, List<Offset> pts, double pingT) {
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

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    _drawFill(canvas, block1, _blockOpacity(t, _fillPhase1));
    _drawTrace(canvas, route, t);

    if (t < 0.95) {
      _drawRunner(canvas, route, t);
    }

    if (t > _fillPhase1 && t < _fillPhase1 + 0.12) {
      _drawPings(canvas, block1, ((t - _fillPhase1) / 0.12).clamp(0.0, 1.0));
    }
  }

  @override
  bool shouldRepaint(_IntroPulseMapPainter old) =>
      old.t != t ||
      old.route != route ||
      old.block1 != block1;
}

// ---------------------------------------------------------------------------
// 2. IntroCaptureMap — El Carmen block capture on real map (slide 2)
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
  List<Offset> _pts = [];
  bool _mapReady = false;

  static const _kRouteCoords = [
    LatLng(39.4787577, -0.3762760),
    LatLng(39.4790307, -0.3781721),
    LatLng(39.4802212, -0.3773612),
    LatLng(39.4795250, -0.3761129),
    LatLng(39.4787577, -0.3762760),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
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
    setState(() {
      _pts = _kRouteCoords.map((ll) {
        final p = cam.latLngToScreenPoint(ll);
        return Offset(p.x.toDouble(), p.y.toDouble());
      }).toList();
      _mapReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: const LatLng(39.4787, -0.3758),
            initialZoom: 17,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
            onMapReady: _updatePoints,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
              userAgentPackageName: 'app.runwar.runwar_app',
            ),
          ],
        ),
        if (_mapReady)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _IntroCaptureMapPainter(
                t: _ctrl.value,
                accent: widget.accent,
                pts: _pts,
              ),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

class _IntroCaptureMapPainter extends CustomPainter {
  final double t;
  final Color accent;
  final List<Offset> pts;
  _IntroCaptureMapPainter(
      {required this.t, required this.accent, required this.pts});

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;

    final route = pts;
    final segs = route.length - 1;

    final cornerCount = (pts.length - 1).clamp(1, pts.length);
    double sumX = 0, sumY = 0;
    for (int i = 0; i < cornerCount; i++) {
      sumX += pts[i].dx;
      sumY += pts[i].dy;
    }
    final centroid = Offset(sumX / cornerCount, sumY / cornerCount);

    final decayT = t > 0.8 ? ((t - 0.8) / 0.2).clamp(0.0, 1.0) : 0.0;

    final fillOpacity = t > 0.72
        ? ((t - 0.72) / 0.08).clamp(0.0, 1.0) * (1.0 - decayT) * 0.28
        : 0.0;
    if (fillOpacity > 0) {
      final fillP = Paint()
        ..color = accent.withValues(alpha: fillOpacity)
        ..style = PaintingStyle.fill;
      final fp = Path()..moveTo(route[0].dx, route[0].dy);
      for (int i = 1; i < route.length; i++) { fp.lineTo(route[i].dx, route[i].dy); }
      fp.close();
      canvas.drawPath(fp, fillP);
    }

    final drawPhase = (t / 0.72).clamp(0.0, 1.0);
    final totalLen = drawPhase * segs;
    final trailOpacity = 1.0 - decayT * 0.8;
    final routeP = Paint()
      ..color = accent.withValues(alpha: 0.65 * trailOpacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rp = Path()..moveTo(route[0].dx, route[0].dy);
    for (int i = 0; i < segs; i++) {
      if (totalLen > i) {
        final segT = (totalLen - i).clamp(0.0, 1.0);
        final next = (i + 1).clamp(0, segs);
        rp.lineTo(
          Offset.lerp(route[i], route[next], segT)!.dx,
          Offset.lerp(route[i], route[next], segT)!.dy,
        );
      }
    }
    canvas.drawPath(rp, routeP);

    if (t < 0.85) {
      final segIdx = totalLen.floor().clamp(0, segs - 1);
      final segT = (totalLen - segIdx).clamp(0.0, 1.0);
      final pos =
          Offset.lerp(route[segIdx], route[(segIdx + 1).clamp(0, segs)], segT)!;
      final runnerOpacity = 1.0 - (decayT * 0.9);
      canvas.drawCircle(
          pos,
          14,
          Paint()
            ..color = accent.withValues(alpha: 0.2 * runnerOpacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(
          pos, 5, Paint()..color = accent.withValues(alpha: runnerOpacity));
      canvas.drawCircle(
          pos,
          2,
          Paint()..color = Colors.white.withValues(alpha: runnerOpacity * 0.9));
    }

    if (t > 0.75 && t < 0.82) {
      final labelOpacity =
          (math.sin((t - 0.75) / 0.07 * math.pi)).clamp(0.0, 1.0);
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
      tp.paint(canvas,
          Offset(centroid.dx - tp.width / 2, centroid.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_IntroCaptureMapPainter old) =>
      old.t != t || old.pts != pts;
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))
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
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: const LatLng(39.4768, -0.3762),
            initialZoom: 14,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
            onMapReady: _onMapReady,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
              userAgentPackageName: 'app.runwar.runwar_app',
            ),
          ],
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

class _IntroRivalsMapPainter extends CustomPainter {
  final double t;
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

    void drawRunner(Offset pos, Color color) {
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

    drawRunner(r1, runner1Color);
    drawRunner(r2, runner2Color);
    drawRunner(r3, runner3Color);

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
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: _kDropCoord,
            initialZoom: 16,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
            onMapReady: _updatePoint,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              maxZoom: 19,
              retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
              userAgentPackageName: 'app.runwar.runwar_app',
            ),
          ],
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
