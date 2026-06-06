import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

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
    with TickerProviderStateMixin, IntroMapMixin<IntroCaptureMap> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  // Attacker route — blue rival (kSea) runs S→N along Carrer de Cuba (real
  // Ruzafa street, sourced via /gps-streets from Overpass on 2026-06-06), enters
  // kS1Block1 from the south, then traces a closed lasso wrapping the block on
  // three sides before returning to the inside-block start point.
  //   pt0 → pt1: north along Cuba, off-screen south → inside kS1Block1
  //   pt1 → pt2: SE exit (cross block edge A–B southward)
  //   pt2 → pt3: north along east side (outside block)
  //   pt3 → pt4: west across the top (outside block)
  //   pt4 → pt5: south back into block (cross block edge C–D into interior); pt5 ≈ pt1
  static const _kAttackerRoute = [
    LatLng(39.4585831, -0.3746524), // 0: Carrer de Cuba — off-screen south (entry)
    LatLng(39.4619,    -0.376650),  // 1: inside kS1Block1 (south interior) — lasso start
    LatLng(39.4605,    -0.374800),  // 2: SE of block (outside)
    LatLng(39.4633,    -0.375000),  // 3: NE of block (outside)
    LatLng(39.4633,    -0.378000),  // 4: NW of block (outside)
    LatLng(39.4619,    -0.376650),  // 5: lasso close = pt1 (inside kS1Block1)
  ];

  // Lasso polygon — closed loop pt1 → pt2 → pt3 → pt4 → pt5 (≈ pt1). Encloses
  // ~79% of kS1Block1 (overlap area ~7100 m² out of 8941 m²).
  static const _kAttackerLasso = [
    LatLng(39.4619, -0.376650),    // pt1 — inside kS1Block1 (lasso start)
    LatLng(39.4605, -0.374800),    // pt2 — outside SE
    LatLng(39.4633, -0.375000),    // pt3 — outside NE
    LatLng(39.4633, -0.378000),    // pt4 — outside NW
    LatLng(39.4619, -0.376650),    // pt5 — close = pt1
  ];

  // Disputed area — exact Sutherland-Hodgman intersection of _kAttackerLasso
  // with kS1Block1 (sole clip target, computed offline 2026-06-06).
  // 5 vertices, ~7100 m² (79.4% of kS1Block1 area). Vertices:
  //   D — block vertex (lasso encloses)
  //   crossing of lasso edge pt3→pt4 with block edge C–D
  //   pt1 — lasso vertex inside block
  //   crossing of lasso edge pt5→pt1 (≡ pt4→pt1 in closed lasso) with block edge A–B
  //   A — block vertex (lasso encloses)
  static const _kDisputedArea = [
    LatLng(39.4626710000, -0.3759370000), // D — kS1Block1 vertex inside lasso
    LatLng(39.4622369806, -0.3769749456), // lasso edge ∩ block edge C–D
    LatLng(39.4619000000, -0.3766500000), // pt1 — lasso vertex inside block
    LatLng(39.4617161880, -0.3764071056), // lasso edge ∩ block edge A–B
    LatLng(39.4620770000, -0.3755220000), // A — kS1Block1 vertex inside lasso
  ];

  // Shared transfer vertices — points where territory changes hands. Includes
  // the two real edge-crossings of the lasso boundary against kS1Block1, plus
  // one captured block vertex (A) for narrative weight. ≥3 entries are required
  // by drawPings guard (intro_helpers.dart:274); if fewer than 3 are listed,
  // ping rings silently suppress.
  static const _kSharedTransferVertices = [
    LatLng(39.4617161880, -0.3764071056), // lasso edge ∩ block edge A–B
    LatLng(39.4622369806, -0.3769749456), // lasso edge ∩ block edge C–D
    LatLng(39.4620770000, -0.3755220000), // A — captured block vertex
  ];

  List<List<Offset>> _inheritedPts = [];
  List<Offset> _ownedBlock1 = [];
  List<Offset> _ownedBlock2 = [];
  List<Offset> _attackerRoute = [];
  List<Offset> _attackerLasso = [];
  List<Offset> _disputedArea = [];
  List<Offset> _sharedTransferVertices = [];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8));
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
      _sharedTransferVertices =
          _kSharedTransferVertices.map(toScreen).toList();
    });
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
            center: const LatLng(39.4650, -0.3750),
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                double tailPx = 0.0;
                if (mapReady) {
                  final zoom = mapCtrl.camera.zoom;
                  final lat = mapCtrl.camera.center.latitudeInRad;
                  const earthCircumference = 2 * math.pi * 6378137.0;
                  final metersPerPx = (earthCircumference * math.cos(lat)) /
                      (256.0 * math.pow(2.0, zoom));
                  tailPx = (_ctrl.value * kIntroRouteEstimatedMeters).clamp(0.0, kCometTailMaxMeters) / metersPerPx;
                }
                return CustomPaint(
                  painter: _IntroCaptureMapPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    ownedBlock1: _ownedBlock1,
                    ownedBlock2: _ownedBlock2,
                    attackerRoute: _attackerRoute,
                    attackerLasso: _attackerLasso,
                    disputedArea: _disputedArea,
                    sharedTransferVertices: _sharedTransferVertices,
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

class _IntroCaptureMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> ownedBlock1;
  final List<Offset> ownedBlock2;
  final List<Offset> attackerRoute;
  final List<Offset> attackerLasso;
  final List<Offset> disputedArea;
  final List<Offset> sharedTransferVertices;
  final double tailLengthPx;

  _IntroCaptureMapPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.ownedBlock1,
    required this.ownedBlock2,
    required this.attackerRoute,
    required this.attackerLasso,
    required this.disputedArea,
    required this.sharedTransferVertices,
    required this.tailLengthPx,
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
  // Formula: _kAttackerRoute.length - 2 (last segment closes back to pt1).
  // For a 6-point route → 5 segments → close at segment 4 (pt4→pt5, pt5 ≈ pt1).
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

    final segs = attackerRoute.length - 1; // 5 segments for 6-point route
    final routeProgress = (t / _kRouteCompleteT).clamp(0.0, 1.0);
    final traveled = routeProgress * segs;
    final lassoIsClosed = traveled >= _kLassoCloseSegIdx;
    final fade = _globalFade(t);

    // Dispute detection — computed early so inherited blocks can subtract
    // the disputed area once the attacker has claimed it (t >= _kUnifyT).
    // A "genuine" dispute requires the clipped polygon to have ≥3 vertices
    // and a non-zero screen-space area. Touching at a single vertex or
    // along an edge yields a degenerate polygon (area ≈ 0) and is NOT a
    // dispute — the attacker simply claims their full lasso area in kSea.
    final hasGenuineDispute = disputedArea.length >= 3 &&
        _polygonArea(disputedArea) > 1.0; // > 1 px² in screen space

    // 0. Inherited blocks from slide 1 — pre-filled, no animation. After the
    //    dispute resolves (t >= _kUnifyT) we cut the disputed polygon out of
    //    the defender's combined territory so the orange visibly shrinks to
    //    match the attacker's gain. Note: drawInheritedBlocks executes at t=0
    //    (no pre-roll branch) so the three Ruzafa blocks are visible from
    //    the very first frame at alpha 0.28 (AC-1).
    if (lassoIsClosed && t >= _kUnifyT && hasGenuineDispute &&
        inheritedPts.isNotEmpty) {
      Path inheritedUnion = _makePoly(inheritedPts.first);
      for (int i = 1; i < inheritedPts.length; i++) {
        inheritedUnion = Path.combine(
          PathOperation.union,
          inheritedUnion,
          _makePoly(inheritedPts[i]),
        );
      }
      final disputedCut = _makePoly(disputedArea);
      final shrunk = Path.combine(
        PathOperation.difference,
        inheritedUnion,
        disputedCut,
      );
      canvas.drawPath(
        shrunk,
        Paint()
          ..color = kAccent.withValues(alpha: 0.28 * fade)
          ..style = PaintingStyle.fill,
      );
    } else {
      drawInheritedBlocks(canvas, inheritedPts);
    }

    // 1. Static orange owned territory fills for this slide — always visible.
    drawFillColor(canvas, ownedBlock1, kAccent, 0.22 * fade);
    drawFillColor(canvas, ownedBlock2, kAccent, 0.22 * fade);

    // 2. Attacker trail: runner traces route until close; afterwards full trace stays.
    if (!lassoIsClosed) {
      drawComet(canvas, attackerRoute, routeProgress,
          tailLengthPx: tailLengthPx, color: kSea);
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
      // Lasso outline fades as dispute resolves — compute decayMul so the
      // trace disappears after the runner's curve-out window ends (~t 0.64).
      final lassoCloseT = (_kLassoCloseSegIdx / (attackerRoute.length - 1).toDouble()) * _kRouteCompleteT;
      final traceDecay = t < lassoCloseT + 0.08
          ? 1.0
          : (1.0 - ((t - (lassoCloseT + 0.08)) / 0.10)).clamp(0.0, 1.0);
      drawTraceColor(canvas, attackerRoute, 1.0, kSea, alphaMul: traceDecay * fade);
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
    // on a clean attacker claim). Fires only on the shared-edge vertices
    // (E, F, G) where defender territory transfers to attacker, not across
    // the full disputed polygon boundary.
    final pingT = traveled - _kLassoCloseSegIdx;
    if (pingT > 0 && pingT < 1.5 && hasGenuineDispute) {
      drawPings(canvas, sharedTransferVertices, (pingT / 1.5).clamp(0.0, 1.0));
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
      old.inheritedPts != inheritedPts ||
      old.tailLengthPx != tailLengthPx;
}
