import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

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
    with TickerProviderStateMixin, IntroMapMixin<IntroDefenseMap> {
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

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Stack(
        children: [
          buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: const LatLng(39.4627, -0.3756),
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
                  painter: _IntroDefenseMapPainter(
                    t: _ctrl.value,
                    accent: widget.accent,
                    inheritedPts: _inheritedPts,
                    attackerRoute: _attackerRoute,
                    disputedArea: _disputedArea,
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

class _IntroDefenseMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  @override
  final Color accent;
  final List<List<Offset>> inheritedPts;
  final List<Offset> attackerRoute;
  final List<Offset> disputedArea;
  final double tailLengthPx;

  _IntroDefenseMapPainter({
    required this.t,
    required this.accent,
    required this.inheritedPts,
    required this.attackerRoute,
    required this.disputedArea,
    required this.tailLengthPx,
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
      drawComet(canvas, attackerRoute, routeProgress,
          tailLengthPx: tailLengthPx, color: kSea, decayMul: routeFade);
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
      old.inheritedPts != inheritedPts ||
      old.tailLengthPx != tailLengthPx;
}
