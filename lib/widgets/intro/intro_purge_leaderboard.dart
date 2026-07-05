// lib/widgets/intro/intro_purge_leaderboard.dart
//
// IntroPurgeLeaderboard — pure CustomPainter animation for slide 8 ("THE
// PURGE"). Operator-locked Option B (leaderboard cut): a ranked list of
// runners with distance values, a countdown that reaches zero, and a red
// cut line that rises to separate survivors (above) from the eliminated
// (below). No map, no GPS — matches the retired IntroSurvivalCut's profile.
//
// Timeline (8s loop, loopController pattern):
//   0.00-0.50  rows render top-to-bottom, countdown ticks toward 00:00
//   0.50-0.65  red cut line rises from below the last row to its resting
//              position between rank 4 and rank 5
//   0.65-0.85  rows below the line strike through, then sweep sideways +
//              fade off-screen
//   0.85-1.00  hold on the final state

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';
import 'intro_helpers.dart';

// ── Data model (static demo values — presentation only, not live data) ─────
class _PurgeRow {
  final String handle;
  final int km;
  final bool isYou;
  const _PurgeRow(this.handle, this.km, {this.isYou = false});
}

const _kPurgeRows = [
  _PurgeRow('@NOVA_RUN', 212),
  _PurgeRow('@KM_REAPER', 198),
  _PurgeRow('@PACER_V', 171),
  _PurgeRow('YOU', 154, isYou: true),
  _PurgeRow('@GRINDCORE', 140),
  _PurgeRow('@STORMCHASE', 118),
  _PurgeRow('@LOWBEAM', 96),
  _PurgeRow('@DUSKRUN', 71),
];

// Rank index (0-based) of the last surviving row. The cut line rests between
// this row and the next — YOU sits one row above it (R-20).
const int _kCutAfterIndex = 3;

const double _kCutRiseStart = 0.50;
const double _kCutRiseEnd = 0.65;
const double _kSweepStart = 0.65;
const double _kSweepEnd = 0.85;

class IntroPurgeLeaderboard extends StatefulWidget {
  const IntroPurgeLeaderboard({super.key});

  @override
  State<IntroPurgeLeaderboard> createState() => _IntroPurgeLeaderboardState();
}

class _IntroPurgeLeaderboardState extends State<IntroPurgeLeaderboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    loopController(_ctrl, mounted: () => mounted);
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
        return CustomPaint(
          painter: _IntroPurgeLeaderboardPainter(t: _ctrl.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _IntroPurgeLeaderboardPainter extends CustomPainter {
  _IntroPurgeLeaderboardPainter({required this.t});

  final double t;

  static const double _rowHeight = 34.0;
  static const double _topPad = 56.0;
  static const double _sidePad = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    const rowsTopY = _topPad;

    // ── Countdown (0.0-0.5 ticks toward 00:00; holds after) ────────────────
    final countdownT = (t / _kCutRiseStart).clamp(0.0, 1.0);
    final secondsLeft = (5 * (1.0 - countdownT)).ceil().clamp(0, 5);
    final countdownText = '00:0$secondsLeft';
    _drawCountdown(canvas, size, countdownText);

    // ── Rows ─────────────────────────────────────────────────────────────
    final sweepT = ((t - _kSweepStart) / (_kSweepEnd - _kSweepStart)).clamp(0.0, 1.0);
    final strikeT = ((t - _kSweepStart) / 0.06).clamp(0.0, 1.0);

    for (int i = 0; i < _kPurgeRows.length; i++) {
      final row = _kPurgeRows[i];
      final rowY = rowsTopY + i * _rowHeight;
      final belowCut = i > _kCutAfterIndex;

      double dx = 0;
      double alpha = 1.0;
      if (belowCut) {
        // Rows below the line strike through then sweep sideways + fade.
        dx = Curves.easeIn.transform(sweepT) * size.width * 0.6;
        alpha = 1.0 - sweepT;
      }
      if (alpha <= 0) continue;

      _drawRow(
        canvas,
        size,
        row: row,
        rank: i + 1,
        y: rowY,
        dx: dx,
        alpha: alpha,
        strikeThrough: belowCut && strikeT > 0,
        strikeProgress: strikeT,
      );
    }

    // ── Red cut line — rises between rank 4/5 (R-20) ───────────────────────
    _drawCutLine(canvas, size, rowsTopY);
  }

  void _drawCountdown(Canvas canvas, Size size, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: monoStyle(size: 22, color: kDanger),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, 8));
  }

  void _drawRow(
    Canvas canvas,
    Size size, {
    required _PurgeRow row,
    required int rank,
    required double y,
    required double dx,
    required double alpha,
    required bool strikeThrough,
    required double strikeProgress,
  }) {
    final rowColor = row.isYou ? kAccent2 : kFg;

    final rankTp = TextPainter(
      text: TextSpan(
        text: '$rank',
        style: monoStyle(size: 12, color: kFgMuted.withValues(alpha: alpha)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rankTp.paint(canvas, Offset(_sidePad + dx, y));

    final handleTp = TextPainter(
      text: TextSpan(
        text: row.handle,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: row.isYou ? FontWeight.w700 : FontWeight.w500,
          color: rowColor.withValues(alpha: alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final handleX = _sidePad + 28 + dx;
    handleTp.paint(canvas, Offset(handleX, y));

    final kmTp = TextPainter(
      text: TextSpan(
        text: '${row.km} KM',
        style: monoStyle(size: 12, color: kFgMuted.withValues(alpha: alpha)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    kmTp.paint(
        canvas, Offset(size.width - _sidePad - kmTp.width + dx, y));

    if (strikeThrough) {
      final lineY = y + handleTp.height / 2;
      final lineEndX = handleX + (handleTp.width + kmTp.width + 60) * strikeProgress;
      canvas.drawLine(
        Offset(handleX, lineY),
        Offset(lineEndX.clamp(handleX, size.width - _sidePad), lineY),
        Paint()
          ..color = kDanger.withValues(alpha: alpha)
          ..strokeWidth = 2.0,
      );
    }
  }

  void _drawCutLine(Canvas canvas, Size size, double rowsTopY) {
    final restingY = rowsTopY + (_kCutAfterIndex + 1) * _rowHeight - 8;
    final belowScreenY = rowsTopY + _kPurgeRows.length * _rowHeight + 20;

    final riseT = ((t - _kCutRiseStart) / (_kCutRiseEnd - _kCutRiseStart))
        .clamp(0.0, 1.0);
    if (t < _kCutRiseStart) return;

    final lineY = belowScreenY - (belowScreenY - restingY) * Curves.easeOut.transform(riseT);

    canvas.drawLine(
      Offset(_sidePad, lineY),
      Offset(size.width - _sidePad, lineY),
      Paint()
        ..color = kDanger
        ..strokeWidth = 2.0,
    );

    final labelTp = TextPainter(
      text: TextSpan(text: 'CUT LINE', style: monoStyle(size: 9, color: kDanger)),
      textDirection: TextDirection.ltr,
    )..layout();
    labelTp.paint(canvas, Offset(size.width - _sidePad - labelTp.width, lineY - 16));
  }

  @override
  bool shouldRepaint(_IntroPurgeLeaderboardPainter old) => old.t != t;
}
