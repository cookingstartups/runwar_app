import 'package:flutter/material.dart';

import '../models/mission_step.dart';
import '../theme.dart';
import 'map_screen.dart';

/// Full-screen dark briefing for Mission 1: Claim Your First Territory.
///
/// Shown by _RouteGuard (main.dart Gate 5a) when a new player has no zones
/// and has not yet completed the first mission stamp.
class FirstMissionBriefingScreen extends StatelessWidget {
  const FirstMissionBriefingScreen({super.key});

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
              // Mission label — small-caps, muted
              Text(
                'MISSION 1 / 2',
                style: monoStyle(size: 11, color: kFgMuted),
              ),
              const SizedBox(height: 16),
              // Headline — Bebas Neue, large
              Text(
                'CLAIM YOUR\nFIRST TERRITORY',
                style: displayStyle(size: 52),
              ),
              const SizedBox(height: 20),
              // Descriptor
              Text(
                'Run a loop around any unclaimed area.\nMake it yours.',
                style: bodyStyle(size: 16, color: kFgMuted),
              ),
              const Spacer(flex: 2),
              // CTA — accent orange
              ElevatedButton(
                onPressed: () => _onAccept(context),
                child: const Text('ACCEPT MISSION  →'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _onAccept(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            const MapScreen(missionStep: MissionStep.mission1Claim),
      ),
    );
  }
}
