import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../theme.dart';

// ── Named duration constants ──────────────────────────────────────────────────
const kIntroFadeDelay = Duration(milliseconds: 400);
const kIntroFadeDuration = Duration(milliseconds: 200);
const kIntroLoopPause = Duration(seconds: 2);

// ── Expand & Unify animation constants ───────────────────────────────────────
/// Total E&U animation window — longest of the three layers.
const kExpandUnifyDuration = Duration(milliseconds: 400);

/// Layer 1 (border sweep) sub-window fraction of the full 400 ms window.
/// 0.625 = 250 ms of 400 ms.
const double kEUBorderSweepFraction = 0.625;

/// Layer 2 (perimeter pulse) sub-window — full 400 ms.
const double kEUPulseFraction = 1.0;

/// Vertex coincidence tolerance for shared-edge detection (screen pixels).
const double kEUSharedVertexEpsPx = 1.5;

// ── Runner color used across multiple slides ──────────────────────────────────
const Color kRunnerCPink = Color(0xFFFF3B7A);

// ── Comet tail constants ──────────────────────────────────────────────────────
const double kCometTailTimeWindowSec = 600.0;
const double kCometTailMaxMeters = 1500.0;
const double kIntroRouteEstimatedMeters = 500.0;
const int kCometBandCount = 16;

// ── Loop helper ───────────────────────────────────────────────────────────────
void loopController(
  AnimationController ctrl, {
  Duration pause = kIntroLoopPause,
  required bool Function() mounted,
}) {
  ctrl.reset();
  ctrl.forward().then((_) {
    if (!mounted()) return;
    Future.delayed(pause, () {
      if (!mounted()) return;
      loopController(ctrl, pause: pause, mounted: mounted);
    });
  });
}

// ── Map controller lifecycle mixin ────────────────────────────────────────────
mixin IntroMapMixin<T extends StatefulWidget> on State<T> {
  final mapCtrl = MapController();
  bool mapReady = false;

  void markMapReady(VoidCallback computePoints) {
    setState(() {
      computePoints();
      mapReady = true;
    });
  }

  void disposeMapCtrl() => mapCtrl.dispose();
}

String formatSqm(int sqm) =>
    sqm >= 1000 ? '${(sqm / 1000).toStringAsFixed(1)}k' : sqm.toString();

TileLayer cartoDbDarkNoLabels(BuildContext context) => TileLayer(
      urlTemplate: 'assets/intro_tiles/{z}/{x}/{y}.png',
      tileProvider: AssetTileProvider(),
      retinaMode: false,
      userAgentPackageName: 'app.runwar.runwar_app',
      keepBuffer: 4,
      panBuffer: 2,
      tileDisplay: const TileDisplay.instantaneous(),
    );

Widget buildIntroMap({
  required BuildContext context,
  required MapController mapController,
  required LatLng center,
  required double zoom,
  required VoidCallback onReady,
  double? maxZoom,
}) =>
    LayoutBuilder(
      builder: (ctx, constraints) {
        // Guard against degenerate constraints (e.g. in widget tests or during
        // early layout). FlutterMap throws Infinity/NaN toInt or isFinite
        // assertions when constraints or MediaQuery size are not ready.
        final mqs = MediaQuery.maybeSizeOf(ctx);
        if (constraints.maxWidth <= 0 ||
            constraints.maxHeight <= 0 ||
            !constraints.maxWidth.isFinite ||
            !constraints.maxHeight.isFinite ||
            mqs == null ||
            mqs == Size.zero ||
            !mqs.width.isFinite ||
            !mqs.height.isFinite) {
          return const SizedBox.expand();
        }
        return FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
            onMapReady: onReady,
          ),
          children: [
            if (maxZoom != null)
              TileLayer(
                urlTemplate: 'assets/intro_tiles/{z}/{x}/{y}.png',
                tileProvider: AssetTileProvider(),
                maxZoom: maxZoom,
                retinaMode: false,
                userAgentPackageName: 'app.runwar.runwar_app',
                keepBuffer: 4,
                panBuffer: 2,
                tileDisplay: const TileDisplay.instantaneous(),
              )
            else
              cartoDbDarkNoLabels(ctx),
          ],
        );
      },
    );

