import 'package:flutter/material.dart';
import '../theme.dart';

class MilestoneProgressBar extends StatefulWidget {
  const MilestoneProgressBar({
    super.key,
    required this.currentStep,
    required this.labels,
  });

  final int currentStep; // 0-indexed; dots 0..labels.length-1
  final List<String> labels;

  @override
  State<MilestoneProgressBar> createState() => _MilestoneProgressBarState();
}

class _MilestoneProgressBarState extends State<MilestoneProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _fill;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fill = Tween<double>(begin: 0.0, end: 0.0).animate(_ctrl);
    _updateFill(animate: false);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(MilestoneProgressBar old) {
    super.didUpdateWidget(old);
    if (old.currentStep != widget.currentStep) {
      _updateFill(animate: true);
    }
  }

  void _updateFill({required bool animate}) {
    final target = widget.labels.isEmpty
        ? 0.0
        : widget.currentStep / (widget.labels.length - 1);
    _fill = Tween<double>(begin: _fill.value, end: target.clamp(0.0, 1.0))
        .animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Cubic(0.22, 1, 0.36, 1),
    ));
    if (animate) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 28,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _BarPainter(
                    fill: _fill.value,
                    currentStep: widget.currentStep,
                    steps: n,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(n, (i) {
              final done = i <= widget.currentStep;
              return Expanded(
                child: Text(
                  widget.labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    letterSpacing: 1.5,
                    color: done ? kFg : kFgMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.fill,
    required this.currentStep,
    required this.steps,
  });

  final double fill;
  final int currentStep;
  final int steps;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final mid = size.height / 2;
    const dotR = 5.0;

    // Track
    canvas.drawLine(
      Offset(0, mid),
      Offset(w, mid),
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.08)
        ..strokeWidth = 2,
    );

    // Filled portion (gradient fire)
    if (fill > 0) {
      final fillW = w * fill;
      canvas.drawLine(
        Offset(0, mid),
        Offset(fillW, mid),
        Paint()
          ..shader = LinearGradient(colors: kGradientFire)
              .createShader(Rect.fromLTWH(0, 0, fillW, 1))
          ..strokeWidth = 2,
      );
    }

    // Milestone dots
    for (var i = 0; i < steps; i++) {
      final x = steps == 1 ? w / 2 : w * i / (steps - 1);
      final done = i < currentStep;
      final active = i == currentStep;

      if (active) {
        // Glow ring
        canvas.drawCircle(
          Offset(x, mid),
          dotR + 4,
          Paint()
            ..color = kAccent.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      // Dot fill
      canvas.drawCircle(
        Offset(x, mid),
        dotR,
        Paint()..color = (done || active) ? kAccent : kBg,
      );

      // Dot border
      canvas.drawCircle(
        Offset(x, mid),
        dotR,
        Paint()
          ..color = (done || active) ? kAccent : kFgMuted
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fill != fill || old.currentStep != currentStep;
}
