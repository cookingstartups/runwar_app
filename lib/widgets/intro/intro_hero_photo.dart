// lib/widgets/intro/intro_hero_photo.dart
//
// IntroHeroPhoto — slide 9 ("Real streets. Real rivals."). Operator-locked
// D2 (Option A): a single hyper-real hero photo animated with a Ken Burns
// effect (scale 1.00 -> 1.09, 2-3% diagonal drift, one warm light-sweep pass
// per cycle). Replaces the retired abstract 3-dot race painter
// (IntroPhysicalEventsMap). No map, no GPS, no new package dependency.
//
// Ken Burns architecture (see design.md): a single forward-only
// AnimationController..repeat() (rejecting the ping-pong "mirror on the way
// back" controller variant) drives a triangular value profile of
// _ctrl.value inside AnimatedBuilder. Scale/drift use the mirrored triangle
// (0->1->0) so the loop's start/end values are identical and the repeat()
// restart is invisible (no jump-cut). The light sweep uses the raw
// (non-mirrored) value so it fires exactly once per pass. Direction is
// never detected via a status-change callback anywhere in this file.

import 'package:flutter/material.dart';

const String kHeroPhotoAsset = 'assets/hero_photos/game_gets_real.jpg';

class IntroHeroPhoto extends StatefulWidget {
  const IntroHeroPhoto({super.key});

  @override
  State<IntroHeroPhoto> createState() => _IntroHeroPhotoState();
}

class _IntroHeroPhotoState extends State<IntroHeroPhoto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final v = _ctrl.value;
        // Mirrored 0->1->0 triangle: start (0.0) and end (1.0 loop wrap ==
        // 0.0 again) share the same value, so scale/drift have no seam.
        final tri = v < 0.5 ? v * 2 : (1 - v) * 2;
        final eased = Curves.easeInOut.transform(tri);

        final scale = 1.00 + 0.09 * eased;
        return ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final driftPx = 0.025 * size.shortestSide * eased;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Transform.translate(
                    offset: Offset(-driftPx, -driftPx),
                    child: Transform.scale(
                      scale: scale,
                      child: Image.asset(
                        kHeroPhotoAsset,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // Warm light sweep — a single diagonal gradient pass over
                  // the full 0->1 raw value (not the mirrored triangle), so
                  // it fires exactly once per 8.5s cycle.
                  IgnorePointer(
                    child: _LightSweep(progress: Curves.easeInOut.transform(v)),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Single warm diagonal light-sweep overlay. [progress] runs 0->1 once per
/// Ken Burns cycle.
class _LightSweep extends StatelessWidget {
  const _LightSweep({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    // The sweep band travels diagonally from top-left to bottom-right,
    // fading in/out so it reads as one warm pass, not a hard-edged wipe.
    final center = Alignment(
      -1.5 + progress * 3.0,
      -1.5 + progress * 3.0,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: center,
          radius: 0.9,
          colors: [
            const Color(0xFFFFD08A).withValues(alpha: 0.16),
            const Color(0xFFFFD08A).withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}
