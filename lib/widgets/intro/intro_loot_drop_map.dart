import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// IntroLootDropMap - Runner B collects a loot chest in Ruzafa (F3b)
//
// Geometry sourced from real OpenStreetMap street data (Nominatim lookup on
// the actual OSM ways, since the Overpass interpreter endpoint was down at
// fetch time - same underlying OSM dataset either way):
//   - Carrer de Buenos Aires (ways 12403610 + 52092204)
//   - Carrer de Cuba (way 52091638)
// Both streets genuinely intersect at LatLng(39.461576, -0.376751) in
// Russafa - this node is also, not by coincidence but by construction, the
// exact corner "B" of IntroZones.kS1Block1 in intro_helpers.dart, and the
// route's own eastern waypoint LatLng(39.462077, -0.375522) matches corner
// "A" of that same block - i.e. this slide's geometry traces two real edges
// of the neighbourhood block already established by the rest of onboarding.
//
// Map centre: LatLng(39.4598, -0.3768) - zoom 16. Shifted south of the real
// intersection so the chest/routes render in the upper ~35-45% of the
// screen (this slide uses visualTopTextBottom; the text panel and bottom
// gradient dissolve occupy the lower portion).
// Chest:      LatLng(39.461576, -0.376751) - Carrer de Cuba × Carrer de
//             Buenos Aires, inside the viewport at the above centre/zoom.
//
// Runner A (kAccent orange)  - straight west→east along Carrer de Buenos
//                               Aires; passes through the intersection node
//                               but does NOT react to the chest.
// Runner B (kSea blue)       - travels N→S along Carrer de Cuba, passing
//                               directly through the same intersection node
//                               (the chest) at t=0.45 - no artificial branch
//                               needed since the real streets cross there.
//                               Single spliced _kRouteBFull list (ADN-4).
// ---------------------------------------------------------------------------

class IntroLootDropMap extends StatefulWidget {
  const IntroLootDropMap({super.key});

  @override
  State<IntroLootDropMap> createState() => _IntroLootDropMapState();
}

class _IntroLootDropMapState extends State<IntroLootDropMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroLootDropMap> {
  // ── Fixed coordinates ──────────────────────────────────────────────────────
  // Centre shifted south of the real intersection so the action reads in the
  // upper portion of the screen (visualTopTextBottom layout - see file header).
  static const _kCentre = LatLng(39.4598, -0.3768);

  // Chest location: real intersection of Carrer de Cuba × Carrer de Buenos
  // Aires (OSM way 52091638 × ways 12403610/52092204). Same node as
  // IntroZones.kS1Block1 corner "B" in intro_helpers.dart.
  static const _kDropCoord = LatLng(39.461576, -0.376751);

  // Runner A (kAccent orange) - west→east along the real Carrer de Buenos
  // Aires alignment. Passes through the Cuba intersection (_kDropCoord) but
  // does NOT react to the chest - collection is driven only by Runner B's
  // timeline, so both routes may legitimately cross the same real node.
  static const _kRouteA = [
    LatLng(39.4577, -0.3860),   // 0: off-screen west start (~700 m beyond street end)
    LatLng(39.460846, -0.378471), // 1: Carrer de Buenos Aires - western real waypoint
    LatLng(39.460901, -0.378366), // 2: Buenos Aires continuing east
    LatLng(39.461554, -0.376799), // 3: Buenos Aires approaching the Cuba intersection
    LatLng(39.461576, -0.376751), // 4: Cuba × Buenos Aires intersection (= _kDropCoord)
    LatLng(39.462077, -0.375522), // 5: Buenos Aires continuing east (= kS1Block1 corner A)
    LatLng(39.4652, -0.3680),   // 6: off-screen east exit (~700 m beyond street end)
  ];

  // Runner B (kSea blue) - single spliced route (ADN-4), real Carrer de Cuba
  // alignment (OSM way 52091638), heading N→S and passing directly through
  // the Buenos Aires intersection (the chest) - no artificial detour needed
  // since the real streets genuinely cross at that node.
  //
  // Timing with arrivalB = 0.85, startT = 0.05, 13 waypoints (indices 0-12):
  //   progress(t) = (t - 0.05) / (0.85 - 0.05) = (t - 0.05) / 0.80
  //   waypoint index = progress * 12
  //   t=0.45 → progress=0.5 → wpt=6.0 (exactly _kDropCoord) ✓
  static const _kRouteBFull = [
    LatLng(39.4700, -0.382760),   //  0: off-screen north start (~700 m beyond street end)
    LatLng(39.463031, -0.377807), //  1: Carrer de Cuba - northern real waypoint
    LatLng(39.462994, -0.377764), //  2: Cuba continuing south
    LatLng(39.462925, -0.377711), //  3: Cuba continuing south
    LatLng(39.462206, -0.377203), //  4: Cuba continuing south
    LatLng(39.462155, -0.377171), //  5: Cuba approaching the Buenos Aires intersection
    LatLng(39.461576, -0.376751), //  6: _kDropCoord - chest collected at t≈0.45
    LatLng(39.461123, -0.376444), //  7: Cuba continuing south, past the intersection
    LatLng(39.461100, -0.376426), //  8: Cuba continuing south
    LatLng(39.461050, -0.376394), //  9: Cuba continuing south
    LatLng(39.460947, -0.376322), // 10: Cuba continuing south
    LatLng(39.460440, -0.375966), // 11: Carrer de Cuba - southern real waypoint
    LatLng(39.4500, -0.368545),   // 12: off-screen south exit (~700 m beyond street end)
  ];

