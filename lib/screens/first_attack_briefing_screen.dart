import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/mission_provider.dart';
import '../theme.dart';

/// Full-screen dark briefing for Mission 2: Attack a Rival Zone.
///
/// [botZoneId] is the zone ID returned by BotSpawnerService.checkOrSpawn —
/// passed through to MapScreen so the overlay can locate the target.
class FirstAttackBriefingScreen extends ConsumerWidget {
  const FirstAttackBriefingScreen({
    super.key,
    required this.botZoneId,
  });

  final String botZoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Mission label
              Text(
                'MISSION 2 / 2',
                style: monoStyle(size: 11, color: kFgMuted),
              ),
              const SizedBox(height: 16),
              // Headline
              Text(
                'RIVAL\nDETECTED',
                style: displayStyle(size: 52),
              ),
              const SizedBox(height: 20),
              // Descriptor
              Text(
                'A ConquerBot has claimed territory near you.\nTake it back.',
                style: bodyStyle(size: 16, color: kFgMuted),
              ),
              const Spacer(flex: 2),
              // CTA
              ElevatedButton(
                onPressed: () {
                  ref.read(mission2BriefingAcceptedProvider.notifier).state =
                      true;
                },
                child: const Text('ENTER THE WAR'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
