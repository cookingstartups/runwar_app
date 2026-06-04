import 'package:flutter/material.dart';

import '../services/telemetry_service.dart';
import '../theme.dart';

/// Full-screen celebration modal shown when the player reaches a streak
/// milestone (day 7, 14, 21, or 30).
///
/// Uses [FadeTransition] + [ScaleTransition] for entry animation, matching
/// the pattern in [FirstZoneCelebrationOverlay].
class MilestoneRewardModal extends StatefulWidget {
  const MilestoneRewardModal({
    required this.day,
    required this.creditsAwarded,
    this.powerGranted,
    super.key,
  });

  /// Milestone day — one of 7, 14, 21, 30.
  final int day;

  /// Credits granted by the milestone.
  final int creditsAwarded;

  /// Optional superpower granted (e.g. 'SHIELD', 'RUSH').
  final String? powerGranted;

  @override
  State<MilestoneRewardModal> createState() => _MilestoneRewardModalState();
}

class _MilestoneRewardModalState extends State<MilestoneRewardModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );

    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    // Telemetry — fired once on show.
    TelemetryService.instance.logEvent(
      'milestone_reward_shown',
      props: {'day': widget.day},
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: kBg.withValues(alpha: 0.96),
        child: SafeArea(
          child: ScaleTransition(
            scale: _scale,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  // Animated milestone badge
                  Center(child: _MilestoneBadge(day: widget.day)),
                  const SizedBox(height: 32),
                  // Headline
                  Text(
                    'DAY ${widget.day} MILESTONE',
                    textAlign: TextAlign.center,
                    style: displayStyle(size: 48, color: kAccent),
                  ),
                  const SizedBox(height: 16),
                  // Credits awarded
                  Text(
                    '+${widget.creditsAwarded} CREDITS',
                    textAlign: TextAlign.center,
                    style: displayStyle(size: 36, color: kAccent2),
                  ),
                  // Optional power granted
                  if (widget.powerGranted != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${widget.powerGranted} UNLOCKED',
                      textAlign: TextAlign.center,
                      style: monoStyle(size: 12, color: kFgMuted),
                    ),
                  ],
                  const Spacer(flex: 2),
                  // CTA
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CLAIM REWARD'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated badge showing the milestone day number.
class _MilestoneBadge extends StatefulWidget {
  const _MilestoneBadge({required this.day});

  final int day;

  @override
  State<_MilestoneBadge> createState() => _MilestoneBadgeState();
}

class _MilestoneBadgeState extends State<_MilestoneBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final radius = 56.0 + 8.0 * _pulse.value;
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kAccent.withValues(alpha: 0.12 + 0.10 * _pulse.value),
            border: Border.all(
              color: kAccent2.withValues(alpha: 0.65 + 0.35 * _pulse.value),
              width: 2.5,
            ),
          ),
          child: Center(
            child: Text(
              '${widget.day}',
              style: displayStyle(size: 52, color: kAccent2),
            ),
          ),
        );
      },
    );
  }
}
