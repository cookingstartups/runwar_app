// lib/widgets/intro/intro_survival_cut.dart
//
// IntroSurvivalCut — pure CustomPainter animation for the "THE BOTTOM DROPS"
// intro slide. Visualises the weekly survival-cut mechanic: ~100 circles in an
// inverse-funnel grid that fill, get cut (red flash → grey), swap positions,
// and reset. Pure canvas widget — no map, no GPS, no text.
//
// AC coverage: AC-1 through AC-9 (requirements.md)

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const int _kRowCount = 11; // AC-2: 10–12 rows; 11 hits ~100 circles target
const double _kTopWidthFrac = 0.80; // top row spans 80 % of canvas width
const double _kBotWidthFrac = 0.80; // bottom row also spans 80 % (clean rectangle, not a funnel)
const double _kCircleRadius = 5.0; // circle radius in logical px
const double _kStrokeWidth = 1.5; // stroke width for empty circles
const double _kJitterFrac = 0.0; // no jitter; dots sit on an exact grid
const double _kRowTopPad = 24.0; // padding from canvas top edge
const Color _kCutFlash = Color(0xFFFF3344); // elimination red flash

// ── Data models ───────────────────────────────────────────────────────────────

enum _CircleState { empty, filled, cut } // AC-3

class _SeatPos {
  _SeatPos({required this.base});

  final Offset base; // computed once; never mutates
  _CircleState state = _CircleState.empty;
  double fillAlpha = 0.0; // 0.0→1.0 during fill transition
  DateTime? fillStart; // set when fill transition begins
  DateTime? cutFlashStart; // set when cut flash begins (null = not cutting)
}

class _SwapAnim {
  _SwapAnim({
    required this.idxA,
    required this.idxB,
    required this.startA,
    required this.endA,
    required this.startB,
    required this.endB,
    required this.start,
  });

  final int idxA;
  final int idxB;
  final Offset startA;
  final Offset endA; // = base of B
  final Offset startB;
  final Offset endB; // = base of A
  final DateTime start;
  double t = 0.0; // 0.0→1.0 over 350 ms
}

// ── Widget ────────────────────────────────────────────────────────────────────

class IntroSurvivalCut extends StatefulWidget {
  const IntroSurvivalCut({super.key});

  @override
  State<IntroSurvivalCut> createState() => _IntroSurvivalCutState();
}

