import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated radar-ping ring used on the invite-only close slide.
class PulseRing extends StatefulWidget {
  final Color color;

  const PulseRing({super.key, this.color = kAccent});

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 84,
        height: 84,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _PulseRingPainter(_c.value, widget.color),
          ),
        ),
      );
}

class _PulseRingPainter extends CustomPainter {
  final double t;
  final Color color;

  const _PulseRingPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 30 + t * 12;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: (1 - t) * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) => old.t != t || old.color != color;
}