  // ── State ──────────────────────────────────────────────────────────────────
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  List<Offset> _routeA = [];
  List<Offset> _routeBFull = [];
  Offset _dropPt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
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

  void _updatePoints() {
    final cam = mapCtrl.camera;
    Offset toScreen(LatLng ll) {
      final p = cam.latLngToScreenPoint(ll);
      return Offset(p.x.toDouble(), p.y.toDouble());
    }
    markMapReady(() {
      _routeA = _kRouteA.map(toScreen).toList();
      _routeBFull = _kRouteBFull.map(toScreen).toList();
      _dropPt = toScreen(_kDropCoord);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Stack(
        children: [
          // Tile: cartoDbDarkNoLabels (via buildIntroMap default)
          buildIntroMap(
            context: context,
            mapController: mapCtrl,
            center: _kCentre,
            zoom: 16.0,
            onReady: _updatePoints,
          ),
          if (mapReady)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  final zoom = mapCtrl.camera.zoom;
                  final lat = mapCtrl.camera.center.latitudeInRad;
                  const earthCircumference = 2 * math.pi * 6378137.0;
                  final metersPerPx = (earthCircumference * math.cos(lat)) /
                      (256.0 * math.pow(2.0, zoom));
                  final tailPx =
                      (_ctrl.value * kIntroRouteEstimatedMeters)
                              .clamp(0.0, kCometTailMaxMeters) /
                          metersPerPx;
                  return CustomPaint(
                    painter: _IntroLootDropMapPainter(
                      t: _ctrl.value,
                      dropPt: _dropPt,
                      routeA: _routeA,
                      routeBFull: _routeBFull,
                      tailLengthPx: tailPx,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _IntroLootDropMapPainter extends CustomPainter with IntroPainterHelpers {
  final double t;
  final Offset dropPt;
  final List<Offset> routeA;
  final List<Offset> routeBFull;
  final double tailLengthPx;

  _IntroLootDropMapPainter({
    required this.t,
    required this.dropPt,
    required this.routeA,
    required this.routeBFull,
    required this.tailLengthPx,
  });

  // IntroPainterHelpers requires a Color get accent - use kAccent as default.
  @override
  Color get accent => kAccent;

  // ── Timeline constants ─────────────────────────────────────────────────────
  // t 0.00–0.30  : start-position pulses for both runners
  // t 0.05–0.85  : runners move along their routes
  //   Runner A: straight west→east, arrival=0.85 (passes through, exits)
  //   Runner B: N→S with detour; branch at t≈0.30, chest at t=0.45, rejoins t=0.70
  // t 0.45       : chest collection - 3-ring pulse, chest fade begins
  // t 0.55       : chest fully faded (alpha=0)
  // t 0.80–1.00  : _globalFade fade-out
  static const double _arrivalA = 0.85;
  static const double _arrivalB = 0.85;
  // Chest collection timing
  static const double _collectT = 0.45;
  static const double _chestFadeEnd = 0.55;
  // Branch start timing (used as comment reference for route design)
  static const double _branchT = 0.30;
  // Global fade
  static const double _fadeStart = 0.80;

  // ── Helpers ────────────────────────────────────────────────────────────────

  double _globalFade() {
    if (t < _fadeStart) return 1.0;
    return (1.0 - (t - _fadeStart) / (1.0 - _fadeStart)).clamp(0.0, 1.0);
  }

  double _runnerProgress(double arrivalT) {
    if (t >= arrivalT) return 1.0;
    const startT = 0.05;
    if (t < startT) return 0.0;
    return ((t - startT) / (arrivalT - startT)).clamp(0.0, 1.0);
  }

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

  void _drawStartPulse(Canvas canvas, Offset pos, Color color) {
    if (t >= _branchT) return;
    final pulseT = (t / _branchT).clamp(0.0, 1.0);
    final radius = pulseT * 22;
    canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = color.withValues(alpha: (1.0 - pulseT) * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  // ── Chest alpha lifecycle (AC-F3b-5) ──────────────────────────────────────
  // Returns full alpha before collection; decays 1.0→0.0 from t=0.45 to t=0.55.
  // At loop reset (t=0): (0-0.45)/0.10 = negative → clamped to 0 → 1-0 = 1.0 ✓
  double _chestAlpha() {
    if (t < _collectT) return _globalFade();
    final decay =
        1.0 - ((t - _collectT) / (_chestFadeEnd - _collectT)).clamp(0.0, 1.0);
    return decay * _globalFade();
  }

  // ── Treasure chest vector glyph (AC-F3b-4) ────────────────────────────────
  // Box: 16×11 px centred rect, stroked kAccent2, strokeWidth 2.0
  // Lid: trapezoid - 24 px wide at base, 12 px wide at top, 7 px tall
  // Hasp: 4×5 px rect centred on lid/box seam
  // PaintingStyle.stroke only - no fill (hollow interior, dark tile shows through)
  void _drawChest(Canvas canvas, Offset centre, double alpha) {
    if (alpha <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = kAccent2.withValues(alpha: alpha);

    // Box
    final boxRect = Rect.fromCenter(center: centre, width: 16, height: 11);
    canvas.drawRect(boxRect, p);

    // Lid - trapezoid
    // Bottom edge of lid coincides with top edge of box: centre.dy - 5.5
    final lidPath = Path()
      ..moveTo(centre.dx - 12, centre.dy - 5.5) // bottom-left (+4 px each side vs 8)
      ..lineTo(centre.dx + 12, centre.dy - 5.5) // bottom-right
      ..lineTo(centre.dx + 6, centre.dy - 12.5) // top-right (narrower by 6 px, 7 px tall)
      ..lineTo(centre.dx - 6, centre.dy - 12.5) // top-left
      ..close();
    canvas.drawPath(lidPath, p);

    // Hasp - 4×5 px rect centred on lid/box seam midpoint
    final haspRect = Rect.fromCenter(
      center: Offset(centre.dx, centre.dy - 5.5),
      width: 4,
      height: 5,
    );
    canvas.drawRect(haspRect, p);
  }

  // ── Chest collection pulse (AC-F3b-5, adapted from _drawBeacon) ───────────
  // 3 concentric kAccent2 rings expand from _dropPt over t ∈ [0.45, 0.53].
  // Ring i fires with delay i × (0.08/3).
  void _drawChestPulse(Canvas canvas, double fade) {
    if (t < _collectT || t > _chestFadeEnd || fade <= 0) return;
    for (int i = 0; i < 3; i++) {
      final delay = i * (0.08 / 3);
      final ringT = ((t - _collectT - delay) / 0.08).clamp(0.0, 1.0);
      if (ringT > 0) {
        canvas.drawCircle(
          dropPt,
          ringT * 40,
          Paint()
            ..color = kAccent2.withValues(alpha: (1.0 - ringT) * 0.55 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // AC-F3b-9: map-not-ready guard - must be first statement
    if (routeA.isEmpty || routeBFull.isEmpty) return;

    final fade = _globalFade();

    // ── 1. Start-position pulses (t=0.00–0.30) ──────────────────────────────
    _drawStartPulse(canvas, routeA.first, kAccent);
    _drawStartPulse(canvas, routeBFull.first, kSea);

    // ── 2. Runner traces (comet tails) ───────────────────────────────────────
    final progressA = _runnerProgress(_arrivalA);
    final progressB = _runnerProgress(_arrivalB);

    drawComet(canvas, routeA, progressA,
        tailLengthPx: tailLengthPx, color: kAccent, decayMul: fade);
    drawComet(canvas, routeBFull, progressB,
        tailLengthPx: tailLengthPx, color: kSea, decayMul: fade);

    // ── 3. Runner dots ───────────────────────────────────────────────────────
    final posA = progressA < 1.0 ? _posOnRoute(routeA, progressA) : routeA.last;
    final posB =
        progressB < 1.0 ? _posOnRoute(routeBFull, progressB) : routeBFull.last;

    _drawRunnerDot(canvas, posA, kAccent, fade);
    _drawRunnerDot(canvas, posB, kSea, fade);

    // ── 4. Treasure chest ────────────────────────────────────────────────────
    _drawChest(canvas, dropPt, _chestAlpha());

    // ── 5. Chest collection pulse (t=0.45–0.55) ─────────────────────────────
    _drawChestPulse(canvas, fade);
  }

  @override
  bool shouldRepaint(_IntroLootDropMapPainter old) =>
      old.t != t ||
      old.tailLengthPx != tailLengthPx ||
      old.dropPt != dropPt ||
      old.routeA != routeA ||
      old.routeBFull != routeBFull;
}
