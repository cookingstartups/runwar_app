// lib/providers/run_simulation_provider.dart
//
// Tester-only run replay simulation. Loads a bundled fixture asset and
// drives it through RunRecorderService's simulation entry points
// (beginSimulation / runSimulationSequence / abortSimulation) so an operator
// can watch a previously recorded run play back live on the map: trail
// drawing, lasso closure, and claim outcome, exactly as a real run would
// produce them.
//
// This provider owns fixture selection and JSON parsing only. It never
// touches _track, _posSub, or any other RunRecorderService internal - all
// position-source isolation lives in the service (see design note above
// RunRecorderService.beginSimulation).

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/run_recorder_service.dart';
import '../utils/runwar_constants.dart';
import 'auth_provider.dart';
import 'cities_provider.dart';

/// One selectable replay fixture bundled as a build asset.
class SimulationFixture {
  const SimulationFixture({
    required this.assetPath,
    required this.label,
    required this.city,
  });

  final String assetPath;
  final String label;
  final String city;
}

/// Fixtures shipped with the debug build. Add an entry here (and the asset
/// under assets/fixtures/ + pubspec.yaml) to make a new recorded session
/// selectable from the simulation control.
const List<SimulationFixture> kBundledSimulationFixtures = [
  SimulationFixture(
    assetPath: 'assets/fixtures/session-2026-07-18-valencia.json',
    label: 'Valencia session (2026-07-18)',
    city: 'valencia',
  ),
];

enum SimulationStatus { idle, running, done, aborted }

class RunSimulationState {
  const RunSimulationState({
    this.status = SimulationStatus.idle,
    this.fixtureLabel,
    this.emittedCount = 0,
    this.totalCount = 0,
    this.error,
  });

  final SimulationStatus status;
  final String? fixtureLabel;
  final int emittedCount;
  final int totalCount;
  final String? error;

  bool get isActive => status == SimulationStatus.running;

  RunSimulationState copyWith({
    SimulationStatus? status,
    String? fixtureLabel,
    int? emittedCount,
    int? totalCount,
    String? error,
  }) {
    return RunSimulationState(
      status: status ?? this.status,
      fixtureLabel: fixtureLabel ?? this.fixtureLabel,
      emittedCount: emittedCount ?? this.emittedCount,
      totalCount: totalCount ?? this.totalCount,
      error: error,
    );
  }
}

class RunSimulationNotifier extends StateNotifier<RunSimulationState> {
  RunSimulationNotifier(this._ref) : super(const RunSimulationState());

  final Ref _ref;

  /// Loads [fixture], starts a simulation session, and plays every event
  /// through RunRecorderService. Accelerated timing (the default) divides
  /// each fix's original inter-fix delay by [kSimulationAccelerationMultiplier];
  /// real-time timing replays the original wall-clock spacing unscaled.
  Future<void> start(SimulationFixture fixture, {bool accelerated = true}) async {
    if (state.status == SimulationStatus.running) return;
    final svc = RunRecorderService.instance;
    try {
      final raw = await rootBundle.loadString(fixture.assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final rawEvents = (json['events'] as List).cast<Map<String, dynamic>>();
      final events = rawEvents
          .map((e) => SimulationFixEvent(
                t: DateTime.parse(e['t'] as String),
                type: e['type'] as String,
                data: (e['data'] as Map<String, dynamic>?) ?? const {},
              ))
          .toList();

      final userId = _ref.read(authProvider).user?['id'] as String?;
      if (userId == null) {
        state = state.copyWith(
          status: SimulationStatus.aborted,
          error: 'Not signed in',
        );
        return;
      }
      svc.setActiveUser(userId);
      final slugs = _ref.read(joinedCitySlugsProvider(userId)).valueOrNull;
      svc.activeCity =
          (slugs != null && slugs.isNotEmpty) ? slugs.first : fixture.city;

      await svc.beginSimulation();
      state = RunSimulationState(
        status: SimulationStatus.running,
        fixtureLabel: fixture.label,
        totalCount: events.length,
      );

      await svc.runSimulationSequence(
        events,
        multiplier: accelerated ? kSimulationAccelerationMultiplier : 1.0,
      );

      if (state.status == SimulationStatus.running) {
        state = state.copyWith(status: SimulationStatus.done);
      }
    } catch (e) {
      state = state.copyWith(status: SimulationStatus.aborted, error: e.toString());
    }
  }

  /// Immediately aborts an active simulation: discards the in-progress
  /// synthetic track, dispatches no claim, and returns the recorder to idle.
  Future<void> abort() async {
    if (state.status != SimulationStatus.running) return;
    await RunRecorderService.instance.abortSimulation();
    state = state.copyWith(status: SimulationStatus.aborted);
  }

  /// Resets the panel back to idle so a fresh fixture can be picked.
  void reset() {
    state = const RunSimulationState();
  }
}

final runSimulationProvider =
    StateNotifierProvider<RunSimulationNotifier, RunSimulationState>(
  (ref) => RunSimulationNotifier(ref),
);
