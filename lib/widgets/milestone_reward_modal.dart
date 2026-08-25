import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/paywall_downsell_screen.dart';
import '../services/telemetry_service.dart';
import '../theme.dart';
import '../utils/runwar_constants.dart';

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
    this.subscriptionTier = 'free',
    super.key,
  });

  /// Milestone day — one of 7, 14, 21, 30.
  final int day;

  /// Credits granted by the milestone.
  final int creditsAwarded;

  /// Optional superpower granted (e.g. 'SHIELD', 'RUSH').
  final String? powerGranted;

  /// Player's current subscription tier.
  final String subscriptionTier;

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

  /// Day 21 is the capstone of the streak curriculum - the only milestone
  /// tier that also earns a permanent badge - and gets a distinct,
  /// more celebratory treatment than the ordinary checkpoint milestones.
  bool get _isCapstone => widget.day == kFirstThirtyDaysCapstoneDay;

  @override
  Widget build(BuildContext context) {
    final headlineColor = _isCapstone ? kAccent2 : kAccent;

    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: kBg.withValues(alpha: 0.96),
        child: SafeArea(
          child: Stack(
            children: [
              if (_isCapstone) const Positioned.fill(child: _ConfettiBurst()),
              ScaleTransition(
                scale: _scale,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      // Animated milestone badge
                      Center(
                        child: _MilestoneBadge(
                            day: widget.day, capstone: _isCapstone),
                      ),
                      const SizedBox(height: 32),
                      // Headline
                      Text(
                        _isCapstone
                            ? 'FULL STREAK COMPLETE'
                            : 'DAY ${widget.day} MILESTONE',
                        textAlign: TextAlign.center,
                        style: displayStyle(size: 48, color: headlineColor),
                      ),
                      if (_isCapstone) ...[
                        const SizedBox(height: 4),
                        Text(
                          '21 DAYS RUNNING. NOT LUCK, DISCIPLINE.',
                          textAlign: TextAlign.center,
                          style: monoStyle(size: 12, color: kFgMuted),
                        ),
                      ],
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
                      // Permanent badge earned - capstone only.
                      if (_isCapstone) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: kAccent2.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: kAccent2.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            '21-DAY MARATHON BADGE EARNED',
                            textAlign: TextAlign.center,
                            style: monoStyle(size: 12, color: kAccent2),
                          ),
                        ),
                      ],
                      const Spacer(flex: 2),
                      // CTA
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                            _isCapstone ? 'CLAIM MARATHON REWARD' : 'CLAIM REWARD'),
                      ),
                      if (_isCapstone && widget.subscriptionTier == 'free') ...[
                        const SizedBox(height: 16),
                        _Day21PaywallSection(onDismiss: () {
                          Navigator.of(context).pop();
                          Navigator.of(context)
                              .push(PaywallDownsellScreen.route());
                        }),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paywall upsell section shown on day-21 milestone for free-tier players.
class _Day21PaywallSection extends StatelessWidget {
  const _Day21PaywallSection({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: kBorder),
        const SizedBox(height: 12),
        const Text(
          'UNLOCK FULL WAR ACCESS',
          style: TextStyle(color: kAccent2, fontSize: 12, letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),
        const Text(
          '$kDownsellExtensionDays-day streak earns you a '
          '€$kDownsellPriceAmount extended trial.',
          style: TextStyle(color: kFgMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onDismiss,
            style: ElevatedButton.styleFrom(backgroundColor: kAccent2),
            child: const Text(
              'SUBSCRIBE — €$kDownsellPriceAmount / $kDownsellExtensionDays DAYS',
              style: TextStyle(color: kBg),
            ),
          ),
        ),
      ],
    );
  }
}

/// Animated badge showing the milestone day number. When [capstone] is true
/// (the day-21 full-streak reward) it renders larger, with a wider gold
/// pulse ring and a solid fill, to read as a permanent badge rather than an
/// ordinary checkpoint marker.
class _MilestoneBadge extends StatefulWidget {
  const _MilestoneBadge({required this.day, this.capstone = false});

  final int day;
  final bool capstone;

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
    final baseRadius = widget.capstone ? 68.0 : 56.0;
    final pulseAmplitude = widget.capstone ? 12.0 : 8.0;
    final fillAlpha = widget.capstone ? 0.22 : 0.12;
    final fillAlphaBoost = widget.capstone ? 0.16 : 0.10;
    final borderWidth = widget.capstone ? 3.5 : 2.5;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final radius = baseRadius + pulseAmplitude * _pulse.value;
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kAccent2.withValues(
                alpha: widget.capstone
                    ? fillAlpha + fillAlphaBoost * _pulse.value
                    : 0.0),
            border: Border.all(
              color: kAccent2.withValues(alpha: 0.65 + 0.35 * _pulse.value),
              width: borderWidth,
            ),
          ),
          child: !widget.capstone
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        kAccent.withValues(alpha: fillAlpha + fillAlphaBoost * _pulse.value),
                  ),
                  child: Center(
                    child: Text(
                      '${widget.day}',
                      style: displayStyle(size: 52, color: kAccent2),
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    '${widget.day}',
                    style: displayStyle(size: 60, color: kAccent2),
                  ),
                ),
        );
      },
    );
  }
}

/// Lightweight confetti-burst effect for the day-21 capstone celebration.
/// Deliberately reuses the codebase's existing per-frame `AnimatedBuilder`
/// pattern (protocol #1 - recompute derived state inside `builder`, never
/// via `addListener` + `setState`) rather than pulling in a confetti
/// package, since this is a one-shot decorative overlay, not a reusable
/// physics system.
class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;

  static const _particleCount = 36;
  static const _colors = [kAccent, kAccent2, kSea, kFg];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();

    final rng = math.Random(21);
    _particles = List.generate(_particleCount, (i) {
      return _ConfettiParticle(
        startX: rng.nextDouble(),
        angle: rng.nextDouble() * math.pi * 2,
        speed: 0.35 + rng.nextDouble() * 0.5,
        size: 4.0 + rng.nextDouble() * 5.0,
        color: _colors[i % _colors.length],
        spinSpeed: (rng.nextDouble() - 0.5) * 8,
        fallDelay: rng.nextDouble() * 0.15,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              t: _controller.value,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ConfettiParticle {
  _ConfettiParticle({
    required this.startX,
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spinSpeed,
    required this.fallDelay,
  });

  final double startX; // 0..1 fraction of width
  final double angle; // initial outward burst direction
  final double speed; // fall + drift speed multiplier
  final double size;
  final Color color;
  final double spinSpeed;
  final double fallDelay; // 0..1 stagger before this particle starts moving
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.t});

  final List<_ConfettiParticle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final localT = ((t - p.fallDelay) / (1.0 - p.fallDelay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      final fadeAlpha = (1.0 - localT).clamp(0.0, 1.0);
      final driftX = math.cos(p.angle) * 40.0 * localT;
      final dx = p.startX * size.width + driftX;
      final dy = localT * size.height * p.speed;
      final rotation = p.spinSpeed * localT * math.pi;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rotation);
      final paint = Paint()..color = p.color.withValues(alpha: fadeAlpha);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldPainter) =>
      oldPainter.t != t;
}
