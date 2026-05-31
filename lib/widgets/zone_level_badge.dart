// lib/widgets/zone_level_badge.dart
//
// 24×24 circular badge showing a zone's influence level.
// Design.md §4 — 5-tier color palette (Team Lead brief, supersedes phase spec).

import 'package:flutter/material.dart';

/// 5-tier color map (design.md §4):
///   Tier 0 L1-3  → green  0xFF4CAF50
///   Tier 1 L4-6  → lime   0xFFCDDC39
///   Tier 2 L7-9  → amber  0xFFFFC107
///   Tier 3 L10-12→ orange 0xFFFF9800
///   Tier 4 L13-15→ red    0xFFF44336
const List<Color> _kTierColors = [
  Color(0xFF4CAF50), // tier 0 — green
  Color(0xFFCDDC39), // tier 1 — lime
  Color(0xFFFFC107), // tier 2 — amber
  Color(0xFFFF9800), // tier 3 — orange
  Color(0xFFF44336), // tier 4 — red
];

/// Returns the tier index for [level], clamped 0..4.
/// Formula: ((level.clamp(1,15) - 1) ~/ 3).clamp(0,4)
/// Verified for all boundary values:
///   L1→0, L3→0, L4→1, L6→1, L7→2, L9→2, L10→3, L12→3, L13→4, L15→4
///   L16 clamps to L15 → idx 4 (red).
int _tierIndex(int level) =>
    ((level.clamp(1, 15) - 1) ~/ 3).clamp(0, 4);

/// Circular badge displaying the zone influence level with tier-appropriate color.
/// StatelessWidget — takes an int level; renders a 24×24 circle.
class ZoneLevelBadge extends StatelessWidget {
  const ZoneLevelBadge({super.key, required this.level});

  /// Zone influence level. Out-of-range values are clamped to 1..15.
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = _kTierColors[_tierIndex(level)];
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 4,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$level',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
    );
  }
}
