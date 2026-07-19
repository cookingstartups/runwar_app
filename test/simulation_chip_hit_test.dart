// test/simulation_chip_hit_test.dart
//
// Coverage for the tester-only SIM chip: it must be reachable by a real
// tap, not just callable directly. This mirrors the exact Stack composition
// MapScreen uses when a mission is active (mapBody underneath,
// MissionModeOverlay's full-width top banner in the middle, the chip on
// top). Nothing here previously covered a tap going through real hit
// testing - the service-level simulation tests only ever called the
// provider directly - so this closes that gap even though the composition
// itself checked out as correct on inspection.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/models/mission_step.dart';
import 'package:runwar_app/services/run_recorder_service.dart';
import 'package:runwar_app/widgets/mission_mode_overlay.dart';
import 'package:runwar_app/widgets/simulation_control_panel.dart';

/// Stand-in for the interactive map body: a full-bleed opaque gesture
/// surface, exactly like the real FlutterMap underneath the chip.
class _FakeMapBody extends StatelessWidget {
  const _FakeMapBody({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(color: Colors.black),
      ),
    );
  }
}

void main() {
  testWidgets(
    'tapping the SIM chip through a real hit test opens the fixture picker',
    (tester) async {
      var mapTaps = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  Stack(
                    children: [
                      _FakeMapBody(onTap: () => mapTaps++),
                      const MissionModeOverlay(
                        missionStep: MissionStep.mission1Claim,
                        isRecording: false,
                      ),
                    ],
                  ),
                  const SimulationLauncherChip(),
                ],
              ),
            ),
          ),
        ),
      );
      // MissionModeOverlay drives a repeating pulse animation that never
      // settles, so pump a fixed frame instead of pumpAndSettle.
      await tester.pump();

      // Sanity: the chip is actually on screen before we tap it.
      expect(find.text('SIM'), findsOneWidget);

      await tester.tap(find.text('SIM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mapTaps, 0,
          reason: 'the tap must land on the chip, not fall through to the '
              'map body underneath it');
      expect(find.text('REPLAY SIMULATION'), findsOneWidget,
          reason: 'a real tap on the SIM chip must open the fixture picker '
              'sheet, not just a directly-invoked callback');
    },
  );

  testWidgets(
    'the SIM chip is disabled while a real run is recording and tapping it '
    'never opens the fixture picker',
    (tester) async {
      addTearDown(
        () => RunRecorderService.instance.stateNotifier.value = RecorderState.idle,
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: SimulationLauncherChip(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Drive the shared recorder service into the same state a live real
      // run leaves it in, once the provider tree already exists so its
      // listener picks up the change.
      RunRecorderService.instance.stateNotifier.value = RecorderState.recording;
      await tester.pump();

      expect(find.text('SIM'), findsOneWidget);

      await tester.tap(find.text('SIM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('REPLAY SIMULATION'), findsNothing,
          reason: 'the fixture picker must never open while a real run is '
              'recording - this is exactly the dead end that misled the '
              'operator');
      expect(
        find.text('Stop the current run before starting a simulation'),
        findsOneWidget,
        reason: 'tapping the disabled chip must surface a message '
            'explaining why, not fail silently',
      );
    },
  );
}
