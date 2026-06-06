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
//   0.10–0.40  Player 3 (pink-red) runs real-street Valencia route, drawing a lasso.
//   0.40–0.711 Newly-claimed block enters dispute (amber fill + dashed border).
//              Dispute hold ≈ 2.8 s.
//   0.711–0.80 Shield icon (orange hex outline) flies from a bottom-center
//              inventory slot to the disputed centroid; stamps and pulses.
//              A blue-tinted hex aura outlines the disputed polygon.
//   0.80–0.944 3 staggered hex-aura pulses ripple outward; attacker lasso
//              fades; disputed fill stays amber.
//   0.944–1.00 Disputed block snaps to kAccent orange ownership; brief
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

  // Runner C (pink-red) — 9-point real-street Valencia GPS lasso.
  // pt9 == pt1 (lasso closure).
  static const _kP3RouteA = [
    LatLng(39.46314567232372,  -0.37789166434492444), // pt1
    LatLng(39.46106660289374,  -0.37641108503092524), // pt2
    LatLng(39.46218483520633,  -0.37378252030679626), // pt3
    LatLng(39.463448035941596, -0.372097621546374),   // pt4
    LatLng(39.46364710896024,  -0.37250909525302534), // pt5
    LatLng(39.46483306401015,  -0.3736557353361204),  // pt6
    LatLng(39.46333791021514,  -0.37794603459439946), // pt7
    LatLng(39.46295670439205,  -0.3777320682631042),  // pt8
    LatLng(39.46314567232372,  -0.37789166434492444), // pt9 = copy of pt1
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

      // Compute disputed area dynamically (screen-space, not GPS-space).
      final lassoScreen = _p3Route;
      final block1Screen = IntroZones.kS1Block1.map(toScreen).toList();
      var clipped = _sutherlandHodgman(lassoScreen, block1Screen);
      if (clipped.length < 3 || _polygonArea(clipped) <= 1.0) {
        // Fallback: try kS1Block2.
        final block2Screen = IntroZones.kS1Block2.map(toScreen).toList();
        clipped = _sutherlandHodgman(lassoScreen, block2Screen);
      }
      if (clipped.length >= 3 && _polygonArea(clipped) > 1.0) {
        _disputedArea = clipped;
        _sharedTransferVertices =
            _extractSharedVertices(clipped, block1Screen);
      } else {
        // Both intersections empty — skip all dispute visuals.
        _disputedArea = [];
        _sharedTransferVertices = [];
      }
    });
  }

  // ── Sutherland-Hodgman polygon clipping helpers ───────────────────────────

  static List<Offset> _sutherlandHodgman(
      List<Offset> subject, List<Offset> clip) {
    var output = List<Offset>.from(subject);
    if (output.isEmpty) return output;
    final n = clip.length;
    for (int i = 0; i < n; i++) {
      if (output.isEmpty) break;
      final input = List<Offset>.from(output);
      output.clear();
      final edgeA = clip[i];
      final edgeB = clip[(i + 1) % n];
      for (int j = 0; j < input.length; j++) {
        final curr = input[j];
        final prev = input[(j + 1) % input.length];
        final currInside = _isInside(curr, edgeA, edgeB);
        final prevInside = _isInside(prev, edgeA, edgeB);
        if (currInside) {
          if (!prevInside) output.add(_intersection(prev, curr, edgeA, edgeB));
          output.add(curr);
        } else if (prevInside) {
          output.add(_intersection(prev, curr, edgeA, edgeB));
        }
      }
    }
    return output;
  }

  static bool _isInside(Offset p, Offset a, Offset b) =>
      (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx) >= 0;

  static Offset _intersection(Offset a, Offset b, Offset c, Offset d) {
    final dxAB = b.dx - a.dx, dyAB = b.dy - a.dy;
    final dxCD = d.dx - c.dx, dyCD = d.dy - c.dy;
    final denom = dxAB * dyCD - dyAB * dxCD;
    if (denom.abs() < 1e-10) return a; // parallel — degenerate guard
    final t = ((c.dx - a.dx) * dyCD - (c.dy - a.dy) * dxCD) / denom;
    return Offset(a.dx + t * dxAB, a.dy + t * dyAB);
  }

  static double _polygonArea(List<Offset> pts) {
    if (pts.length < 3) return 0.0;
    double area = 0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      area += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
    }
    return area.abs() / 2.0;
  }

  static List<Offset> _extractSharedVertices(
      List<Offset> disputed, List<Offset> block,
      {double eps = 2.0}) {
    return disputed
        .where((d) => block.any((b) => (d - b).distance < eps))
        .toList();
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
            center: const LatLng(39.463, -0.376),
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
                final tailPx = (_ctrl.value * kIntroRouteEstimatedMeters)
                        .clamp(0.0, kCometTailMaxMeters) /
                    metersPerPx;
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

  // Phase boundaries (9 s loop, t ∈ [0, 1]).
  static const double _kRouteStart = 0.10;
  static const double _kRouteEnd = 0.40;
  static const double _kDisputeStart = 0.40;
  static const double _kShieldFlyStart = 0.711;
  static const double _kShieldArrive = 0.800;
  static const double _kPulseStart = 0.800;
  static const double _kPulseEnd = 0.944;
  static const double _kSnapStart = 0.944;

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

    // Lasso trace fade — fully visible until 0.800, then fades to 0 by 0.944.
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

    // [NEW] Residual attacker-claim fill (AC-6).
    // Difference of lasso minus disputed area; persists from _kDisputeStart through t=1.0.
    if (t >= _kDisputeStart && disputedArea.length >= 3 && p3Route.length >= 3) {
      final lassoPath = _polyPath(p3Route);
      final disputedPath = _polyPath(disputedArea);
      final residualPath =
          Path.combine(PathOperation.difference, lassoPath, disputedPath);
      final residualBounds = residualPath.getBounds();
      if (residualBounds.width > 0 && residualBounds.height > 0) {
        canvas.drawPath(
          residualPath,
          Paint()
            ..color = p3Color.withValues(alpha: 0.38)
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Ping burst at lasso close — fires on the shared kS1Block1 vertices
    // (A and D) where defender territory transfers to the attacker.
    if (sharedTransferVertices.isNotEmpty) {
      final pingT = (t - _kDisputeStart) / 0.15; // ramp 0.40–0.55
      if (pingT > 0 && pingT < 1.0) {
        drawPings(canvas, sharedTransferVertices, pingT.clamp(0.0, 1.0));
      }
    }

    // Phase 2: 0.40–0.944 — disputed area amber fill + dashed amber border.
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

    // Phase 3: 0.711–0.800 — shield icon flies from inventory slot to centroid.
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

    // Phase 3b: 0.800 onward — hex glyph stamped at centroid, pulsing alpha.
    if (t >= _kShieldArrive && centroid != Offset.zero) {
      // Pulse alpha 0.7 → 1.0 → 0.7 via sine wave.
      // Fade out after 0.944 (during snap).
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

    // Phase 3c: 0.711–0.944 — blue-tinted hex aura outlining the disputed area.
    if (t >= _kShieldFlyStart && t < _kSnapStart && disputedArea.length >= 3) {
      // Fade in from 0.711–0.800, hold, fade out 0.90–0.944.
      double auraFade;
      if (t < _kShieldArrive) {
        auraFade = ((t - _kShieldFlyStart) / 0.089).clamp(0.0, 1.0);
      } else if (t < 0.90) {
        auraFade = 1.0;
      } else {
        auraFade = (1.0 - (t - 0.90) / 0.044).clamp(0.0, 1.0);
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

    // Phase 4: 0.800–0.944 — 3 concentric hex auras pulse outward.
    if (t >= _kPulseStart && t < _kPulseEnd && centroid != Offset.zero) {
      const pulseSpan = _kPulseEnd - _kPulseStart; // 0.144
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

    // Phase 5: 0.944–1.00 — "DEFENDED" label fades in at centroid.
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
