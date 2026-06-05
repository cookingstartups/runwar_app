// lib/beta/aesthetics/squid_game_theme.dart
//
// RunWar "Earn Your Seat" aesthetic package — Squid Game-inspired visual system.
//
// Palette, typography, shapes, and widgets used for elimination-round UI:
//   - Weekly rank-cut screens
//   - "ELIMINATED" notifications
//   - Survival countdown overlays
//   - Rank badge system (Circle → Triangle → Square)

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────

const Color sqPink       = Color(0xFFFF0067); // Squid Game hot pink
const Color sqNavy       = Color(0xFF0F2233); // deep navy backdrop
const Color sqTeal       = Color(0xFF00D4AA); // teal accent (guards)
const Color sqGold       = Color(0xFFFFD700); // rank/prize gold
const Color sqWhite      = Color(0xFFF5F5F5); // off-white typography
const Color sqDanger     = Color(0xFFFF2D2D); // elimination red
const Color sqMuted      = Color(0xFF4A5568); // muted label text

// ── Text styles ───────────────────────────────────────────────────────────────

TextStyle sqDisplay(double size) => TextStyle(
  color: sqWhite,
  fontSize: size,
  fontFamily: 'BebasNeue',
  fontWeight: FontWeight.w700,
  letterSpacing: 3.0,
  height: 1.0,
);

TextStyle sqLabel(double size, {Color color = sqTeal}) => TextStyle(
  color: color,
  fontSize: size,
  fontFamily: 'monospace',
  fontWeight: FontWeight.w600,
  letterSpacing: 2.5,
);

TextStyle sqBody(double size) => TextStyle(
  color: sqWhite.withValues(alpha: 0.75),
  fontSize: size,
  height: 1.5,
);

// ── Shape constants ───────────────────────────────────────────────────────────

enum SurvivalRank {
  circle,    // recruit  — just started
  triangle,  // runner   — earning territory
  square,    // elite    — top percentile
}

extension SurvivalRankLabel on SurvivalRank {
  String get label {
    switch (this) {
      case SurvivalRank.circle:   return 'RECRUIT';
      case SurvivalRank.triangle: return 'RUNNER';
      case SurvivalRank.square:   return 'ELITE';
    }
  }
  Color get color {
    switch (this) {
      case SurvivalRank.circle:   return sqTeal;
      case SurvivalRank.triangle: return sqPink;
      case SurvivalRank.square:   return sqGold;
    }
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

/// Rank badge — circle/triangle/square symbol from the Squid Game guards.
class SurvivalRankBadge extends StatelessWidget {
  const SurvivalRankBadge({
    super.key,
    required this.rank,
    this.size = 40.0,
  });

  final SurvivalRank rank;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RankShapePainter(rank: rank, size: size),
    );
  }
}

class _RankShapePainter extends CustomPainter {
  const _RankShapePainter({required this.rank, required this.size});
  final SurvivalRank rank;
  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final color = rank.color;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.08;
    final center = Offset(size / 2, size / 2);
    final r = size * 0.40;

    switch (rank) {
      case SurvivalRank.circle:
        canvas.drawCircle(center, r, paint);
      case SurvivalRank.triangle:
        final h = r * math.sqrt(3) / 2;
        final path = Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r * math.sqrt(3) / 2, center.dy + h)
          ..lineTo(center.dx - r * math.sqrt(3) / 2, center.dy + h)
          ..close();
        canvas.drawPath(path, paint);
      case SurvivalRank.square:
        canvas.drawRect(
          Rect.fromCenter(center: center, width: r * 1.6, height: r * 1.6),
          paint,
        );
    }
    // Inner fill glow
    paint
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.12);
    switch (rank) {
      case SurvivalRank.circle:
        canvas.drawCircle(center, r, paint);
      case SurvivalRank.triangle:
        final h = r * math.sqrt(3) / 2;
        final path = Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r * math.sqrt(3) / 2, center.dy + h)
          ..lineTo(center.dx - r * math.sqrt(3) / 2, center.dy + h)
          ..close();
        canvas.drawPath(path, paint);
      case SurvivalRank.square:
        canvas.drawRect(
          Rect.fromCenter(center: center, width: r * 1.6, height: r * 1.6),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_RankShapePainter old) => old.rank != rank || old.size != size;
}

/// "ELIMINATED" splash overlay — shown on weekly cut.
class EliminatedOverlay extends StatefulWidget {
  const EliminatedOverlay({super.key, required this.child, this.show = false});
  final Widget child;
  final bool show;

  @override
  State<EliminatedOverlay> createState() => _EliminatedOverlayState();
}

class _EliminatedOverlayState extends State<EliminatedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.show) _ctrl.forward();
  }

  @override
  void didUpdateWidget(EliminatedOverlay old) {
    super.didUpdateWidget(old);
    if (widget.show && !old.show) _ctrl.forward();
    if (!widget.show && old.show) _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            if (_ctrl.value == 0) return const SizedBox.shrink();
            return Opacity(
              opacity: _ctrl.value,
              child: Container(
                color: sqDanger.withValues(alpha: 0.85),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ELIMINATED', style: sqDisplay(52)),
                    const SizedBox(height: 12),
                    Text(
                      'Your zone went dark.\nRun harder next week.',
                      textAlign: TextAlign.center,
                      style: sqBody(16),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Survival countdown timer bar — red → yellow → green.
class SurvivalCountdownBar extends StatelessWidget {
  const SurvivalCountdownBar({
    super.key,
    required this.fractionRemaining, // 0.0 = time up, 1.0 = full
    this.height = 6.0,
  });

  final double fractionRemaining;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = fractionRemaining > 0.6
        ? sqTeal
        : fractionRemaining > 0.3
            ? sqGold
            : sqDanger;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: sqNavy,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        widthFactor: fractionRemaining.clamp(0.0, 1.0),
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
            ],
          ),
        ),
      ),
    );
  }
}
