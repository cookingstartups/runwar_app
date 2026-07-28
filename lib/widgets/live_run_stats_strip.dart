import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../geo/lasso.dart' show trackDistanceM;
import '../providers/run_recorder_provider.dart';
import '../services/run_recorder_service.dart';
import '../theme.dart';

/// Live-run HUD strip showing distance and elapsed time only. Never shows
/// pace or speed - instantaneous speed is acceptable comet-tail noise but
/// reads as broken when displayed as a number; average pace is a post-run
/// figure shown on the summary screen instead.
class LiveRunStatsStrip extends ConsumerWidget {
  const LiveRunStatsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild on every accepted GPS point so distance/elapsed stay live.
    ref.watch(runRecorderTrackVersionProvider);

    final svc = RunRecorderService.instance;
    final distanceM = trackDistanceM(svc.track);
    final startedAt = svc.startedAt;
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().toUtc().difference(startedAt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(distanceM / 1000).toStringAsFixed(1)} km',
            style: const TextStyle(
              color: kFg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatElapsed(elapsed),
            style: const TextStyle(
              color: kFgMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(Duration elapsed) {
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
