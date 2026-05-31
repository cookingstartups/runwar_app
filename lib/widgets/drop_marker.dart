import 'package:flutter/material.dart';

// Drop model is written by @Backend-Developer in
// lib/services/database/drops_repository.dart (design.md §3.2).
// Import path kept relative so resolution fails loudly if Backend hasn't merged.
import '../services/database/drops_repository.dart';

/// Color constants for drop types.
const Color _kCrystalColor = Color(0xFFFF6B00); // kAccent — orange
const Color _kCreditsCacheColor = Color(0xFFFFB703); // kAccent2 — gold
const Color _kPowerCoreColor = Color(0xFF9C27B0); // purple

/// Map marker for an on-map drop pickup.
/// Size: 36×36.
/// Taps call [onTap] with the drop data.
class DropMarker extends StatelessWidget {
  const DropMarker({
    required this.drop,
    required this.onTap,
    super.key,
  });

  final Drop drop;
  final void Function(Drop) onTap;

  /// Resolves background color by drop type string (snake_case from DB).
  static Color _colorFor(String type) => switch (type) {
        'influence_crystal' => _kCrystalColor,
        'credits_cache' => _kCreditsCacheColor,
        'power_core' => _kPowerCoreColor,
        _ => _kCrystalColor,
      };

  /// Resolves the center icon label by drop type.
  static String _iconFor(String type) => switch (type) {
        'influence_crystal' => '⬡',
        'credits_cache' => '₿',
        'power_core' => '⚡',
        _ => '⬡',
      };

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(drop.dropType);
    final icon = _iconFor(drop.dropType);

    return GestureDetector(
      onTap: () => onTap(drop),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing ring using AnimatedContainer
            _PulseRing(color: color),
            // Center filled circle
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                icon,
                style: const TextStyle(fontSize: 13, height: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Continuously pulsing outer ring for a drop marker.
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color});

  final Color color;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.color.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
    );
  }
}
