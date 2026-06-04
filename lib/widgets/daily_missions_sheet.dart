import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_mission.dart';
import '../providers/daily_missions_provider.dart';
import '../services/telemetry_service.dart';
import '../theme.dart';

/// Bottom sheet listing today's missions for [userId].
/// Watches [todaysMissionsProvider] and renders a card per mission with a
/// [LinearProgressIndicator], reward chip, and a checkmark when complete.
class DailyMissionsSheet extends ConsumerStatefulWidget {
  const DailyMissionsSheet({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<DailyMissionsSheet> createState() => _DailyMissionsSheetState();
}

class _DailyMissionsSheetState extends ConsumerState<DailyMissionsSheet> {
  bool _telemetryFired = false;

  @override
  Widget build(BuildContext context) {
    final missionsAsync = ref.watch(todaysMissionsProvider(widget.userId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
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
            Text('DAILY MISSIONS', style: monoStyle(size: 11, color: kFgMuted)),
            const SizedBox(height: 12),
            missionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(
                    color: kAccent,
                    strokeWidth: 2,
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Could not load missions',
                  style: bodyStyle(size: 14, color: kDanger),
                ),
              ),
              data: (missions) {
                // Fire one telemetry event per visible mission card (once).
                if (!_telemetryFired && missions.isNotEmpty) {
                  _telemetryFired = true;
                  final streak = ref
                      .read(dailyStreakProvider(widget.userId))
                      .valueOrNull
                      ?.current ?? 0;
                  for (final m in missions) {
                    TelemetryService.instance.logEvent(
                      'mission_shown',
                      props: {'slug': m.slug, 'streak': streak},
                    );
                  }
                }
                if (missions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No missions today',
                      style: bodyStyle(size: 14, color: kFgMuted),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final mission in missions) ...[
                      _MissionCard(mission: mission, userId: widget.userId),
                      const SizedBox(height: 10),
                    ],
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

/// A single mission card with title, progress bar and reward chip.
class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission, required this.userId});

  final DailyMission mission;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final isDone = mission.isComplete;
    final progressColor = isDone ? kFgMuted : kAccent;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDone ? kBorder : kAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mission.slug
                            .replaceAll('_', ' ')
                            .toUpperCase(),
                        style: monoStyle(
                          size: 10,
                          color: isDone ? kFgMuted : kFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RewardChip(
                      credits: mission.rewardCredits,
                      power: mission.rewardPower,
                      isDone: isDone,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: mission.fraction,
                  backgroundColor:
                      progressColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDone
                        ? kFgMuted
                        : kAccent,
                  ),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 4),
                Text(
                  '${mission.progress} / ${mission.target}',
                  style: monoStyle(size: 9, color: kFgMuted),
                ),
              ],
            ),
          ),
          if (isDone) ...[
            const SizedBox(width: 12),
            const Icon(
              Icons.check_circle_outline,
              color: kFgMuted,
              size: 20,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small pill showing "+N cr" (and optional power name).
class _RewardChip extends StatelessWidget {
  const _RewardChip({
    required this.credits,
    required this.power,
    required this.isDone,
  });

  final int credits;
  final String? power;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final label = power != null ? '+$credits cr · $power' : '+$credits cr';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDone
            ? kSurface
            : kAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDone ? kBorder : kAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: monoStyle(
          size: 9,
          color: isDone ? kFgMuted : kAccent,
        ),
      ),
    );
  }
}
