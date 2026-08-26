// lib/widgets/intro/intro_purge_leaderboard.dart
//
// IntroPurgeLeaderboard — pure CustomPainter animation for slide 8 ("THE
// PURGE"). Operator-locked Option B (leaderboard cut): a ranked list of
// runners, a countdown that reaches zero, and a red cut line - visible from
// the very start of the loop - separating survivors (above) from the
// eliminated (below). No map, no GPS - matches the retired IntroSurvivalCut's
// profile.
//
// Row values carry no numeric distance/score — rank is signalled purely by
// list order, plus YOU's accent-gold styling. The cut line is on screen at
// t=0; YOU starts below it and swaps upward, one row at a time, across three
// discrete turns, finishing clear of the line before the countdown lands.
//
// Timeline (8s loop, loopController pattern):
//   0.00       red cut line renders immediately at its resting position
//              (between slot 4 and slot 5); rows render top-to-bottom,
//              countdown shows 00:05. YOU sits below the line.
//   0.06-0.22  Turn 1 — YOU swaps upward past the row directly above it.
//   0.22-0.38  Turn 2 — YOU swaps upward again, landing on the boundary slot.
//   0.38-0.54  Turn 3 — YOU swaps upward once more, ending clear of the cut.
//              Countdown reaches 00:00 at the end of this turn.
//   0.58-0.82  rows below the line strike through, then sweep sideways +
//              fade off-screen.
//   0.82-1.00  hold on the final state.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';
import 'intro_helpers.dart';

// ── Turn boundaries (fractions of the 8s loop) ──────────────────────────────
const double _kTurn1Start = 0.06;
const double _kTurn1End = 0.22;
const double _kTurn2Start = 0.22;
const double _kTurn2End = 0.38;
const double _kTurn3Start = 0.38;
const double _kTurn3End = 0.54;

// The cut line is static - visible at its resting position from t=0 - so the
// sweep of eliminated rows starts shortly after the countdown lands at the
// end of turn 3 (no rise beat precedes it anymore).
const double _kSweepStart = 0.58;
const double _kSweepEnd = 0.82;

// ── Data model (static demo values — presentation only, not live data) ─────
// No numeric field exists anywhere on this model: rank is conveyed only by
// the row's rendered slot (top-to-bottom list order), never a digit.
class _SwapEvent {
  final double start;
  final double end;
  final int toSlot;
  const _SwapEvent(this.start, this.end, this.toSlot);
}

class _PurgeRow {
  final String handle;
  final bool isYou;
  final bool eliminated;
  final int homeSlot;
  final List<_SwapEvent> events;
  const _PurgeRow(
    this.handle, {
    this.isYou = false,
    this.eliminated = false,
    required this.homeSlot,
    this.events = const [],
  });
}

// Turn 0 (initial) order is the list's declaration order. YOU starts at slot
// 6 (below the cut line, which is on screen from t=0) and swaps upward with
// the row immediately above it once per turn, ending at slot 3, one clear
// survivor slot above the cut.
const _kPurgeRows = [
  _PurgeRow('@NOVA_RUN', homeSlot: 0),
  _PurgeRow('@KM_REAPER', homeSlot: 1),
  _PurgeRow('@PACER_V', homeSlot: 2),
  _PurgeRow(
    '@GRINDCORE',
    homeSlot: 3,
    events: [_SwapEvent(_kTurn3Start, _kTurn3End, 4)],
  ),
  _PurgeRow(
    '@STORMCHASE',
    homeSlot: 4,
    eliminated: true,
    events: [_SwapEvent(_kTurn2Start, _kTurn2End, 5)],
  ),
  _PurgeRow(
    '@LOWBEAM',
    homeSlot: 5,
    eliminated: true,
    events: [_SwapEvent(_kTurn1Start, _kTurn1End, 6)],
  ),
  _PurgeRow(
    'YOU',
    isYou: true,
    homeSlot: 6,
    events: [
      _SwapEvent(_kTurn1Start, _kTurn1End, 5),
      _SwapEvent(_kTurn2Start, _kTurn2End, 4),
      _SwapEvent(_kTurn3Start, _kTurn3End, 3),
    ],
  ),
  _PurgeRow('@DUSKRUN', homeSlot: 7, eliminated: true),
];

