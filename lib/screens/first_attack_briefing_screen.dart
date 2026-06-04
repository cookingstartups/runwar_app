import 'package:flutter/material.dart';

import '../models/mission_step.dart';
import '../theme.dart';
import 'map_screen.dart';

/// Full-screen dark briefing for Mission 2: Attack a Rival Zone.
///
/// [botZoneId] is the zone ID returned by BotSpawnerService.checkOrSpawn —
/// passed through to MapScreen so the overlay can locate the target.
class FirstAttackBriefingScreen extends StatelessWidget {
  const FirstAttackBriefingScreen({
    super.key,
    required this.botZoneId,
  });

  final String botZoneId;

  @override
  Widget build(BuildContext context) {
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
                onPressed: () => _onEnter(context),
                child: const Text('ENTER THE WAR  →'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _onEnter(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MapScreen(
          missionStep: MissionStep.mission2Attack,
          botZoneId: botZoneId,
        ),
      ),
    );
  }
}
