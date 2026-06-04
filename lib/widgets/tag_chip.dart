import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared tag/category chip used across intro slides.
/// Wrap with [Center] at the call site if centred alignment is needed.
class TagChip extends StatelessWidget {
  final String label;
  final Color color;

  const TagChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(label, style: monoStyle(size: 9, color: color)),
    );
  }
}
