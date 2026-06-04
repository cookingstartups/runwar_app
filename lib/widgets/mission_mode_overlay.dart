import 'package:flutter/material.dart';

import '../models/mission_step.dart';
import '../theme.dart';

/// Overlay widget composited over MapScreen when in mission mode.
///
/// Renders:
///   - Top banner: instruction text per [MissionStep]
///   - Bottom FAB ring: pulsing animation around the FAB position
///
/// Does NOT intercept taps — the ring is wrapped in IgnorePointer.
/// The banner is interactive so it remains readable but never blocks the map.
class MissionModeOverlay extends StatefulWidget {
  const MissionModeOverlay({
    super.key,
    required this.missionStep,
    this.isRecording = false,
  });

  final MissionStep missionStep;
  final bool isRecording;

  @override
  State<MissionModeOverlay> createState() => _MissionModeOverlayState();
}

class _MissionModeOverlayState extends State<MissionModeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MissionModeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording != oldWidget.isRecording) {
      if (widget.isRecording) {
        _pulse.stop();
      } else {
        _pulse.repeat();
      }
    }
  }

  String get _bannerText {
    if (widget.missionStep == MissionStep.mission1Claim) {
      return widget.isRecording
          ? 'WALK A LOOP. RETURN TO START.'
          : 'TAP THE BUTTON. START WALKING.';
    }
    return 'WALK A LOOP AROUND THE RIVAL ZONE.';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top instruction banner — NOT wrapped in IgnorePointer so users
        // can read it; it has no tap handlers so it passes taps through.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBanner(text: _bannerText),
        ),
        // Pulsing ring around the FAB — IgnorePointer so it never blocks
        // the actual FAB tap target below it.
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: _FabPulseRing(animation: _pulse),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBanner extends StatelessWidget {
  const _TopBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: kBg.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        bottom: false,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: monoStyle(size: 11, color: kAccent),
        ),
      ),
    );
  }
}

class _FabPulseRing extends StatelessWidget {
  const _FabPulseRing({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final radius = 36.0 + 18.0 * animation.value;
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: kAccent.withValues(alpha: 0.6 - 0.5 * animation.value),
              width: 2.0,
            ),
          ),
        );
      },
    );
  }
}
