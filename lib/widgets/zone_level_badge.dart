// lib/widgets/zone_level_badge.dart
//
// Fortification ring — on-map indicator for a captured holding's influence
// level (1-15). The colored core reads tier/strength at a glance, the ring
// arc shows progress toward the next tier within the current 3-level band,
// and a crown replaces the arc once the holding reaches the max tier
// (Citadel). The exact numeric level is never shown here — it stays in the
// zone tap-detail sheet, where attack planning needs the precise value.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 5-tier color map:
///   Tier 0 L1-3   → green  0xFF4CAF50 (Outpost)
///   Tier 1 L4-6   → lime   0xFFCDDC39 (Stronghold)
///   Tier 2 L7-9   → amber  0xFFFFC107 (Fortress)
///   Tier 3 L10-12 → orange 0xFFFF9800 (Bastion)
///   Tier 4 L13-15 → red    0xFFF44336 (Citadel)
const List<Color> kTierColors = [
  Color(0xFF4CAF50), // tier 0 — Outpost — green
  Color(0xFFCDDC39), // tier 1 — Stronghold — lime
  Color(0xFFFFC107), // tier 2 — Fortress — amber
  Color(0xFFFF9800), // tier 3 — Bastion — orange
  Color(0xFFF44336), // tier 4 — Citadel — red
];

/// Returns the tier index for [level], clamped 0..4.
/// Formula: ((level.clamp(1,15) - 1) ~/ 3).clamp(0,4)
/// Verified for all boundary values:
///   L1→0, L3→0, L4→1, L6→1, L7→2, L9→2, L10→3, L12→3, L13→4, L15→4
///   L16 clamps to L15 → idx 4 (red).
int tierIndexForLevel(int level) => ((level.clamp(1, 15) - 1) ~/ 3).clamp(0, 4);

/// Position of [level] within its 3-level tier band, 0..2.
int subLevelInTier(int level) => (level.clamp(1, 15) - 1) % 3;

/// Fraction of the current tier band completed by [level], e.g. level 5
/// (Stronghold, L4-6, sub-position 1) → (1+1)/3 ≈ 0.333.
double tierProgressFraction(int level) => (subLevelInTier(level) + 1) / 3.0;

/// True once [level] is in the Citadel tier (L13-15) — the max tier, where
/// no further tier progress is possible and the ring becomes a crown.
bool isMaxTier(int level) => tierIndexForLevel(level) == 4;

/// Fortification ring badge: tier-colored core + progress arc (or crown at
/// Citadel) for a zone's influence level. Renders no numeric text — the
/// exact level lives in the zone tap-detail sheet only.
class ZoneLevelBadge extends StatelessWidget {
  const ZoneLevelBadge({super.key, required this.level, this.size = 28});

  /// Zone influence level. Out-of-range values are clamped to 1..15.
  final int level;

  /// Overall footprint of the badge (square).
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = kTierColors[tierIndexForLevel(level)];
    final maxTier = isMaxTier(level);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: FortificationRingPainter(
          color: color,
          progress: maxTier ? 1.0 : tierProgressFraction(level),
          showCrown: maxTier,
        ),
      ),
    );
  }
}

/// Paints the fortification ring: a faint track, a tier-colored progress
/// arc, a soft tier-colored core fill, and — at the Citadel tier — a white
/// crown glyph in place of the (now-complete) arc.
class FortificationRingPainter extends CustomPainter {
  const FortificationRingPainter({
    required this.color,
    required this.progress,
    required this.showCrown,
  });

  /// Tier color for the ring/core.
  final Color color;

  /// Fraction (0..1) of the ring arc to draw — progress toward next tier.
  final double progress;

  /// True at the Citadel (max) tier — draws a crown instead of the arc.
  final bool showCrown;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 3;
    const strokeWidth = 3.0;

    final trackPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final corePaint = Paint()..color = color.withValues(alpha: 0.22);
    canvas.drawCircle(center, radius * 0.6, corePaint);

    if (showCrown) {
      _paintCrown(canvas, center, radius);
      return;
    }

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arcPaint,
    );
  }

  void _paintCrown(Canvas canvas, Offset center, double radius) {
    final s = radius * 0.55;
    final path = Path()
      ..moveTo(center.dx, center.dy - s)
      ..lineTo(center.dx + s * 0.55, center.dy - s * 0.1)
      ..lineTo(center.dx + s, center.dy - s * 0.35)
      ..lineTo(center.dx + s * 0.7, center.dy + s * 0.45)
      ..lineTo(center.dx - s * 0.7, center.dy + s * 0.45)
      ..lineTo(center.dx - s, center.dy - s * 0.35)
      ..lineTo(center.dx - s * 0.55, center.dy - s * 0.1)
      ..close();
    canvas.drawPath(
        path, Paint()..color = Colors.white.withValues(alpha: 0.95));
  }

  @override
  bool shouldRepaint(covariant FortificationRingPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.showCrown != showCrown;
}
