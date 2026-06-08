import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/mission_provider.dart';
import '../theme.dart';

/// Full-screen dark briefing for Mission 1: Claim Your First Territory.
///
/// Shown by _RouteGuard (main.dart Gate 5a) when a new player has no zones
/// and has not yet completed the first mission stamp.
class FirstMissionBriefingScreen extends ConsumerWidget {
  const FirstMissionBriefingScreen({super.key});

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
              // Headline — Bebas Neue, large
              Text(
                'CLAIM YOUR\nFIRST TERRITORY',
                style: displayStyle(size: 52),
              ),
              const SizedBox(height: 20),
              // Descriptor
              Text(
                'Run a loop around any area.\nMake it yours.',
                style: bodyStyle(size: 16, color: kFgMuted),
              ),
              const Spacer(flex: 2),
              // CTA — accent orange
              ElevatedButton(
                onPressed: () {
                  ref.read(mission1BriefingAcceptedProvider.notifier).state =
                      true;
                },
                child: const Text('ACCEPT MISSION'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
