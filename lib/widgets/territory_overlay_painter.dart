import 'package:flutter/material.dart';

import 'intro/intro_helpers.dart';

// ── TerritoryOverlayPainter ───────────────────────────────────────────────────
//
// Full post-close claim animation rendered above the flutter_map PolygonLayer.
// Plays a 1500 ms beat: fill ramp, E&U layers, comet tail, runner glyph,
// ping burst. The painter self-subscribes to [repaint] so no AnimatedBuilder
// wrapper is needed at the call site.
//
// All geometry is pre-projected to screen Offsets by MapScreen so this painter
// does zero lat/lng math per frame.

class TerritoryOverlayPainter extends CustomPainter with IntroPainterHelpers {
  TerritoryOverlayPainter({
    required this.ownerColor,
    required this.priorUnion,
    required this.newBlock,
    required this.unionAfter,
    required this.sharedEdgesList,
    required this.animT,
    required this.routePoints,
    required this.tailLengthPx,
    required this.capturedSqm,
    this.euWindowFraction = 400.0 / 1500.0,
    super.repaint,
  }) : assert(euWindowFraction > 0 && euWindowFraction <= 1.0);

  /// Owning player color — all layers are modulated from this base color.
  /// Must be fully opaque (alpha = 1.0); the painter modulates alpha internally.
  @override
  Color get accent => ownerColor;

  final Color ownerColor;

  /// Territory path BEFORE the new block was merged (screen-space Paths,
  /// projected by the caller via [MapCamera.latLngToScreenPoint]).
  final Path priorUnion;

  /// Newly-claimed block vertices projected to screen Offsets.
  final List<Offset> newBlock;

  /// Territory path AFTER the merge -- stroked as the perimeter ring (layer 2).
  final Path unionAfter;

  /// Pre-computed shared-edge polylines (layer 1 border sweep).
  /// Pass null or empty to skip the border-sweep layer (isolated claim).
  final List<List<Offset>>? sharedEdgesList;

  /// Animation progress within the full 1500 ms window, in [0.0, 1.0].
  final double animT;

  /// Screen-projected GPS trail snapshot (last 60 points of trackBefore).
  final List<Offset> routePoints;

  /// Length in screen pixels of the visible comet tail (= 100 m / metersPerPixel).
  final double tailLengthPx;

  /// Captured area in square meters -- passed through for symmetry; HUD chip
  /// reads the matching state field from MapScreen, not from this painter.
  final int capturedSqm;

  /// Fraction of the 1500 ms window used by E&U sub-layers.
  /// Default = 400/1500 so E&U completes at animT = 0.267 (400 ms).
  /// Override in widget tests to pump a shorter controller.
  final double euWindowFraction;

  @override
  void paint(Canvas canvas, Size size) {
    // Remap animT into the E&U sub-window so E&U layers complete at 400 ms.
    final euT = (animT / euWindowFraction).clamp(0.0, 1.0);
    // Fill ramp: 0 -> 0.28 over the first 40% of the window (~600 ms).
    final activeOpacity = (animT / 0.4).clamp(0.0, 1.0) * 0.28;

    // 1. Union fill + outer stroke (anchor the territory visually).
    if (activeOpacity > 0) {
      canvas.drawPath(
        unionAfter,
        Paint()
          ..color = ownerColor.withValues(alpha: activeOpacity)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        unionAfter,
        Paint()
          ..color = ownerColor.withValues(
              alpha: (activeOpacity / 0.28).clamp(0.0, 1.0) * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 2. E&U layers (border sweep + perimeter ring) -- additive over fill.
    drawExpandUnify(
      canvas,
      priorUnion: priorUnion,
      newBlock: newBlock,
      unionAfter: unionAfter,
      sharedEdges: sharedEdgesList,
      t: euT,
      color: ownerColor,
    );

    // 3. Comet tail -- decays from animT = 0.70 to fully gone at animT = 1.0.
    if (routePoints.isNotEmpty) {
      final decayMul = animT < 0.7
          ? 1.0
          : (1.0 - (animT - 0.7) / 0.3).clamp(0.0, 1.0);
      drawComet(
        canvas,
        routePoints,
        1.0,
        tailLengthPx: tailLengthPx,
        color: ownerColor,
        decayMul: decayMul,
      );
    }

    // 4. Runner glyph (animT < 0.55) or exit curve (animT in [0.55, 0.85]).
    if (routePoints.length >= 2) {
      if (animT < 0.55) {
        drawRunner(canvas, routePoints, 1.0);
      } else if (animT < 0.85) {
        final contT = ((animT - 0.55) / 0.30).clamp(0.0, 1.0);
        final lastPt = routePoints.last;
        final prevPt = routePoints[routePoints.length - 2];
        final dir = lastPt - prevPt;
        final len = dir.distance;
        if (len > 0) {
          final unitDir = dir / len;
          // 90-degree right-hand perpendicular.
          final rightDir = Offset(unitDir.dy, -unitDir.dx);
          final blendDir = Offset.lerp(unitDir, rightDir, contT)!;
          final blendLen = blendDir.distance;
          final blendNorm = blendLen > 0 ? blendDir / blendLen : blendDir;
          final pos =
              lastPt + blendNorm * (Curves.easeIn.transform(contT) * 34);
          final alpha = (1.0 - contT).clamp(0.0, 1.0);
          // Draw runner at the blended exit position with fading alpha.
          canvas.drawCircle(
            pos,
            12,
            Paint()
              ..color = ownerColor.withValues(alpha: 0.25 * alpha)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
          );
          canvas.drawCircle(
            pos,
            4.5,
            Paint()..color = ownerColor.withValues(alpha: alpha),
          );
          canvas.drawCircle(
            pos,
            1.8,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.8 * alpha),
          );
        }
      }
    }

    // 5. Ping burst -- drawn last so rings sit visually on top.
    if (animT >= 0.40 && animT < 0.70) {
      final pingT = ((animT - 0.40) / 0.30).clamp(0.0, 1.0);
      drawPings(canvas, newBlock, pingT);
    }
  }

  @override
  bool shouldRepaint(TerritoryOverlayPainter old) =>
      old.animT != animT ||
      old.ownerColor != ownerColor ||
      old.priorUnion != priorUnion ||
      old.unionAfter != unionAfter ||
      old.routePoints != routePoints ||
      old.tailLengthPx != tailLengthPx ||
      old.capturedSqm != capturedSqm ||
      old.euWindowFraction != euWindowFraction;
}