// Slot index (0-based) of the last surviving row once all swaps land. The
// cut line rests between this slot and the next.
const int _kCutAfterIndex = 4;

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

  /// Fractional slot (0-based, top-to-bottom) [row] occupies at time [t].
  /// Returns a non-integer value while a swap for that row is in progress,
  /// so callers can interpolate a smooth y-position (ease-out slide).
  double _slotFor(_PurgeRow row) {
    double slot = row.homeSlot.toDouble();
    for (final e in row.events) {
      if (t <= e.start) break;
      if (t >= e.end) {
        slot = e.toSlot.toDouble();
        continue;
      }
      final localT = (t - e.start) / (e.end - e.start);
      final eased = Curves.easeInOut.transform(localT);
      slot = slot + (e.toSlot - slot) * eased;
      break;
    }
    return slot;
  }

  /// Triangular 0-1 pulse while [row] has a swap in progress at time [t];
  /// 0 outside any swap window. Draws YOU's accent glow during each turn.
  double _swapPulseFor(_PurgeRow row) {
    for (final e in row.events) {
      if (t > e.start && t < e.end) {
        final localT = (t - e.start) / (e.end - e.start);
        return (1.0 - (localT - 0.5).abs() * 2).clamp(0.0, 1.0);
      }
    }
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const rowsTopY = _topPad;

    // ── Countdown (0.0-0.54 ticks toward 00:00, landing with turn 3) ───────
    final countdownT = (t / _kTurn3End).clamp(0.0, 1.0);
    final secondsLeft = (5 * (1.0 - countdownT)).ceil().clamp(0, 5);
    final countdownText = '00:0$secondsLeft';
    _drawCountdown(canvas, size, countdownText);

    // ── Rows ─────────────────────────────────────────────────────────────
    final sweepT = ((t - _kSweepStart) / (_kSweepEnd - _kSweepStart)).clamp(0.0, 1.0);
    final strikeT = ((t - _kSweepStart) / 0.06).clamp(0.0, 1.0);

    for (final row in _kPurgeRows) {
      final slot = _slotFor(row);
      final rowY = rowsTopY + slot * _rowHeight;

      double dx = 0;
      double alpha = 1.0;
      if (row.eliminated) {
        // Eliminated rows strike through then sweep sideways + fade, once
        // the countdown has landed and every swap has already finished.
        dx = Curves.easeIn.transform(sweepT) * size.width * 0.6;
        alpha = 1.0 - sweepT;
      }
      if (alpha <= 0) continue;

      final pulseAlpha = row.isYou ? _swapPulseFor(row) : 0.0;

      _drawRow(
        canvas,
        size,
        row: row,
        y: rowY,
        dx: dx,
        alpha: alpha,
        strikeThrough: row.eliminated && strikeT > 0,
        strikeProgress: strikeT,
        pulseAlpha: pulseAlpha,
      );
    }

    // ── Red cut line - static at its resting position from t=0 ───────────
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
    required double y,
    required double dx,
    required double alpha,
    required bool strikeThrough,
    required double strikeProgress,
    double pulseAlpha = 0.0,
  }) {
    final rowColor = row.isYou ? kAccent2 : kFg;

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

    if (pulseAlpha > 0) {
      final glowRect = Rect.fromLTWH(
        handleX - 8,
        y - 4,
        handleTp.width + 16,
        handleTp.height + 8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(glowRect, const Radius.circular(6)),
        Paint()..color = kAccent2.withValues(alpha: pulseAlpha * 0.28 * alpha),
      );
    }

    handleTp.paint(canvas, Offset(handleX, y));

    if (strikeThrough) {
      final lineY = y + handleTp.height / 2;
      final lineEndX = handleX + (handleTp.width + 80) * strikeProgress;
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
    // Visible from t=0: the line sits at its resting position for the whole
    // loop while the rows swap around it (operator ask: the cut line must
    // display at the START of the animation, not appear later).
    final lineY = rowsTopY + (_kCutAfterIndex + 1) * _rowHeight - 8;

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
