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

// ── Runner color used across multiple slides ──────────────────────────────────
const Color kRunnerCPink = Color(0xFFFF3B7A);

// ── Comet tail constants ──────────────────────────────────────────────────────
const double kCometTailMeters = 100.0;
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
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
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
            keepBuffer: 4,
            panBuffer: 2,
            tileDisplay: const TileDisplay.instantaneous(),
          )
        else
          cartoDbDarkNoLabels(context),
      ],
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
  /// [tailLengthPx] — screen pixels for kCometTailMeters at current zoom.
  ///   Caller computes: kCometTailMeters / mapCtrl.camera.metersPerPixel.
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
