import 'package:flutter/material.dart';

import '../theme.dart';

/// Full-screen celebration overlay shown after a player claims their first zone.
///
/// Uses a FadeTransition + ScaleTransition to animate in over 1.5 seconds.
/// Calls [onContinue] when the user taps "ENTER THE WAR".
class FirstZoneCelebrationOverlay extends StatefulWidget {
  const FirstZoneCelebrationOverlay({
    super.key,
    required this.onContinue,
  });

  final VoidCallback onContinue;

  @override
  State<FirstZoneCelebrationOverlay> createState() =>
      _FirstZoneCelebrationOverlayState();
}

class _FirstZoneCelebrationOverlayState
    extends State<FirstZoneCelebrationOverlay>
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
        color: kBg.withValues(alpha: 0.94),
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
                  // Pulsing zone fill indicator
                  Center(
                    child: _PulsingZoneFill(),
                  ),
                  const SizedBox(height: 36),
                  // Credits counter
                  Text(
                    '+50 CREDITS',
                    textAlign: TextAlign.center,
                    style: displayStyle(size: 56, color: kAccent),
                  ),
                  const SizedBox(height: 12),
                  // Streak subtext
                  Text(
                    'STREAK STARTED — Day 1',
                    textAlign: TextAlign.center,
                    style: monoStyle(size: 12, color: kFgMuted),
                  ),
                  const Spacer(flex: 2),
                  // CTA
                  ElevatedButton(
                    onPressed: widget.onContinue,
                    child: const Text('ENTER THE WAR  →'),
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

/// Animated orange fill circle representing the claimed zone.
class _PulsingZoneFill extends StatefulWidget {
  @override
  State<_PulsingZoneFill> createState() => _PulsingZoneFillState();
}

class _PulsingZoneFillState extends State<_PulsingZoneFill>
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
        final radius = 60.0 + 10.0 * _pulse.value;
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kAccent.withValues(alpha: 0.15 + 0.12 * _pulse.value),
            border: Border.all(
              color: kAccent.withValues(alpha: 0.7 + 0.3 * _pulse.value),
              width: 2.5,
            ),
          ),
          child: const Icon(
            Icons.flag_rounded,
            color: kAccent,
            size: 48,
          ),
        );
      },
    );
  }
}
