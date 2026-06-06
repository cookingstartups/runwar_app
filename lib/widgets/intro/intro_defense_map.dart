import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 6A. IntroDefenseMapA — SHIELD superpower, Variant A "Inventory Drop"
//
// Scene (9s loop, t ∈ [0,1]):
//   0.00–0.20  Inherited orange Ruzafa territory visible.
//   0.10–0.40  Player 3 (pink-red) runs from Renfe Norte → adjacent fresh block,
//              drawing a lasso.
//   0.40–0.55  Newly-claimed block enters dispute (amber fill + dashed border).
//   0.55–0.70  Shield icon (orange hex outline) flies from a bottom-center
//              inventory slot to the disputed centroid; stamps and pulses.
//              A blue-tinted hex aura outlines the disputed polygon.
//   0.70–0.95  3 staggered hex-aura pulses ripple outward; attacker lasso
//              fades; disputed fill stays amber.
//   0.95–1.00  Disputed block snaps to kAccent orange ownership; brief
//              "DEFENDED" label at centroid.
// ---------------------------------------------------------------------------
class IntroDefenseMapA extends StatefulWidget {
  final Color accent;
  const IntroDefenseMapA({required this.accent, super.key});
  @override
  State<IntroDefenseMapA> createState() => _IntroDefenseMapAState();
}

