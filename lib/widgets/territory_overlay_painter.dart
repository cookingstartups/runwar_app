import 'package:flutter/material.dart';

import 'intro/intro_helpers.dart';

// ── TerritoryOverlayPainter ───────────────────────────────────────────────────
//
// Lightweight CustomPainter that renders the Expand & Unify transient animation
// on top of the flutter_map PolygonLayer during a territory claim.
//
// Construction is lightweight: all geometry is pre-projected to screen Offsets
// by the caller (MapScreen) so this painter does zero lat/lng math per frame.
//
// Usage: wrap in `CustomPaint(painter: TerritoryOverlayPainter(...),
//   child: const SizedBox.expand())` and place it directly above the map Stack.

class TerritoryOverlayPainter extends CustomPainter with IntroPainterHelpers {
  TerritoryOverlayPainter({
    required this.accent,
    required this.priorUnion,
    required this.newBlock,
    required this.unionAfter,
    required this.sharedEdgesList,
    required this.animT,
  }) : super(repaint: null);

  /// Base accent color — alpha is modulated per layer inside [drawExpandUnify].
  @override
  final Color accent;

  /// Territory path BEFORE the new block was merged (screen-space Paths,
  /// projected by the caller via [MapCamera.latLngToScreenPoint]).
  final Path priorUnion;

  /// Newly-claimed block vertices projected to screen Offsets.
  final List<Offset> newBlock;

  /// Territory path AFTER the merge — stroked as the perimeter ring (layer 2).
  final Path unionAfter;

  /// Pre-computed shared-edge polylines (layer 1).
  /// Pass `null` or empty list to skip the border-sweep layer (isolated claim).
  final List<List<Offset>>? sharedEdgesList;

  /// Animation progress within the E&U window, ∈ [0.0, 1.0].
  final double animT;

  @override
  void paint(Canvas canvas, Size size) {
    drawExpandUnify(
      canvas,
      priorUnion: priorUnion,
      newBlock: newBlock,
      unionAfter: unionAfter,
      sharedEdges: sharedEdgesList,
      t: animT,
      color: accent,
    );
  }

  @override
  bool shouldRepaint(TerritoryOverlayPainter old) =>
      old.animT != animT ||
      old.accent != accent ||
      old.priorUnion != priorUnion ||
      old.unionAfter != unionAfter;
}
