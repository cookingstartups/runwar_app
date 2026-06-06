import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

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
    with TickerProviderStateMixin, IntroMapMixin<IntroRivalsMap> {
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
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat();
    Future.delayed(kIntroFadeDelay, () {
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
          buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4665, -0.3768),
            zoom: 16.0,
            onReady: _onMapReady,
          ),
          if (mapReady)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final tailPx = () {
                  final zoom = mapCtrl.camera.zoom;
                  final lat = mapCtrl.camera.center.latitudeInRad;
                  const earthCircumference = 2 * math.pi * 6378137.0;
                  final metersPerPx =
                      (earthCircumference * math.cos(lat)) /
                      (256.0 * math.pow(2.0, zoom));
                  return (_ctrl.value * kIntroRouteEstimatedMeters).clamp(0.0, kCometTailMaxMeters) / metersPerPx;
                }();
                return CustomPaint(
                  painter: _IntroRivalsMapPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    ownedBlock1: _ownedBlock1,
                    ownedBlock2: _ownedBlock2,
                    attackerRoute: _attackerRoute,
                    partialDisputed: _partialDisputed,
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

class _IntroRivalsMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> ownedBlock1;
  final List<Offset> ownedBlock2;
  final List<Offset> attackerRoute;
  final List<Offset> partialDisputed;
  final double tailLengthPx;

  _IntroRivalsMapPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.ownedBlock1,
    required this.ownedBlock2,
    required this.attackerRoute,
    required this.partialDisputed,
    required this.tailLengthPx,
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
      drawComet(canvas, attackerRoute, routeProgress,
          tailLengthPx: tailLengthPx, color: kSea, decayMul: 1.0);
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
      old.inheritedPts != inheritedPts ||
      old.tailLengthPx != tailLengthPx;
}
