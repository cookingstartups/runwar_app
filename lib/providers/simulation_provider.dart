import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/simulation_service.dart';
import 'zones_provider.dart';

final simProvider =
    StateNotifierProvider<SimNotifier, SimState>((ref) => SimNotifier(ref));

class SimState {
  final bool isRunning;
  final bool timeLapseComplete;
  final String? latestEvent;

  const SimState({
    this.isRunning = false,
    this.timeLapseComplete = false,
    this.latestEvent,
  });

  SimState copyWith({
    bool? isRunning,
    bool? timeLapseComplete,
    String? latestEvent,
    bool clearEvent = false,
  }) =>
      SimState(
        isRunning: isRunning ?? this.isRunning,
        timeLapseComplete: timeLapseComplete ?? this.timeLapseComplete,
        latestEvent: clearEvent ? null : (latestEvent ?? this.latestEvent),
      );
}

class SimNotifier extends StateNotifier<SimState> {
  SimNotifier(this._ref) : super(const SimState()) {
    final sim = SimulationService.instance;
    sim.onRunStateChange = (running) => state = state.copyWith(isRunning: running);
    sim.onTimeLapseComplete = () =>
        state = state.copyWith(isRunning: false, timeLapseComplete: true);
    sim.onEvent = (event) => state = state.copyWith(latestEvent: event);
  }

  final Ref _ref;

  void start() {
    SimulationService.instance.start(
      onZoneChange: (city) => _ref.invalidate(zonesProvider(city)),
    );
  }

  void startTimeLapse() {
    state = state.copyWith(isRunning: true, timeLapseComplete: false, clearEvent: true);
    SimulationService.instance.startTimeLapse(
      onComplete: () {},
      onZoneChange: (city) => _ref.invalidate(zonesProvider(city)),
    );
  }

  void stop() => SimulationService.instance.stop();

  void resetTimeLapse() {
    SimulationService.instance.resetTimeLapseFlag();
    state = state.copyWith(isRunning: false, timeLapseComplete: false, clearEvent: true);
  }

  @override
  void dispose() {
    final sim = SimulationService.instance;
    sim.onRunStateChange = null;
    sim.onTimeLapseComplete = null;
    sim.onEvent = null;
    super.dispose();
  }
}
