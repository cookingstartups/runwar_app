import 'package:flutter/material.dart';
import '../../theme.dart';

// ---------------------------------------------------------------------------
// IntroPhoneCardOverlay — slide 3's Beat 3 (3-5s) "at home" affordance.
//
// A plain UI overlay — never painted inside the map CustomPainter (R-8) —
// communicating "the player is at home, not running" with a one-tap
// "shield" affordance. Mounted by IntroDefenseMapA as a Positioned direct
// Stack child (protocol rule 7). Visibility is time-windowed (only shown
// during Beat 3), so this StatelessWidget takes the driving controller and
// an opacity function directly and animates itself internally via
// AnimatedBuilder, keeping the call site a single short expression.
// ---------------------------------------------------------------------------
class IntroPhoneCardOverlay extends StatelessWidget {
  final Animation<double> controller;
  final double Function(double) opacityOf;
  const IntroPhoneCardOverlay(
      {required this.controller, required this.opacityOf, super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) =>
          Opacity(opacity: opacityOf(controller.value), child: _card()),
    );
  }

  Widget _card() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: kBg.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kSea.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_iphone, color: kSea, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AT HOME',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    letterSpacing: 1,
                    fontFamily: 'BebasNeue',
                  ),
                ),
                Text(
                  'TAP · SHIELD',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: kSea.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            const Icon(Icons.touch_app, color: kAccent, size: 20),
          ],
        ),
      );
}
