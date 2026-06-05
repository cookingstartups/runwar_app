import 'package:flutter/material.dart';

/// "Color beam pulse" player dot — matches the intro-slide 1/2 aesthetic.
///
/// Three concentric layers:
///   outer pulsing ring → glow halo → solid dot → white core
///
/// [showPulse] — true (default): animating ring + glow; false: static glow dot.
class BeamPulseDot extends StatefulWidget {
  const BeamPulseDot({
    super.key,
    required this.color,
    this.size = 10.0,
    this.showPulse = true,
  });

  final Color color;
  final double size;
  final bool showPulse;

  @override
  State<BeamPulseDot> createState() => _BeamPulseDotState();
}

class _BeamPulseDotState extends State<BeamPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    if (!widget.showPulse) {
      return SizedBox(
        width: s * 3.5,
        height: s * 3.5,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s * 2.0,
                height: s * 2.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.22),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.40),
                      blurRadius: s,
                    ),
                  ],
                ),
              ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
              Container(
                width: s * 0.38,
                height: s * 0.38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return SizedBox(
          width: s * 5,
          height: s * 5,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulsing halo ring
                Container(
                  width: s * (2.5 + t * 1.5),
                  height: s * (2.5 + t * 1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.35 - t * 0.25),
                      width: 1.5,
                    ),
                  ),
                ),
                // Glow halo
                Container(
                  width: s * 2.0,
                  height: s * 2.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.18 + t * 0.08),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.35 + t * 0.15),
                        blurRadius: s * (1.0 + t * 0.6),
                        spreadRadius: s * 0.1,
                      ),
                    ],
                  ),
                ),
                // Solid dot
                Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.7 + t * 0.3),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.55),
                        blurRadius: s * 0.8,
                      ),
                    ],
                  ),
                ),
                // White core
                Container(
                  width: s * 0.38,
                  height: s * 0.38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
