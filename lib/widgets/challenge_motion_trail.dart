// lib/widgets/challenge_motion_trail.dart
// Phase 3 trust layer — animated motion feedback ring for verification challenge.
//
// Shows a pulsing ring + run icon whose color shifts from blue (idle) to orange
// (active) based on [intensity] (0.0–1.0). The pulse speed is fixed; the caller
// controls color via intensity to convey motion strength.

import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated ring that pulses continuously during an identity verification
/// challenge. The ring color interpolates from calm blue to [kAccent] orange
/// as [intensity] increases from 0.0 to 1.0.
class ChallengeMotionTrail extends StatefulWidget {
  const ChallengeMotionTrail({super.key, this.intensity = 0.0});

  /// Motion intensity in [0.0, 1.0].
  /// 0.0 = calm (blue); 1.0 = peak (orange).
  final double intensity;

  @override
  State<ChallengeMotionTrail> createState() => _ChallengeMotionTrailState();
}

class _ChallengeMotionTrailState extends State<ChallengeMotionTrail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  static const _idleColor = Color(0xFF448AFF);   // blue
  static const _peakColor = kAccent;              // orange — Valencia accent

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
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
    final ringColor =
        Color.lerp(_idleColor, _peakColor, widget.intensity.clamp(0.0, 1.0)) ??
            _idleColor;

    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ringColor.withValues(alpha: 0.08),
          border: Border.all(color: ringColor, width: 3),
        ),
        child: Icon(
          Icons.directions_run,
          size: 56,
          color: ringColor,
          semanticLabel: 'Motion verification active',
        ),
      ),
    );
  }
}
