// lib/widgets/simulation_control_panel.dart
//
// Tester-only run replay simulation control. Rendered by MapScreen only
// when kDebugMode is true AND the signed-in player's is_tester flag is set
// (see isTesterProvider) - never visible to an ordinary player, even on a
// debug build.
//
// Visually and positionally distinct from the real Start/Stop run FAB so it
// can never be tapped by accident: a small "SIM" chip placed in the top
// safe area, in the sea-blue accent color rather than the FAB's orange.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/run_simulation_provider.dart';
import '../theme.dart';

/// Small always-available launcher chip. Opens the fixture picker sheet.
class SimulationLauncherChip extends ConsumerWidget {
  const SimulationLauncherChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(runSimulationProvider);
    if (simState.isActive) return const SimulationActiveBanner();

    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, right: 12),
          child: GestureDetector(
            onTap: () => _openPicker(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kSurface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kSea.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.science_outlined, color: kSea, size: 14),
                  const SizedBox(width: 4),
                  Text('SIM', style: monoStyle(size: 10, color: kSea)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openPicker(BuildContext context, WidgetRef ref) {
    if (kBundledSimulationFixtures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No replay fixtures found')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      builder: (sheetContext) => _FixturePickerSheet(ref: ref),
    );
  }
}

class _FixturePickerSheet extends StatefulWidget {
  const _FixturePickerSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_FixturePickerSheet> createState() => _FixturePickerSheetState();
}

class _FixturePickerSheetState extends State<_FixturePickerSheet> {
  bool _accelerated = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('REPLAY SIMULATION', style: displayStyle(size: 20, color: kSea)),
            const SizedBox(height: 4),
            Text(
              'Plays a recorded run through the real trail, lasso and claim '
              'pipeline on this device. Tester-only diagnostic tool.',
              style: bodyStyle(color: kFgMuted),
            ),
            const SizedBox(height: 16),
            for (final fixture in kBundledSimulationFixtures)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(fixture.label, style: bodyStyle(color: kFg)),
                subtitle: Text(fixture.city, style: monoStyle(color: kFgFaint)),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kSea),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.ref
                        .read(runSimulationProvider.notifier)
                        .start(fixture, accelerated: _accelerated);
                  },
                  child: const Text('START'),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: kSea,
              value: _accelerated,
              onChanged: (v) => setState(() => _accelerated = v),
              title: Text('Accelerated timing', style: bodyStyle(color: kFg)),
              subtitle: Text(
                _accelerated
                    ? 'Fast playback for iterative testing'
                    : 'Real-time playback for animation timing checks',
                style: monoStyle(color: kFgFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Persistent banner shown for the entire duration a simulation is active.
/// Distinct from the normal recording-in-progress notification so the
/// operator can never mistake a simulation for a live real run.
class SimulationActiveBanner extends ConsumerWidget {
  const SimulationActiveBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(runSimulationProvider);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kSea.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.science_outlined, color: kBg, size: 16),
              const SizedBox(width: 8),
              Text(
                'SIMULATION - ${simState.fixtureLabel ?? ''} '
                '(${simState.emittedCount}/${simState.totalCount})',
                style: monoStyle(size: 11, color: kBg),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => ref.read(runSimulationProvider.notifier).abort(),
                child: Text('ABORT', style: monoStyle(size: 11, color: kBg).copyWith(
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
