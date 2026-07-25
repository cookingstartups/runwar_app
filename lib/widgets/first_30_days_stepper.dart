// lib/widgets/first_30_days_stepper.dart
//
// Persistent HUD stepper for the first-30-days curriculum (rw_app-T0593).
// Implements the operator's chosen hybrid design ("Option E"):
// ~/AIOS/infra/meta/specs/runwar/first-30-days-missions/mockups/stepper-mockup-v1.html#e
//
//   - Collapsed/default: Variant A's minimalist dot row.
//   - Tap: opens a Variant-B-styled bottom sheet (full mission list, the
//     current/active mission highlighted).
//   - While the sheet is open: the HUD element swaps from the dot row to
//     Variant C's segmented progress bar (day / mission counter) for the
//     duration, reverting to the dot row the moment the sheet closes.
//
// Sits in MapScreen's top-right HUD, directly below StreakChip/CreditsChip.
// Consumes firstThirtyDaysMissionsProvider (rw_app-T0593 PR #121/#122) —
// always render Day30MissionState.displayTitle/displayTeaches, never the
// raw mission.title/teaches, since a non-bespoke ("resolvedDaily") entry's
// real content is only known once resolvedMission is populated.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/day30_mission.dart';
import '../providers/first_thirty_days_missions_provider.dart';
import '../theme.dart';

/// The collapsed<->expanded HUD element. Tapping it opens
/// [First30DaysMissionsSheet]; while that sheet is open this widget renders
/// the Variant C segmented bar instead of the Variant A dot row.
class First30DaysStepper extends ConsumerStatefulWidget {
  const First30DaysStepper({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<First30DaysStepper> createState() =>
      _First30DaysStepperState();
}

class _First30DaysStepperState extends ConsumerState<First30DaysStepper> {
  bool _sheetOpen = false;

  @override
  Widget build(BuildContext context) {
    final missionsAsync =
        ref.watch(firstThirtyDaysMissionsProvider(widget.userId));

    return missionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (states) {
        if (states.isEmpty) return const SizedBox.shrink();
        return GestureDetector(
          key: const Key('first30_stepper_tap_target'),
          // opaque — the collapsed dot row only paints a small chip near the
          // right edge of this HUD element's full-width bounding box (via
          // the Align below); without opaque behavior the default
          // deferToChild hit-testing would only register taps landing
          // exactly on that small chip, not anywhere in its tap area.
          // IntrinsicHeight keeps that full-width tap target sized to the
          // actual chip/bar content instead of expanding to fill all
          // available vertical space inside MapScreen's Stack (which would
          // otherwise swallow map gestures below the HUD).
          behavior: HitTestBehavior.opaque,
          onTap: () => _openSheet(states),
          child: SizedBox(
            width: double.infinity,
            child: IntrinsicHeight(
              child: _sheetOpen
                  ? _SegmentedBar(states: states)
                  : Align(
                      alignment: Alignment.centerRight,
                      child: _DotRow(states: states),
                    ),
            ),
          ),
        );
      },
    );
  }

  void _openSheet(List<Day30MissionState> states) {
    setState(() => _sheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => First30DaysMissionsSheet(userId: widget.userId),
    ).then((_) {
      // This widget lives inside MapScreen (below the auth/onboarding
      // route guard), not one of the guard-replaced screens — a plain
      // `mounted` check here guards the usual "setState after dispose"
      // case, not the route-guard snackbar anti-pattern.
      if (mounted) setState(() => _sheetOpen = false);
    });
  }
}

// ── Variant A — minimalist dot row (collapsed/default) ──────────────────────

class _DotRow extends StatelessWidget {
  const _DotRow({required this.states});