class _IntroDefenseMapAState extends State<IntroDefenseMapA>
    with TickerProviderStateMixin, IntroMapMixin<IntroDefenseMapA> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Runner C (pink-red) — Renfe Norte → south on Xàtiva → lasso overlapping kS1Block1 north edge.
  static const _kP3RouteA = [
    LatLng(39.4658, -0.3766), // 0: Renfe Estación del Norte entrance
    LatLng(39.4645, -0.3766), // 1: south on Carrer de Xàtiva
    LatLng(39.4635, -0.3763), // 2: approaching Ruzafa north boundary
    LatLng(39.4632, -0.3762), // 3: lasso start — NW corner of lasso
    LatLng(39.4632, -0.3750), // 4: NE corner (heading east)
    LatLng(39.4614, -0.3750), // 5: SE corner (heading south)
    LatLng(39.4614, -0.3762), // 6: SW corner — closes back to pt3
  ];

  // Sutherland-Hodgman clip of kS1Block1 against the lasso rectangle.
  // A and D are inside; B and C are outside. Two crossing points on the lasso's west edge.
  static const _kDisputedA = [
    LatLng(39.46208, -0.37552), // A — kS1Block1 NE vertex (inside lasso)
    LatLng(39.46267, -0.37594), // D — kS1Block1 N vertex (inside lasso)
    LatLng(39.46255, -0.37620), // C→D segment × lasso west edge (lng=-0.3762)
    LatLng(39.46181, -0.37620), // A→B segment × lasso west edge (lng=-0.3762)
  ];

  // Shared transfer vertices — actual kS1Block1 boundary vertices that lie
  // inside the lasso. Used for ping bursts on the defender→attacker handoff.
  static const _kSharedTransferVerticesA = [
    LatLng(39.46208, -0.37552), // A — kS1Block1 vertex
    LatLng(39.46267, -0.37594), // D — kS1Block1 vertex
  ];

  // Pink-red attacker color for player 3.
  static const Color _kP3Color = Color(0xFFFF3B7A);

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _p3Route = [];
  List<Offset> _disputedArea = [];
  List<Offset> _sharedTransferVertices = [];

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
      _p3Route = _kP3RouteA.map(toScreen).toList();
      _disputedArea = _kDisputedA.map(toScreen).toList();
      _sharedTransferVertices =
          _kSharedTransferVerticesA.map(toScreen).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 9));
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    loopController(_ctrl, mounted: () => mounted);
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
          buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4621, -0.3762),
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
                final tailPx = kCometTailMeters / metersPerPx;
                return CustomPaint(
                  painter: _IntroDefenseMapAPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    p3Route: _p3Route,
                    disputedArea: _disputedArea,
                    sharedTransferVertices: _sharedTransferVertices,
                    p3Color: _kP3Color,
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

class _IntroDefenseMapAPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> p3Route;
  final List<Offset> disputedArea;
  final List<Offset> sharedTransferVertices;
  final Color p3Color;
  final double tailLengthPx;

  _IntroDefenseMapAPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.p3Route,
    required this.disputedArea,
    required this.sharedTransferVertices,
    required this.p3Color,
    required this.tailLengthPx,
  });

  // Phase boundaries.
  static const double _kRouteStart = 0.10;
  static const double _kRouteEnd = 0.40;
  static const double _kDisputeStart = 0.40;
  static const double _kShieldFlyStart = 0.55;
  static const double _kShieldArrive = 0.65;
  static const double _kPulseStart = 0.70;
  static const double _kPulseEnd = 0.95;
  static const double _kSnapStart = 0.95;

  Offset _centroid(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    double sx = 0, sy = 0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  /// Build a closed Path through [pts].
  Path _polyPath(List<Offset> pts) {
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    p.close();
    return p;
  }

  /// Draw a dashed stroke along a closed polygon.
  void _drawDashedPolygon(
    Canvas canvas,
    List<Offset> pts,
    Paint paint, {
    double dash = 6,
    double gap = 4,
  }) {
    if (pts.length < 2) return;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final seg = b - a;
      final len = seg.distance;
      if (len == 0) continue;
      final dir = seg / len;
      double traveled = 0;
      while (traveled < len) {
        final start = a + dir * traveled;
        final end = a + dir * math.min(traveled + dash, len);
        canvas.drawLine(start, end, paint);
        traveled += dash + gap;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (p3Route.isEmpty) return;

    final segs = p3Route.length - 1;
    final centroid = _centroid(disputedArea);

    // 0. Inherited orange Ruzafa territory.
    drawInheritedBlocks(canvas, inheritedPts);

    // Phase 1: 0.10–0.40 — player 3 runs + lasso draws.
    final routeProgress =
        ((t - _kRouteStart) / (_kRouteEnd - _kRouteStart)).clamp(0.0, 1.0);

    // Lasso trace fade — fully visible until 0.70, then fades to 0 by 0.95.
    final lassoFade = t < _kPulseStart
        ? 1.0
        : (1.0 - (t - _kPulseStart) / (_kPulseEnd - _kPulseStart))
            .clamp(0.0, 1.0);

    if (lassoFade > 0 && routeProgress > 0) {
      drawComet(
        canvas,
        p3Route,
        routeProgress,
        tailLengthPx: tailLengthPx,
        color: p3Color,
        decayMul: lassoFade,
      );
    }

    // Runner dot for player 3 while route is being drawn.
    if (t >= _kRouteStart && t < _kShieldFlyStart && segs > 0) {
      final traveled = routeProgress * segs;
      final segIdx = traveled.floor().clamp(0, segs - 1);
      final segFrac = (traveled - segIdx).clamp(0.0, 1.0);
      final pos = Offset.lerp(
        p3Route[segIdx],
        p3Route[(segIdx + 1).clamp(0, segs)],
        segFrac,
      )!;
      canvas.drawCircle(
        pos,
        12,
        Paint()
          ..color = p3Color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(pos, 4.5, Paint()..color = p3Color);
      canvas.drawCircle(
        pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    // Ping burst at lasso close — fires on the shared kS1Block1 vertices
    // (A and D) where defender territory transfers to the attacker.
    if (sharedTransferVertices.isNotEmpty) {
      final pingT = (t - _kDisputeStart) / 0.15; // ramp 0.40–0.55
      if (pingT > 0 && pingT < 1.0) {
        drawPings(canvas, sharedTransferVertices, pingT.clamp(0.0, 1.0));
      }
    }

    // Phase 2: 0.40–0.95 — disputed area amber fill + dashed amber border.
    // (Snaps to orange in phase 5.)
    const disputedAmber = Color(0xFFFFB200);
    if (disputedArea.length >= 3) {
      if (t >= _kDisputeStart && t < _kSnapStart) {
        final dispRamp =
            ((t - _kDisputeStart) / 0.15).clamp(0.0, 1.0); // ramp 0.40–0.55
        drawFillColor(canvas, disputedArea, disputedAmber, dispRamp * 0.38);

        // Dashed amber border, same ramp.
        if (dispRamp > 0) {
          final dashPaint = Paint()
            ..color = disputedAmber.withValues(alpha: dispRamp)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round;
          _drawDashedPolygon(canvas, disputedArea, dashPaint);
        }
      } else if (t >= _kSnapStart) {
        // Phase 5: snap amber → orange.
        final snapT = ((t - _kSnapStart) / 0.05).clamp(0.0, 1.0);
        final dispColor = Color.lerp(disputedAmber, kAccent, snapT)!;
        drawFillColor(canvas, disputedArea, dispColor, 0.38);
      }
    }

    // Phase 3: 0.55–0.70 — shield icon flies from inventory slot to centroid.
    final inventoryPos = Offset(size.width / 2, size.height - 40);

    if (t >= _kShieldFlyStart && t < _kShieldArrive && centroid != Offset.zero) {
      final flyT = ((t - _kShieldFlyStart) /
              (_kShieldArrive - _kShieldFlyStart))
          .clamp(0.0, 1.0);
      final pos = Offset.lerp(inventoryPos, centroid, flyT)!;
      final alpha = flyT.clamp(0.0, 1.0);

      // Soft glow.
      canvas.drawCircle(
        pos,
        14,
        Paint()
          ..color = accent.withValues(alpha: 0.35 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      // Hex glyph outline.
      drawHexGlyph(
        canvas,
        pos,
        10,
        Paint()
          ..color = accent.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Phase 3b: 0.65 onward — hex glyph stamped at centroid, pulsing alpha.
    if (t >= _kShieldArrive && centroid != Offset.zero) {
      // Pulse alpha 0.7 → 1.0 → 0.7 via sine wave.
      // Fade out after 0.95 (during snap).
      final stampPulse = 0.85 + 0.15 * math.sin((t - _kShieldArrive) * math.pi * 4);
      final stampFade = t < _kSnapStart
          ? 1.0
          : (1.0 - (t - _kSnapStart) / 0.05).clamp(0.0, 1.0);

      drawHexGlyph(
        canvas,
        centroid,
        10,
        Paint()
          ..color = accent.withValues(alpha: stampPulse * stampFade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Phase 3c: 0.55–0.95 — blue-tinted hex aura outlining the disputed area.
    if (t >= _kShieldFlyStart && t < _kSnapStart && disputedArea.length >= 3) {
      // Fade in from 0.55–0.65, hold, fade out 0.90–0.95.
      double auraFade;
      if (t < _kShieldArrive) {
        auraFade = ((t - _kShieldFlyStart) / 0.10).clamp(0.0, 1.0);
      } else if (t < 0.90) {
        auraFade = 1.0;
      } else {
        auraFade = (1.0 - (t - 0.90) / 0.05).clamp(0.0, 1.0);
      }
      if (auraFade > 0) {
        final auraPaint = Paint()
          ..color = kSea.withValues(alpha: 0.4 * auraFade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(_polyPath(disputedArea), auraPaint);
      }
    }

    // Phase 4: 0.70–0.95 — 3 concentric hex auras pulse outward.
    if (t >= _kPulseStart && t < _kPulseEnd && centroid != Offset.zero) {
      const pulseSpan = _kPulseEnd - _kPulseStart; // 0.25
      // Stagger ~0.4s apart in a 9s loop = 0.0444 of t per stagger.
      const stagger = 0.044;
      const perPulse = 0.18; // each pulse expands over 0.18 of t

      for (int i = 0; i < 3; i++) {
        final localStart = _kPulseStart + i * stagger;
        if (t < localStart) continue;
        final ringT = ((t - localStart) / perPulse).clamp(0.0, 1.0);
        if (ringT >= 1.0) continue;
        final radius = 20 + ringT * 60; // 20 → 80
        final ringAlpha = (1.0 - ringT) * 0.55;
        drawHexGlyph(
          canvas,
          centroid,
          radius,
          Paint()
            ..color = kSea.withValues(alpha: ringAlpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
      // Silence unused-const warning (pulseSpan documents intent).
      assert(pulseSpan > 0);
    }

    // Phase 5: 0.95–1.00 — "DEFENDED" label fades in at centroid.
    if (t >= _kSnapStart && centroid != Offset.zero) {
      final labelFade = ((t - _kSnapStart) / 0.05).clamp(0.0, 1.0);
      if (labelFade > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'DEFENDED',
            style: GoogleFonts.bebasNeue(
              fontSize: 18,
              letterSpacing: 1.5,
              color: accent.withValues(alpha: labelFade),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            centroid.dx - tp.width / 2,
            centroid.dy - tp.height - 18,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_IntroDefenseMapAPainter old) =>
      old.t != t ||
      old.tailLengthPx != tailLengthPx ||
      old.p3Route != p3Route ||
      old.disputedArea != disputedArea ||
      old.sharedTransferVertices != sharedTransferVertices ||
      old.inheritedPts != inheritedPts;
}

// ---------------------------------------------------------------------------
// 6b. IntroDefenseMapB — SHIELD Variant B (HUD toast + hex rings + linger glow)
// ---------------------------------------------------------------------------
class IntroDefenseMapB extends StatefulWidget {
  final Color accent;
  const IntroDefenseMapB({required this.accent, super.key});
  @override
  State<IntroDefenseMapB> createState() => _IntroDefenseMapBState();
}

class _IntroDefenseMapBState extends State<IntroDefenseMapB>
    with TickerProviderStateMixin, IntroMapMixin<IntroDefenseMapB> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Player 3 (pink-red) attacks from Renfe Estación del Norte.
  static const _kP3RouteB = [
    LatLng(39.4658, -0.3766), // 0: Renfe Norte entrance
    LatLng(39.4648, -0.3760), // 1: heading south
    LatLng(39.4638, -0.3758), // 2: approaching Ruzafa
    LatLng(39.4631, -0.3758), // 3: lasso start
    LatLng(39.4631, -0.3750), // 4: NE corner
    LatLng(39.4623, -0.3750), // 5: SE corner
    LatLng(39.4623, -0.3758), // 6: SW corner — closes
  ];

  static const _kDisputedB = [
    LatLng(39.4631, -0.3758),
    LatLng(39.4631, -0.3752),
    LatLng(39.4626, -0.3752),
    LatLng(39.4626, -0.3758),
  ];

  static const Color _kP3Color = Color(0xFFFF3B7A);

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _p3Route = [];
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
      _p3Route = _kP3RouteB.map(toScreen).toList();
      _disputedArea = _kDisputedB.map(toScreen).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 9));
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    loopController(_ctrl, mounted: () => mounted);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _ctrl.dispose();
    disposeMapCtrl();
    super.dispose();
  }

  /// Toast vertical position: lerps -48 → 48 between t=0.55 and t=0.58,
  /// holds at 48 until t=0.70, then reverses back to -48 by t=0.73.
  double _toastTop(double t) {
    if (t < 0.55) return -48;
    if (t < 0.58) {
      final p = ((t - 0.55) / 0.03).clamp(0.0, 1.0);
      // ease-out
      final eased = 1 - math.pow(1 - p, 3).toDouble();
      return -48 + (48 - (-48)) * eased;
    }
    if (t < 0.70) return 48;
    if (t < 0.73) {
      final p = ((t - 0.70) / 0.03).clamp(0.0, 1.0);
      final eased = math.pow(p, 3).toDouble();
      return 48 + (-48 - 48) * eased;
    }
    return -48;
  }

  double _toastOpacity(double t) {
    if (t < 0.55 || t >= 0.73) return 0.0;
    return 1.0;
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
            center: const LatLng(39.4640, -0.3758),
            zoom: 16.0,
            onReady: _onMapReady,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _IntroDefenseMapBPainter(
                  t: _ctrl.value,
                  accent: widget.accent,
                  inheritedPts: _inheritedPts,
                  p3Route: _p3Route,
                  disputedArea: _disputedArea,
                  p3Color: _kP3Color,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          // HUD toast overlay — slides DOWN from top.
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final t = _ctrl.value;
                final top = _toastTop(t);
                final fade = _toastOpacity(t);
                if (fade <= 0) return const SizedBox.shrink();
                return Positioned(
                  top: top,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: kAccent2.withValues(alpha: 0.85 * fade),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomPaint(
                              size: const Size(20, 20),
                              painter: _HexGlyphPainter(
                                color: Colors.white.withValues(alpha: fade),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Superpower Activated · SHIELD',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.bebasNeue(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: fade),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _IntroDefenseMapBPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> p3Route;
  final List<Offset> disputedArea;
  final Color p3Color;

  _IntroDefenseMapBPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.p3Route,
    required this.disputedArea,
    required this.p3Color,
  });

  // Timeline:
  //   0.00–0.20  inherited orange territory visible.
  //   0.10–0.40  player 3 runs from Renfe, lassos adjacent block.
  //   0.40–0.55  dispute phase: amber fill + dashed amber border.
  //   0.55–0.70  SHIELD activates: HUD toast (widget overlay) + hex rings expand.
  //   0.70–0.95  polygon glow lingers (slow sin pulse); attacker trace fades.
  //   0.95–1.00  snap to orange + brief "DEFENDED" label.
  static const double _kRouteStartT = 0.10;
  static const double _kRouteEndT = 0.40;

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

  /// Stroke a polygon with dashed segments using the given paint.
  void _drawDashedPolygon(Canvas canvas, List<Offset> pts, Paint paint,
      {double dashLen = 6, double gapLen = 4}) {
    if (pts.length < 2) return;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len <= 0) continue;
      final ux = dx / len;
      final uy = dy / len;
      double cursor = 0;
      while (cursor < len) {
        final segEnd = math.min(cursor + dashLen, len);
        canvas.drawLine(
          Offset(a.dx + ux * cursor, a.dy + uy * cursor),
          Offset(a.dx + ux * segEnd, a.dy + uy * segEnd),
          paint,
        );
        cursor = segEnd + gapLen;
      }
    }
  }

  /// Stroke an open polyline from a list of points with a paint.
  void _strokePolyline(Canvas canvas, List<Offset> pts, Paint paint) {
    if (pts.length < 2) return;
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(p, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (p3Route.isEmpty) return;

    final centroid = _disputedCentroid();

    // 0. Inherited orange territory.
    drawInheritedBlocks(canvas, inheritedPts);

    // Phase 1: 0.10–0.40 — Player 3 runs from Renfe and lassos.
    final routeProgress =
        ((t - _kRouteStartT) / (_kRouteEndT - _kRouteStartT)).clamp(0.0, 1.0);
    final segs = p3Route.length - 1;
    final traveled = routeProgress * segs;

    // Attacker trace — fades 0.70→0.85.
    final traceFade = t < 0.70
        ? 0.7
        : (0.7 * (1.0 - (t - 0.70) / 0.15)).clamp(0.0, 0.7);
    if (traceFade > 0 && routeProgress > 0) {
      drawTraceColor(canvas, p3Route, routeProgress,
          p3Color.withValues(alpha: traceFade));
    }

    // Attacker runner dot (only while running, then disappears).
    if (t >= _kRouteStartT && t < 0.70 && routeProgress < 1.0) {
      final segIdx = traveled.floor().clamp(0, segs - 1);
      final segFrac = (traveled - segIdx).clamp(0.0, 1.0);
      final pos = Offset.lerp(
        p3Route[segIdx],
        p3Route[(segIdx + 1).clamp(0, segs)],
        segFrac,
      )!;
      canvas.drawCircle(
          pos,
          12,
          Paint()
            ..color = p3Color.withValues(alpha: 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      canvas.drawCircle(pos, 4.5, Paint()..color = p3Color);
      canvas.drawCircle(
          pos, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }

    // Phase 2: 0.40–0.55 — dispute amber fill + dashed amber border.
    if (t >= 0.40 && disputedArea.isNotEmpty) {
      const amber = Color(0xFFFFB200);
      if (t < 0.55) {
        final dispRamp = ((t - 0.40) / 0.15).clamp(0.0, 1.0);
        drawFillColor(canvas, disputedArea, amber, dispRamp * 0.35);
        final borderPaint = Paint()
          ..color = amber.withValues(alpha: dispRamp * 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        _drawDashedPolygon(canvas, disputedArea, borderPaint);
      } else if (t < 0.95) {
        // Sustained dispute fill until snap.
        drawFillColor(canvas, disputedArea, amber, 0.35);
        final borderPaint = Paint()
          ..color = amber.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        _drawDashedPolygon(canvas, disputedArea, borderPaint);
      } else {
        // 0.95–1.00 — snap to orange.
        final snapT = ((t - 0.95) / 0.05).clamp(0.0, 1.0);
        final c = Color.lerp(amber, kAccent, snapT)!;
        drawFillColor(canvas, disputedArea, c, 0.45);
      }
    }

    // Phase 3a: 0.58–0.70 — 3 hex shield rings expand from centroid.
    if (t >= 0.58 && centroid != Offset.zero) {
      for (int i = 0; i < 3; i++) {
        final ringT = ((t - 0.58 - i * 0.04) / 0.12).clamp(0.0, 1.0);
        if (ringT > 0 && ringT < 1.0) {
          _drawHexRing(
              canvas,
              centroid,
              ringT * 70,
              Paint()
                ..color = kSea.withValues(alpha: (1.0 - ringT) * 0.55)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.0);
        }
      }
    }

    // Phase 3b: 0.70–0.95 — polygon outline glow lingers (slow sin pulse).
    if (t >= 0.70 && t < 0.95 && disputedArea.isNotEmpty) {
      final pulse = 0.40 + 0.50 * math.sin(t * math.pi * 6).abs();
      final glowPaint = Paint()
        ..color = kSea.withValues(alpha: pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round;
      // Build closed polyline.
      final closed = [...disputedArea, disputedArea.first];
      _strokePolyline(canvas, closed, glowPaint);
    }

    // Phase 4: 0.95–1.00 — brief "DEFENDED" label near top-left of disputed.
    if (t >= 0.95 && disputedArea.isNotEmpty) {
      final labelFade = ((t - 0.95) / 0.04).clamp(0.0, 1.0);
      if (labelFade > 0) {
        final anchor = disputedArea.first;
        final tp = TextPainter(
          text: TextSpan(
            text: 'DEFENDED',
            style: GoogleFonts.bebasNeue(
              fontSize: 22,
              color: accent.withValues(alpha: labelFade),
              letterSpacing: 2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(anchor.dx - 4, anchor.dy - tp.height - 6));
      }
    }
  }

  @override
  bool shouldRepaint(_IntroDefenseMapBPainter old) =>
      old.t != t ||
      old.p3Route != p3Route ||
      old.disputedArea != disputedArea ||
      old.inheritedPts != inheritedPts;
}

/// Small hexagon glyph painter — used inside the HUD toast.
class _HexGlyphPainter extends CustomPainter {
  final Color color;
  const _HexGlyphPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 8.0;
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
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HexGlyphPainter old) => old.color != color;
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
    with TickerProviderStateMixin, IntroMapMixin<IntroDefenseMapC> {
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
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 9));
    Future.delayed(kIntroFadeDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
    loopController(_ctrl, mounted: () => mounted);
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
          buildIntroMap(
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

class _IntroDefenseMapCPainter extends CustomPainter with IntroPainterHelpers {
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
