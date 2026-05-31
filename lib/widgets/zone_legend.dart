// lib/widgets/zone_legend.dart
//
// Compact legend showing the 5-tier zone level color map.
// Design.md §4 — bottom-right anchor in MapScreen Stack.

import 'package:flutter/material.dart';

const List<({String label, Color color})> _kTiers = [
  (label: 'L1-3', color: Color(0xFF4CAF50)),   // green
  (label: 'L4-6', color: Color(0xFFCDDC39)),   // lime
  (label: 'L7-9', color: Color(0xFFFFC107)),   // amber
  (label: 'L10-12', color: Color(0xFFFF9800)), // orange
  (label: 'L13-15', color: Color(0xFFF44336)), // red
];

/// Compact card legend placed at bottom-right of the map.
/// Shows 5 color-coded rows: swatch + label.
class ZoneLegend extends StatelessWidget {
  const ZoneLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _kTiers.map((tier) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: tier.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tier.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
