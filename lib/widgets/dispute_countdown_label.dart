// lib/widgets/dispute_countdown_label.dart
//
// Countdown label for an active zone dispute.
// Design.md §4 — ConsumerWidget reading disputeCountdownProvider(zoneId).
// Mount-on-status-change contract: only mounted inside disputed branch of
// polygon overlay loop in map_screen.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dispute_countdown_provider.dart';

/// Displays the remaining time on a dispute countdown.
///
/// Reads [disputeCountdownProvider(zoneId)] which returns a Stream<Duration>:
/// - No data / error → SizedBox.shrink() (no flicker)
/// - Duration.zero (expired or terminal) → SizedBox.shrink()
/// - Positive duration → formatted mm:ss or h:mm:ss text
///
/// Contract: only mounted when zone.status == ZoneStatus.disputed.
/// The provider auto-disposes when this widget unmounts.
class DisputeCountdownLabel extends ConsumerWidget {
  const DisputeCountdownLabel({super.key, required this.zoneId});

  final String zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(disputeCountdownProvider(zoneId));
    return StreamBuilder<Duration>(
      stream: stream,
      builder: (context, snapshot) {
        final remaining = snapshot.data;
        if (remaining == null || remaining <= Duration.zero) {
          return const SizedBox.shrink();
        }
        return _CountdownText(remaining: remaining);
      },
    );
  }
}

class _CountdownText extends StatelessWidget {
  const _CountdownText({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _format(remaining),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Format duration as mm:ss when < 1h, otherwise h:mm:ss.
  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
