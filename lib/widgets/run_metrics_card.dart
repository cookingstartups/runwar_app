import 'package:flutter/material.dart';

import '../models/run_summary.dart';
import '../models/unit_system.dart';
import '../theme.dart';
import 'elevation_silhouette_painter.dart';
import 'valencia_button.dart';

/// Presentational post-run recap card. Takes a fully-built [RunSummary] and
/// never reads live recorder state directly, so it is reusable wherever a
/// completed session's metrics need to be shown.
///
/// Fixed render order, no exceptions: (1) territory-claimed hero folding the
/// aggregate zone count into itself, (2) the distance/duration/avg-pace
/// triad over a decorative elevation background, (3) the reward line, (4)
/// the Share/Close CTA row.
class RunMetricsCard extends StatelessWidget {
  const RunMetricsCard({
    required this.summary,
    required this.onClosePressed,
    this.onSharePressed,
    this.unitSystem = UnitSystem.metric,
    super.key,
  });

  final RunSummary summary;
  final VoidCallback onClosePressed;
  final VoidCallback? onSharePressed;
  final UnitSystem unitSystem;

  @override
  Widget build(BuildContext context) {
    final areaKm2 = summary.totalAreaM2 / 1e6;
    final zoneCount = summary.claimedZoneCount;
    final zoneWord = zoneCount == 1 ? 'zone' : 'zones';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // (1) Territory-claimed hero - aggregate only, no separate
          // outcome-headline text, no per-zone breakdown list.
          Text(
            '${areaKm2.toStringAsFixed(1)} km2 · $zoneCount $zoneWord claimed',
            style: displayStyle(size: 26),
          ),
          const SizedBox(height: 20),

          // (2) Distance | duration | avg-pace triad, over a decorative
          // elevation-profile background built from this session's real
          // altitude samples (absent entirely when too few samples exist).
          SizedBox(
            height: 72,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: ElevationSilhouettePainter(
                      samples: summary.altitudeSamples,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _metric('DISTANCE', _formatDistance(summary.distanceM)),
                    _metric('DURATION', _formatDuration(summary.duration)),
                    _metric('AVG PACE', _formatPace(summary.avgPacePerKm)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // (3) Reward line.
          Text(
            '+${summary.rewardCreditsPerHour.toStringAsFixed(1)} credits/hr',
            style: bodyStyle(size: 15, color: kAccent2),
          ),
          const SizedBox(height: 24),

          // (4) Share / Close CTA row - always two distinct buttons. Share
          // always renders even when disabled (onSharePressed null).
          Row(
            children: [
              Expanded(
                child: ValenciaButton(
                  label: 'SHARE',
                  onPressed: onSharePressed,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValenciaButton(
                  label: 'CLOSE',
                  onPressed: onClosePressed,
                  variant: ValenciaButtonVariant.ghost,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: monoStyle(size: 10)),
        const SizedBox(height: 4),
        Text(value, style: displayStyle(size: 18)),
      ],
    );
  }

  String _formatDistance(double distanceM) {
    if (unitSystem == UnitSystem.metric) {
      return '${(distanceM / 1000).toStringAsFixed(2)} km';
    }
    return '${(distanceM / 1609.344).toStringAsFixed(2)} mi';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _formatPace(Duration? pace) {
    final unitLabel = unitSystem == UnitSystem.metric ? 'km' : 'mi';
    if (pace == null) return '--:--/$unitLabel';
    final paceSeconds = unitSystem == UnitSystem.metric
        ? pace.inSeconds
        : (pace.inSeconds * 1.609344).round();
    final minutes = paceSeconds ~/ 60;
    final seconds = (paceSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds/$unitLabel';
  }
}
