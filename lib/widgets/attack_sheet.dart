// lib/widgets/attack_sheet.dart
//
// Bottom sheet shown when the current user taps a rival zone.
// Design.md §4 AttackSheet spec.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database/models/zone.dart';
import '../providers/zones_provider.dart';
import '../providers/run_recorder_provider.dart';
import 'dispute_countdown_label.dart';

/// Bottom sheet for attacking a rival zone.
///
/// - ConsumerWidget taking [Zone zone].
/// - Reads owner display name via profileCacheProvider(zone.ownerId).
/// - Shows attack window copy: level × 20 minutes.
/// - "Start a run" CTA: pops the sheet then starts a run recording.
/// - Shows DisputeCountdownLabel when zone.status == ZoneStatus.disputed.
class AttackSheet extends ConsumerWidget {
  const AttackSheet({super.key, required this.zone});

  final Zone zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerAsync = ref.watch(profileCacheProvider(zone.ownerId));
    final level = zone.influenceLevel;
    final windowMinutes = level * 20;

    final ownerName = ownerAsync.when(
      data: (profile) =>
          profile?['username'] as String? ?? 'Unknown runner',
      loading: () => '…',
      error: (_, __) => 'Unknown runner',
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: zone owner label then standalone owner name (test contract).
            Text(
              'Zone owned by',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              ownerName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),

            // Dispute countdown — only when disputed (mount-on-status-change contract).
            if (zone.status == ZoneStatus.disputed) ...[
              DisputeCountdownLabel(zoneId: zone.id),
              const SizedBox(height: 8),
            ],

            // Attack window copy (verbatim from design.md §4 + Team Lead brief).
            Text(
              'Level $level zone — attack window will be $windowMinutes minutes '
              '(20 min × level).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'If you run through this zone and close a lasso before the timer '
              'expires, you capture it. If the timer expires without a successful '
              'lasso, the defender wins and their zone gains +1 influence.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 20),

            // Primary CTA.
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(runRecorderProvider.notifier).start();
                },
                child: const Text('Start a run'),
              ),
            ),
            const SizedBox(height: 8),

            // Secondary CTA.
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