  final List<Day30MissionState> states;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('first30_stepper_dot_row'),
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < states.length; i++) ...[
              _Dot(state: states[i]),
              if (i != states.length - 1) const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final Day30MissionState state;

  @override
  Widget build(BuildContext context) {
    if (state.isCurrent) {
      return Container(
        width: 14,
        height: 5,
        decoration: BoxDecoration(
          color: kAccent2,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: kAccent2.withValues(alpha: 0.25),
              blurRadius: 0,
              spreadRadius: 2,
            ),
          ],
        ),
      );
    }
    if (state.completed) {
      return Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
      );
    }
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kFg.withValues(alpha: 0.16), width: 1.5),
      ),
    );
  }
}

// ── Variant C — segmented progress bar (while the sheet is open) ───────────

class _SegmentedBar extends StatelessWidget {
  const _SegmentedBar({required this.states});

  final List<Day30MissionState> states;

  @override
  Widget build(BuildContext context) {
    final total = states.length;
    final completed = states.where((s) => s.completed).length;
    final currentIdx = states.indexWhere((s) => s.isCurrent);
    final activeDay = currentIdx != -1
        ? states[currentIdx].mission.day
        : (states.isNotEmpty ? states.last.mission.day : 0);
    final positionLabel = currentIdx != -1 ? currentIdx + 1 : completed;

    return Container(
      key: const Key('first30_stepper_segmented_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DAY $activeDay', style: monoStyle(size: 9, color: kFgMuted)),
              Text(
                'MISSION $positionLabel/$total',
                style: monoStyle(size: 9, color: kAccent2),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              for (var i = 0; i < states.length; i++) ...[
                Expanded(child: _Segment(state: states[i])),
                if (i != states.length - 1) const SizedBox(width: 3),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.state});

  final Day30MissionState state;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (state.isCurrent) {
      color = kAccent2;
    } else if (state.completed) {
      color = kAccent;
    } else {
      color = kFg.withValues(alpha: 0.16);
    }
    return Container(
      height: 5,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    );
  }
}

// ── Variant B — bottom sheet (full mission list) ────────────────────────────

/// Bottom sheet listing the full first-30-days curriculum for [userId],
/// with the current/active mission highlighted. Mirrors the visual
/// convention of [DailyMissionsSheet].
class First30DaysMissionsSheet extends ConsumerWidget {
  const First30DaysMissionsSheet({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(firstThirtyDaysMissionsProvider(userId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kFgFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            missionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: kAccent, strokeWidth: 2),
                ),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Could not load missions',
                  style: bodyStyle(size: 14, color: kDanger),
                ),
              ),
              data: (states) {
                if (states.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('No missions yet', style: bodyStyle(size: 14, color: kFgMuted)),
                  );
                }
                final completed = states.where((s) => s.completed).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('30-DAY MISSIONS', style: monoStyle(size: 11, color: kFgMuted)),
                        Text(
                          '$completed / ${states.length}',
                          style: monoStyle(size: 11, color: kAccent2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final state in states) ...[
                              _MissionRow(state: state),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.state});

  final Day30MissionState state;

  @override
  Widget build(BuildContext context) {
    final isCurrent = state.isCurrent;
    final isDone = state.completed;

    return Container(
      key: isCurrent ? const Key('first30_sheet_active_row') : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isCurrent ? kAccent2.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent ? kAccent2.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? kAccent
                  : (isCurrent ? kAccent2 : Colors.transparent),
              border: (!isDone && !isCurrent)
                  ? Border.all(color: kFg.withValues(alpha: 0.16), width: 1.5)
                  : null,
            ),
            child: isDone
                ? const Icon(Icons.check, size: 12, color: kBg)
                : Text(
                    state.mission.slot.toString(),
                    style: monoStyle(size: 9, color: isCurrent ? kBg : kFgFaint),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.displayTitle, style: bodyStyle(size: 12.5, color: kFg)),
                Text(
                  isCurrent
                      ? 'Day ${state.mission.day} · in progress'
                      : 'Day ${state.mission.day}',
                  style: monoStyle(size: 9, color: kFgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
