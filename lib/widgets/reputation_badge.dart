// lib/widgets/reputation_badge.dart
// Phase 3 trust layer — inline reputation score badge.
//
// Shows a shield icon + numeric score in a colored chip.
// Green ≥ 80, amber 50–79, red < 50.

import 'package:flutter/material.dart';

/// Small inline badge displaying a player's reputation [score] (0–100+).
/// Uses the Valencia design tokens for surface and border; the score band
/// determines the accent color (green / amber / red).
class ReputationBadge extends StatelessWidget {
  const ReputationBadge({super.key, required this.score});

  final int score;

  Color get _bandColor {
    if (score >= 80) return const Color(0xFF4CAF50); // green
    if (score >= 50) return const Color(0xFFFFB703); // amber — kAccent2
    return const Color(0xFFE83300); // red — kDanger
  }

  @override
  Widget build(BuildContext context) {
    final color = _bandColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            '$score',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