class _IntroSurvivalCutState extends State<IntroSurvivalCut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _swapTimer;
  List<_SeatPos> _seats = [];
  final List<_SwapAnim> _swapAnims = [];
  bool _layoutDone = false;
  bool _swapStarted = false;

  @override
  void initState() {
    super.initState();

    // AC-1: single AnimationController, 120 ms repeat
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    )..repeat();

    // AC-4: addStatusListener fires once per 120 ms cycle (NOT addListener)
    _ctrl.addStatusListener(_onTick);
  }

  // ── Layout ──────────────────────────────────────────────────────────────────

  void _buildLayout(Size size) {
    if (_layoutDone) return;
    _layoutDone = true;

    final rng = Random();
    final W = size.width;
    final H = size.height;
    final rowSpacing = (H - 2 * _kRowTopPad) / (_kRowCount - 1);
    final seats = <_SeatPos>[];

    for (int r = 0; r < _kRowCount; r++) {
      final rowFrac = r / (_kRowCount - 1); // 0.0 (top) → 1.0 (bottom)
      final rowWidth =
          W * (_kTopWidthFrac + (_kBotWidthFrac - _kTopWidthFrac) * rowFrac);
      final rowX0 = (W - rowWidth) / 2;
      final rowY = _kRowTopPad + r * rowSpacing;

      // Number of circles proportional to row width. Pitch ~ circleRadius * 6.4
      // keeps total dots in the 90-110 range across an 11-row uniform grid.
      final circlesInRow = max(1, (rowWidth / (_kCircleRadius * 6.4)).round());
      final pitch = circlesInRow > 1 ? rowWidth / (circlesInRow - 1) : 0.0;

      for (int c = 0; c < circlesInRow; c++) {
        final baseX = circlesInRow > 1
            ? rowX0 + c * pitch
            : W / 2; // centre single-circle rows
        final jitterX = (rng.nextDouble() * 2 - 1) * _kJitterFrac * rowSpacing;
        final jitterY = (rng.nextDouble() * 2 - 1) * _kJitterFrac * rowSpacing;
        seats.add(_SeatPos(base: Offset(baseX + jitterX, rowY + jitterY)));
      }

      // Safety cap at 120 circles
      if (seats.length >= 120) break;
    }

    _seats = seats;
  }

  // ── Tick dispatch (addStatusListener — fires once per 120 ms cycle) ─────────

  void _onTick(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_seats.isEmpty) return;

    // AC-5: start swap loop on the first tick (deferred to avoid pending timers
    // at widget mount time; swap fires ~600 ms after the animation begins).
    if (!_swapStarted) {
      _swapStarted = true;
      _scheduleSwap();
    }

    final nonCutCount =
        _seats.where((s) => s.state != _CircleState.cut).length;
    if (nonCutCount < 15) {
      _reset();
      return;
    }

    final isCut = Random().nextDouble() < 0.10;
    if (isCut && nonCutCount >= 5) {
      _triggerCut();
    } else {
      _triggerFill();
    }
  }

  // ── Fill transition ──────────────────────────────────────────────────────────

  void _triggerFill() {
    final empties =
        _seats.where((s) => s.state == _CircleState.empty && s.fillStart == null).toList();
    if (empties.isEmpty) return; // AC-4 edge: no empty circles — skip silently
    final target = empties[Random().nextInt(empties.length)];
    target.fillStart = DateTime.now();
  }

  void _advanceFills() {
    final now = DateTime.now();
    for (final s in _seats) {
      if (s.fillStart == null) continue;
      final ms = now.difference(s.fillStart!).inMilliseconds;
      s.fillAlpha =
          Curves.easeIn.transform((ms / 200.0).clamp(0.0, 1.0));
      if (ms >= 200) {
        s.state = _CircleState.filled;
        s.fillAlpha = 1.0;
        s.fillStart = null;
      }
    }
  }

  // ── Cut transition ───────────────────────────────────────────────────────────

  void _triggerCut() {
    final candidates = _seats
        .where((s) => s.state != _CircleState.cut && s.cutFlashStart == null)
        .toList()
      ..sort((a, b) => b.base.dy.compareTo(a.base.dy)); // highest Y first (lowest on screen)
    if (candidates.isEmpty) return;
    // At least 2 dots per cut cycle (3 when there is still plenty of room).
    final n = min(candidates.length, max(2, (candidates.length * 0.10).round()));
    final victims = candidates.take(n).toList();
    final now = DateTime.now();
    for (final v in victims) {
      v.cutFlashStart = now;
    }
  }

  void _advanceCuts() {
    final now = DateTime.now();
    for (final seat in _seats) {
      if (seat.cutFlashStart == null) continue;
      final ms = now.difference(seat.cutFlashStart!).inMilliseconds;
      if (ms >= 600) {
        // Phase 3 complete: seat is gone (cut + fully transparent).
        seat.state = _CircleState.cut;
        seat.cutFlashStart = null;
        seat.fillStart = null;
        seat.fillAlpha = 0.0;
      }
      // Phase 1 (0-200 ms red hold) and phase 2 (200-600 ms fade to transparent)
      // rendering is handled by the painter using cutFlashStart timestamp directly.
    }
  }

  // ── Reset ────────────────────────────────────────────────────────────────────

  void _reset() {
    for (final s in _seats) {
      s.state = _CircleState.empty;
      s.fillAlpha = 0.0;
      s.fillStart = null;
      s.cutFlashStart = null;
    }
    _swapAnims.clear();
  }

  // ── Swap animation ───────────────────────────────────────────────────────────

  void _scheduleSwap() {
    _swapTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return; // AC-9 guard
      _doSwap();
      _scheduleSwap(); // reschedule
    });
  }

  void _doSwap() {
    // AC-5: skip if cap reached
    if (_swapAnims.length >= 8) return;

    // Collect indices of filled, non-cutting circles (AC risk-2 guard)
    final filledIndices = _seats
        .asMap()
        .entries
        .where((e) =>
            e.value.state == _CircleState.filled &&
            e.value.cutFlashStart == null)
        .map((e) => e.key)
        .toList();

    if (filledIndices.length < 2) return; // AC-5: fewer than 2 filled — skip

    // Shuffle and pick min(4, filledCount ~/ 2) non-overlapping pairs
    filledIndices.shuffle();
    final pairCount = min(4, filledIndices.length ~/ 2);
    final now = DateTime.now();

    for (int p = 0; p < pairCount; p++) {
      if (_swapAnims.length >= 8) break; // cap guard
      final idxA = filledIndices[p * 2];
      final idxB = filledIndices[p * 2 + 1];
      _swapAnims.add(_SwapAnim(
        idxA: idxA,
        idxB: idxB,
        startA: _seats[idxA].base,
        endA: _seats[idxB].base,
        startB: _seats[idxB].base,
        endB: _seats[idxA].base,
        start: now,
      ));
    }
  }

  void _advanceSwaps() {
    final now = DateTime.now();
    final completed = <_SwapAnim>[];
    for (final sw in _swapAnims) {
      sw.t =
          (now.difference(sw.start).inMilliseconds / 350.0).clamp(0.0, 1.0);
      if (sw.t >= 1.0) {
        completed.add(sw);
      }
    }
    // Remove completed swaps; logical positions already encoded in startA/endA
    for (final sw in completed) {
      _swapAnims.remove(sw);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Compute layout on first build using MediaQuery size (AC-2)
    _buildLayout(MediaQuery.sizeOf(context));

    // AC-1: AnimatedBuilder is the root; no addListener+setState anywhere
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        _advanceFills();
        _advanceCuts();
        _advanceSwaps();
        return CustomPaint(
          painter: _SurvivalCutPainter(
            seats: _seats,
            swapAnims: _swapAnims,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  // ── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _swapTimer?.cancel(); // cancel any pending swap timer — no post-dispose callbacks
    _ctrl.dispose(); // AC-9
    super.dispose();
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _SurvivalCutPainter extends CustomPainter {
  _SurvivalCutPainter({required this.seats, required this.swapAnims});

  final List<_SeatPos> seats;
  final List<_SwapAnim> swapAnims;

  @override
  void paint(Canvas canvas, Size size) {
    // Build swap override map: seat index → current interpolated paint offset
    final swapOverrides = <int, Offset>{};
    for (final sw in swapAnims) {
      final easedT = Curves.easeInOut.transform(sw.t);
      swapOverrides[sw.idxA] =
          Offset.lerp(sw.startA, sw.endA, easedT)!;
      swapOverrides[sw.idxB] =
          Offset.lerp(sw.startB, sw.endB, easedT)!;
    }

    final now = DateTime.now();
    final paint = Paint()..isAntiAlias = true;

    for (int i = 0; i < seats.length; i++) {
      final seat = seats[i];
      final pos = swapOverrides[i] ?? seat.base;

      // Cut-flash overrides all other states for animating circles.
      if (seat.cutFlashStart != null) {
        final ms = now.difference(seat.cutFlashStart!).inMilliseconds;
        if (ms < 200) {
          // Phase 1: solid red hold.
          paint
            ..style = PaintingStyle.fill
            ..color = _kCutFlash;
        } else {
          // Phase 2 (200-600 ms): lerp red to fully transparent.
          final frac = ((ms - 200) / 400.0).clamp(0.0, 1.0);
          final col = Color.lerp(_kCutFlash, Colors.transparent, frac)!;
          paint
            ..style = PaintingStyle.fill
            ..color = col;
        }
        canvas.drawCircle(pos, _kCircleRadius, paint);
        continue;
      }

      // ── Fill transition ──────────────────────────────────────────────────────
      if (seat.fillStart != null) {
        paint
          ..style = PaintingStyle.fill
          ..color = kFg.withValues(alpha: seat.fillAlpha);
        canvas.drawCircle(pos, _kCircleRadius, paint);
        continue;
      }

      // ── Stable states ────────────────────────────────────────────────────────
      switch (seat.state) {
        case _CircleState.empty:
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = _kStrokeWidth
            ..color = kFg;
          canvas.drawCircle(pos, _kCircleRadius, paint);

        case _CircleState.filled:
          paint
            ..style = PaintingStyle.fill
            ..color = kFg;
          canvas.drawCircle(pos, _kCircleRadius, paint);

        case _CircleState.cut:
          // Seat fully eliminated - draw nothing.
          break;
      }
    }
  }

  @override
  bool shouldRepaint(_SurvivalCutPainter old) => true;
}
