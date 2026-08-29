import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';
import 'intro_helpers.dart';

// ---------------------------------------------------------------------------
// 2. IntroCaptureMap - a rival claims the block next to the player's
//    fortified turf (slide 3, YOUR TURF).
//
//    Opens in slide 2's terminal state: kS1Block1 sits fortified (fill-only,
//    IntroContinuity.kFortifyEndFillAlpha, kAccent orange) from frame 0 -
//    no reset, no replay of slide 2's own controller. The kS1All orange
//    underlay stays visible throughout, exactly as slide 2 leaves it.
//
//    A kSea rival then enters from off-screen along a right-angle street
//    path OUTSIDE the conquered blocks - never cutting through a block
//    interior - and traces a loop around the ADJACENT kS1Block2 (shares the
//    A-B edge with kS1Block1). The loop closes, a flat kSea fill appears on
//    kS1Block2 (a fresh level-1 claim, weaker than the player's own
//    fortified block), a one-shot capture flash fires, and the scene holds
//    quietly until the loop restarts. No contested-border treatment, no
//    dispute visuals - a clean claim (mockup option A,
//    round-2026-08-29/slide3-rival-round1.html).
//
//    The player's fortified kS1Block1 stays intact throughout - the old
//    self-reclaim sequence and player-accent claim stamp are gone.
// ---------------------------------------------------------------------------
class IntroCaptureMap extends StatefulWidget {
  final Color accent;

  /// Optional map-center override. Defaults to the shared
  /// IntroContinuity.kMapCenter used by slides 3/4. The on-screen slide 3
  /// instance (visualTopTextBottom layout) passes a center shifted south so
  /// the claimed block reads in the top half, clear of the bottom text
  /// panel - other callers (e.g. the pre-warm Offstage instance) keep the
  /// shared default so nothing else on screen shifts.
  final LatLng? center;
  const IntroCaptureMap({required this.accent, this.center, super.key});
  @override
  State<IntroCaptureMap> createState() => _IntroCaptureMapState();
}