mixin IntroPainterHelpers {
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

  void drawTrace(Canvas canvas, List<Offset> pts, double routeT, {double alphaMul = 1.0}) {
    if (pts.isEmpty || alphaMul <= 0) return;
    final segs = pts.length - 1;
    final totalLen = routeT.clamp(0.0, 1.0) * segs;
    final routeP = Paint()
      ..color = accent.withValues(alpha: 0.7 * alphaMul)
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

  void drawTraceColor(Canvas canvas, List<Offset> pts, double routeT, Color color, {double alphaMul = 1.0}) {
    if (pts.isEmpty || alphaMul <= 0) return;
    final segs = pts.length - 1;
    final totalLen = routeT.clamp(0.0, 1.0) * segs;
    final routeP = Paint()
      ..color = color.withValues(alpha: 0.7 * alphaMul)
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

  /// Renders a comet tail: the last [tailLengthPx] screen-pixels of the route
  /// [pts] up to [routeT], with a linear alpha gradient — 0 at the tail end
  /// rising to [headAlpha]*[decayMul] at the runner's current position.
  ///
  /// [tailLengthPx] — screen pixels of the visible tail at current zoom.
  ///   Intro proxy: (_ctrl.value * kIntroRouteEstimatedMeters).clamp(0, kCometTailMaxMeters) / metersPerPixel.
  ///   Production: gpsDistanceLast10MinMeters / metersPerPixel.
  /// [decayMul] — 0..1 envelope for idle-decay (1.0 = runner active).
  void drawComet(
    Canvas canvas,
    List<Offset> pts,
    double routeT, {
    required double tailLengthPx,
    required Color color,
    double headAlpha = 0.85,
    double decayMul = 1.0,
  }) {
    if (pts.isEmpty || decayMul <= 0 || tailLengthPx <= 0) return;
    final segs = pts.length - 1;
    if (segs <= 0) return;
    final totalRouteT = routeT.clamp(0.0, 1.0);
    final totalLen = totalRouteT * segs;

    // Build the partial route path up to routeT.
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < segs; i++) {
      if (totalLen > i) {
        final segT = (totalLen - i).clamp(0.0, 1.0);
        path.lineTo(
          Offset.lerp(pts[i], pts[i + 1], segT)!.dx,
          Offset.lerp(pts[i], pts[i + 1], segT)!.dy,
        );
      }
    }

    // Draw gradient tail using path metrics.
    for (final metric in path.computeMetrics()) {
      final fullLen = metric.length;
      if (fullLen <= 0) continue;
      final tailStart = math.max(0.0, fullLen - tailLengthPx);
      final visibleLen = fullLen - tailStart;
      if (visibleLen <= 0) continue;
      final bandLen = visibleLen / kCometBandCount;
      for (int i = 0; i < kCometBandCount; i++) {
        final bandStart = tailStart + i * bandLen;
        final bandEnd = bandStart + bandLen;
        final alpha = headAlpha * decayMul * (i + 1) / kCometBandCount;
        canvas.drawPath(
          metric.extractPath(bandStart, bandEnd),
          Paint()
            ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
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
    // For small lists (≤4 pts) ping every vertex so none are skipped.
    // For larger lists sample 3 representative corners to avoid clutter.
    final corners = pts.length <= 4
        ? pts
        : [pts[0], pts[pts.length ~/ 2], pts[pts.length - 2]];
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

  /// Draw a circular level badge at the top-left corner of a polygon.
  /// [polygon] — screen-space vertices of the polygon.
  /// [level] — integer level number to display (shown as numeral inside circle).
  /// [color] — fill color of the circle (typically the owner's accent color).
  /// [radiusScale] — 0.0→1.0 fraction; animate from 0 to full on level-up.
  void drawLevelBadge(
    Canvas canvas,
    List<Offset> polygon,
    int level,
    Color color, {
    double radiusScale = 1.0,
  }) {
    if (polygon.isEmpty || level <= 0 || radiusScale <= 0) return;

    // Top-left corner = min(x) then min(y) among those.
    Offset topLeft = polygon[0];
    for (final pt in polygon) {
      if (pt.dx < topLeft.dx || (pt.dx == topLeft.dx && pt.dy < topLeft.dy)) {
        topLeft = pt;
      }
    }
    final center = topLeft + const Offset(16, 16); // inset 16px from corner
    final radius = 14.0 * radiusScale;

    // Filled circle.
    canvas.drawCircle(center, radius, Paint()..color = color);
    // White stroke.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Level numeral — white Bebas Neue centred in circle.
    final tp = TextPainter(
      text: TextSpan(
        text: '$level',
        style: GoogleFonts.bebasNeue(
          fontSize: 14,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
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

  /// Draw a list of inherited (already-owned) zone polygons as muted fills.
  /// Uses kAccent at alpha 0.55 so they read as "prior territory" without
  /// competing with the current slide's active animation.
  void drawInheritedBlocks(Canvas canvas, List<List<Offset>> blocks) {
    for (final block in blocks) {
      drawFillColor(canvas, block, kAccent, 0.28);
    }
  }

  /// Draw a regular hexagon path centered at [center] with given [radius]
  /// (top vertex up), stroked or filled per [paint]. Shared shield glyph
  /// used by defense / superpower animations.
  void drawHexGlyph(Canvas canvas, Offset center, double radius, Paint paint) {
    if (radius <= 0) return;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  // ── Expand & Unify convenience wrappers ──────────────────────────────────

  /// Returns lists of consecutive shared-vertex runs between [priorBlocks]
  /// and [newBlock]. Delegates to the top-level [sharedEdgePolylines].
  List<List<Offset>> sharedEdges({
    required List<List<Offset>> priorBlocks,
    required List<Offset> newBlock,
    double epsPx = kEUSharedVertexEpsPx,
  }) =>
      sharedEdgePolylines(
        priorBlocks: priorBlocks,
        newBlock: newBlock,
        epsPx: epsPx,
      );

  /// Smooth opacity tween during an E&U window. Delegates to
  /// the top-level [unionOpacityHandoff].
  double opacityHandoff({
    required double priorOpacity,
    required double newOpacity,
    required double windowT,
  }) =>
      unionOpacityHandoff(
        priorOpacity: priorOpacity,
        newOpacity: newOpacity,
        windowT: windowT,
      );

  /// Expand & Unify transient overlay. Delegates to the top-level
  /// [drawExpandUnify].
  void expandUnify(
    Canvas canvas, {
    required Path priorUnion,
    required List<Offset> newBlock,
    required Path unionAfter,
    List<List<Offset>>? sharedEdges,
    required double t,
    required Color color,
  }) =>
      drawExpandUnify(
        canvas,
        priorUnion: priorUnion,
        newBlock: newBlock,
        unionAfter: unionAfter,
        sharedEdges: sharedEdges,
        t: t,
        color: color,
      );
}

// ---------------------------------------------------------------------------
// Expand & Unify top-level helpers — callable from any CustomPainter or
// class that does NOT mix in IntroPainterHelpers (e.g. production overlay).
// ---------------------------------------------------------------------------

/// Returns lists of consecutive shared-vertex runs between [priorBlocks] and
/// [newBlock]. Uses pixel-space vertex coincidence with [epsPx] tolerance.
///
/// Each entry in the returned list is one contiguous polyline of shared
/// vertices. Returns an empty list if no shared boundary is found.
///
/// Call ONCE at the block-close gate frame and cache; never call per-frame.
List<List<Offset>> sharedEdgePolylines({
  required List<List<Offset>> priorBlocks,
  required List<Offset> newBlock,
  double epsPx = kEUSharedVertexEpsPx,
}) {
  if (priorBlocks.isEmpty || newBlock.isEmpty) return [];

  // Flatten all prior-block vertices for fast proximity checks.
  final allPrior = <Offset>[];
  for (final block in priorBlocks) {
    allPrior.addAll(block);
  }

  bool isNearPrior(Offset v) {
    for (final p in allPrior) {
      if ((v - p).distance < epsPx) return true;
    }
    return false;
  }

  // Walk newBlock vertices (wrap-around included via modulo).
  final n = newBlock.length;
  final matched = List<bool>.generate(n, (i) => isNearPrior(newBlock[i]));

  // Group consecutive matched vertices into polyline runs.
  final result = <List<Offset>>[];
  var i = 0;
  while (i < n) {
    if (matched[i]) {
      final run = <Offset>[newBlock[i]];
      var j = (i + 1) % n;
      while (j != i && matched[j]) {
        run.add(newBlock[j]);
        j = (j + 1) % n;
      }
      // A valid shared edge needs at least 2 consecutive matched vertices.
      if (run.length >= 2) result.add(run);
      // Advance past the whole run (guard against infinite loop on full wrap).
      final runLen = run.length;
      i += runLen;
    } else {
      i++;
    }
  }
  return result;
}

/// Smooth opacity tween during an E&U window, replacing `math.max` flicker.
///
/// [windowT] is 0..1 within the ~400 ms E&U window.
/// Pass [windowT] = -1 if the call is outside the window; the function then
/// returns `math.max(priorOpacity, newOpacity)` (existing behavior).
///
/// Inside the window the formula is:
///   `priorOpacity + (newOpacity - priorOpacity) * easeInOutCubic(windowT)`
/// where `easeInOutCubic(t) = t < 0.5 ? 4t³ : 1 - (-2t+2)³/2`.
double unionOpacityHandoff({
  required double priorOpacity,
  required double newOpacity,
  required double windowT,
}) {
  if (windowT < 0) return math.max(priorOpacity, newOpacity);

  final t = windowT.clamp(0.0, 1.0);
  final curved = t < 0.5
      ? 4.0 * t * t * t
      : 1.0 - math.pow(-2.0 * t + 2.0, 3) / 2.0;
  return priorOpacity + (newOpacity - priorOpacity) * curved;
}

/// Expand & Unify transient overlay — draws up to two layers on [canvas] over
/// a ~400 ms window. Call AFTER the union fill+stroke so layers are additive.
///
/// **Layer 1** (border sweep) — animated moving sub-segment along each polyline
/// in [sharedEdges]. Only fires when [sharedEdges] is non-null and non-empty
/// and while `t < kEUBorderSweepFraction` (first 250 ms of 400 ms).
///
/// **Layer 2** (perimeter ring) — strokes [unionAfter] across the full window
/// `t ∈ [0, 1]`. Always fires for any block-close (isolated or adjacent).
///
/// [t] is 0..1 within the E&U window (0 = start, 1 = end at ~400 ms).
/// [color] — base color; alpha is modulated internally per layer.
void drawExpandUnify(
  Canvas canvas, {
  required Path priorUnion,
  required List<Offset> newBlock,
  required Path unionAfter,
  List<List<Offset>>? sharedEdges,
  required double t,
  required Color color,
}) {
  final tc = t.clamp(0.0, 1.0);

  // Early-out: nothing to draw at t == 1 (window fully elapsed).
  if (tc >= 1.0) return;
  // Early-out: no-op when color is fully transparent.
  if (color.a == 0) return;

  // ── Layer 1 — border sweep (shared edges only, first 62.5 % of window) ──
  if (sharedEdges != null && sharedEdges.isNotEmpty) {
    final layerT = (tc / kEUBorderSweepFraction).clamp(0.0, 1.0);
    if (layerT < 1.0) {
      final alpha = 0.9 * (1.0 - layerT * 1.6).clamp(0.0, 1.0);
      final width = 2.5 * (1.0 - layerT * 1.6).clamp(0.0, 1.0);
      if (alpha > 0 && width > 0) {
        final sweepPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = width;

        final headPct = layerT;
        final tailPct = (headPct - 0.30).clamp(0.0, 1.0);

        for (final polyline in sharedEdges) {
          if (polyline.length < 2) continue;
          final edgePath = Path()
            ..moveTo(polyline[0].dx, polyline[0].dy);
          for (var k = 1; k < polyline.length; k++) {
            edgePath.lineTo(polyline[k].dx, polyline[k].dy);
          }
          for (final metric in edgePath.computeMetrics()) {
            final len = metric.length;
            if (len <= 0) continue;
            final headLen = len * headPct;
            final tailLen = len * tailPct;
            if (headLen > tailLen) {
              canvas.drawPath(
                metric.extractPath(tailLen, headLen),
                sweepPaint,
              );
            }
          }
        }
      }
    }
  }

  // ── Layer 2 — perimeter ring (full 400 ms window) ─────────────────────
  final ringAlpha = (0.5 * (1.0 - tc)).clamp(0.0, 1.0);
  final ringWidth = 2.0 - 1.5 * tc;
  if (ringAlpha > 0 && ringWidth > 0) {
    canvas.drawPath(
      unionAfter,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: ringAlpha)
        ..strokeWidth = ringWidth,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared GPS polygon data — referenced by multiple slide painters.
// ---------------------------------------------------------------------------
abstract final class IntroZones {
  // ── Slide 1 blocks (Ruzafa) — from IntroPulseMap ──────────────────────────
  static const kS1Block1 = [
    LatLng(39.462077, -0.375522), // A
    LatLng(39.461576, -0.376751), // B
    LatLng(39.462155, -0.377171), // C
    LatLng(39.462671, -0.375937), // D
  ];

  static const kS1Block2 = [
    LatLng(39.462077, -0.375522), // A
    LatLng(39.461568, -0.375167), // E
    LatLng(39.460440, -0.375966), // F
    LatLng(39.461050, -0.376394), // G
    LatLng(39.461576, -0.376751), // B
  ];

  static const kS1Block3 = [
    LatLng(39.461576, -0.376751), // B
    LatLng(39.460846, -0.378471), // H
    LatLng(39.460335, -0.378112), // I
    LatLng(39.461050, -0.376394), // G
  ];

  static const kS1All = [kS1Block1, kS1Block2, kS1Block3];

  // ── Slide 2 net-new blocks — empty; dispute is over existing territory ──────
  static const kS2OwnedBlock1 = <LatLng>[];
  static const kS2OwnedBlock2 = <LatLng>[];

  /// Slide 2 sees: same territory as slide 1 (no new captures yet — conflict
  /// is over existing orange blocks).
  static const kS2All = [...kS1All];

  // ── Slide 3 net-new blocks — north of kS1All, Carrer de Cuba area ──────────
  // Player has pushed north from Ruzafa into the Cuba/Sueca corridor.
  static const kS3OwnedBlock1 = [
    LatLng(39.4627, -0.3755), // NE corner
    LatLng(39.4622, -0.3762), // SW corner
    LatLng(39.4628, -0.3766), // S corner
    LatLng(39.4633, -0.3759), // E corner
  ];

  static const kS3OwnedBlock2 = [
    LatLng(39.4628, -0.3766),
    LatLng(39.4622, -0.3762),
    LatLng(39.4623, -0.3773),
    LatLng(39.4630, -0.3778),
    LatLng(39.4635, -0.3771),
  ];

  /// Slide 3 sees: all of slides 1+2 + slide 3's own blocks.
  static const kS3All = [
    ...kS2All,
    kS3OwnedBlock1,
    kS3OwnedBlock2,
  ];
}

// ---------------------------------------------------------------------------
// Continuity constants shared by slides 2, 3 and 4 (onboarding-remake).
// Slides 2-4 are three independently-mounted widgets with no shared
// lifecycle, so "continuity" is enforced structurally: all three reference
// these constants directly instead of repeating the literal values, which
// guarantees they can never visually drift apart.
// ---------------------------------------------------------------------------
abstract final class IntroContinuity {
  /// Single source of truth for slides 2, 3, 4's map center/zoom.
  static const kMapCenter = LatLng(39.4650, -0.3756);
  static const double kMapZoom = 16.0;

  /// Slide-2 terminal state == slide-3 Beat-1 (0-1s) opening state.
  /// Both the capture-map painter's held end frame and the defense-map
  /// painter's opening frame resolve to these exact values.
  static const double kBlock1EndFillAlpha = 0.42; // fill settles ~42%
  static const double kBlock1EndBorderWidth = 3.0; // solid ~3px border

  /// Slide-1 terminal state carried into slide-2's opening beat.
  /// The pulse map (slide 1) holds its captured union — every kS1All block —
  /// at this fill alpha once the runner finishes. Slide 2 opens by painting
  /// that same union directly (never replaying slide 1's controller), so the
  /// player's turf persists across the cut instead of the map resetting empty.
  static const double kS1CapturedFillAlpha = 0.28; // union hold alpha

  /// FORTIFY's (slide 2) final-lap ARMOR-3 terminal state, carried into
  /// SHIELD's (slide 4) Beat-1 opening frame. Derived from
  /// intro_fortify_map.dart's own final-lap math (`lap == 2`):
  /// fillOpacity = 0.30 + 2 * 0.18 = 0.66, borderWidth = _kArmorBorderWidths[2].
  /// Both intro_fortify_map.dart's own final lap and intro_defense_map.dart's
  /// held opening beat reference these constants directly (never re-derive
  /// the numbers independently), so the two frames are structurally
  /// guaranteed to match rather than merely visually approximate.
  static const double kFortifyEndFillAlpha = 0.66; // ARMOR 3 fill
  static const double kFortifyEndBorderWidth = 5.0; // ARMOR 3 border (gold)

  /// Map screen's one-shot claim capture flash (not an intro-slide
  /// constant - shared here per this file's existing role as the single
  /// source of truth for animation magic numbers). Peak fill alpha reuses
  /// [kBlock1EndFillAlpha] directly rather than a duplicate constant.
  static const Duration kCaptureFlashDuration = Duration(milliseconds: 600);
  static const double kCaptureFlashRingMaxRadius = 50.0; // px, screen space
  static const double kCaptureFlashRingPeakAlpha = 0.6; // ring stroke alpha
}