class _IntroCaptureMapState extends State<IntroCaptureMap>
    with TickerProviderStateMixin, IntroMapMixin<IntroCaptureMap> {
  late final AnimationController _ctrl;
  late final AnimationController _fadeCtrl;

  /// The player's fortified block, screen-projected. Fill-only, painted
  /// every frame - never resets.
  List<Offset> _block1Pts = [];

  /// The rival's target block, screen-projected (unclosed - fill/centroid
  /// use it directly).
  List<Offset> _block2Pts = [];

  /// kS1All (all 3 held blocks), screen-projected - the persistent
  /// held-territory under-layer, mirroring intro_fortify_map.dart's own
  /// drawInheritedBlocks treatment.
  List<List<Offset>> _underlayBlocks = [];

  /// The rival's full approach + claim route: an off-screen right-angle
  /// street path down to kS1Block2's far vertex (never grazing a block
  /// interior), followed by the block's own perimeter back to that vertex -
  /// the claim loop itself.
  List<Offset> _rivalRoute = [];

  /// Builds [_rivalRoute]: two street waypoints outside the block's
  /// bounding box, then the full [block2] perimeter reordered to start/end
  /// at [entryIdx] (the vertex farthest from the A-B edge shared with
  /// kS1Block1, so the approach never crosses the player's own turf).
  List<Offset> _buildRivalRoute(List<Offset> block2, int entryIdx) {
    if (block2.isEmpty) return [];
    final entry = block2[entryIdx];
    final approach = <Offset>[
      entry + const Offset(160, -220),
      Offset(entry.dx + 160, entry.dy - 60),
      Offset(entry.dx, entry.dy - 60),
      entry,
    ];
    final n = block2.length;
    final loop = <Offset>[];
    for (int i = 0; i < n; i++) {
      loop.add(block2[(entryIdx + i) % n]);
    }
    loop.add(entry);
    return [...approach, ...loop];
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: kIntroFadeDuration);
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5200));
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
      _block1Pts = IntroZones.kS1Block1.map(toScreen).toList();
      _block2Pts = IntroZones.kS1Block2.map(toScreen).toList();
      _underlayBlocks =
          IntroZones.kS1All.map((b) => b.map(toScreen).toList()).toList();
      // Entry vertex index 2 ("F" in kS1Block2's own vertex comments) sits
      // farthest from the A-B edge shared with kS1Block1, so the rival's
      // street approach never grazes the player's own block.
      _rivalRoute = _buildRivalRoute(_block2Pts, 2);
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
            center: widget.center ?? IntroContinuity.kMapCenter,
            zoom: IntroContinuity.kMapZoom,
            onReady: _updatePoints,
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
                  painter: _IntroCaptureMapPainter(
                    t: _ctrl.value,
                    block1Pts: _block1Pts,
                    block2Pts: _block2Pts,
                    rivalRoute: _rivalRoute,
                    underlayBlocks: _underlayBlocks,
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
  final List<Offset> block1Pts;
  final List<Offset> block2Pts;
  final List<Offset> rivalRoute;
  final List<List<Offset>> underlayBlocks;
  final double tailLengthPx;

  // IntroPainterHelpers declares `accent` as an abstract getter for its
  // shared drawFill/drawTrace/drawRunner/drawPings helpers; none of those
  // are used here (every color on this slide is an explicit kAccent/kSea
  // literal per the color-assignment rule), so this simply mirrors the
  // rival's own color rather than driving any choice.
  @override
  Color get accent => kSea;

  _IntroCaptureMapPainter({
    required this.t,
    required this.block1Pts,
    required this.block2Pts,
    required this.rivalRoute,
    required this.underlayBlocks,
    required this.tailLengthPx,
  });

  // Beat timing - ~5.2s cycle. Phase structure mirrors the round-2 mockup's
  // RIVAL INBOUND -> CLAIMING -> quiet-hold sequence (fractions of the
  // cycle only; the mockup's own absolute 8s durations do not carry over):
  //   0.00 - 0.08  held beat - block1 sits fortified, nothing else happens
  //   0.08 - 0.55  RIVAL INBOUND + CLAIMING - the kSea runner traces the
  //                street approach, then the kS1Block2 perimeter
  //   0.55 - 0.64  claim resolves - flat kSea fill ramps in on kS1Block2
  //   0.55 - 0.74  one-shot capture flash at the block centroid
  //   0.64 - 1.00  quiet hold - block2 stays claimed with a faint
  //                breathing glow; no contested-border treatment, no
  //                dispute geometry (mockup option A)
  static const double _kEntryT = 0.08;
  static const double _kLoopCloseT = 0.55;
  static const double _kFillDoneT = 0.64;
  static const double _kFlashEndT = 0.74;

  /// A fresh level-1 rival claim - weaker than the player's own fortified
  /// block (IntroContinuity.kFortifyEndFillAlpha).
  static const double _kRivalClaimAlpha = 0.19;

  Offset _centroid(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    double sx = 0, sy = 0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (block1Pts.isEmpty || block2Pts.isEmpty) return;

    // kS1All held territory - the same static under-layer every
    // fortify/capture-family slide paints (drawInheritedBlocks).
    drawInheritedBlocks(canvas, underlayBlocks);

    // The player's fortified block never resets on this slide - it opens
    // already at slide 2's terminal fill-only state and stays there.
    drawFillColor(
        canvas, block1Pts, kAccent, IntroContinuity.kFortifyEndFillAlpha);

    if (rivalRoute.isEmpty) return;

    if (t < _kLoopCloseT) {
      // RIVAL INBOUND + CLAIMING - a single continuous comet path covers
      // both the street approach and the block-perimeter claim trace.
      if (t >= _kEntryT) {
        final traceProgress =
            ((t - _kEntryT) / (_kLoopCloseT - _kEntryT)).clamp(0.0, 1.0);
        drawComet(canvas, rivalRoute, traceProgress,
            tailLengthPx: tailLengthPx, color: kSea);
        final segs = rivalRoute.length - 1;
        final traveled = traceProgress * segs;
        final segIdx = traveled.floor().clamp(0, segs - 1);
        final segFrac = (traveled - segIdx).clamp(0.0, 1.0);
        final pos = Offset.lerp(
          rivalRoute[segIdx],
          rivalRoute[(segIdx + 1).clamp(0, segs)],
          segFrac,
        )!;
        drawRunnerAt(canvas, pos, kSea);
      }
      return;
    }

    // The claim resolves - flat kSea fill, a fresh level-1 claim.
    final fillRamp =
        ((t - _kLoopCloseT) / (_kFillDoneT - _kLoopCloseT)).clamp(0.0, 1.0);
    drawFillColor(canvas, block2Pts, kSea, _kRivalClaimAlpha * fillRamp);

    // One-shot capture flash, right as the claim resolves.
    final flashT =
        ((t - _kLoopCloseT) / (_kFlashEndT - _kLoopCloseT)).clamp(0.0, 1.0);
    if (flashT < 1.0) {
      canvas.drawCircle(
        _centroid(block2Pts),
        flashT * 50.0,
        Paint()
          ..color = kSea.withValues(alpha: (1.0 - flashT) * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // Quiet hold - a faint breathing glow around the claimed block, no
    // contested-border treatment and no dispute geometry (mockup option A).
    if (t >= _kFillDoneT) {
      final breathe = (math.sin((t - _kFillDoneT) * math.pi * 3) + 1) / 2;
      canvas.drawPath(
        Path()..addPolygon(block2Pts, true),
        Paint()
          ..color = kSea.withValues(alpha: 0.08 + breathe * 0.10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
    }
  }

  @override
  bool shouldRepaint(_IntroCaptureMapPainter old) =>
      old.t != t ||
      old.block1Pts != block1Pts ||
      old.block2Pts != block2Pts ||
      old.rivalRoute != rivalRoute ||
      old.underlayBlocks != underlayBlocks ||
      old.tailLengthPx != tailLengthPx;
}
