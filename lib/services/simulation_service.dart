import 'dart:async';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'rival_mover_service.dart';

typedef ZoneRefresh = void Function(String city);

/// Thin facade over RivalMoverService.
/// State (isRunning, timeLapseComplete, latestEvent) is owned by [SimNotifier]
/// in the Riverpod layer. This service fires callbacks that SimNotifier listens
/// to and mirrors into Riverpod state.
class SimulationService {
  SimulationService._();
  static final SimulationService instance = SimulationService._();

  // ── Callbacks wired by SimNotifier ────────────────────────────────────────
  void Function(bool running)? onRunStateChange;
  VoidCallback? onTimeLapseComplete;
  void Function(String event)? onEvent;

  ZoneRefresh? _onZoneChange;
  Timer? _timeLapseTimer;

  // ── Public API ─────────────────────────────────────────────────────────────

  void start({required ZoneRefresh onZoneChange}) {
    _onZoneChange = onZoneChange;
    _wireMover();
    RivalMoverService.instance.start(speedMultiplier: 1.0);
    // Quiet continuous mode — does not set isRunning so the UI button stays neutral.
    debugPrint('[Sim] started (continuous 1×)');
  }

  void stop() {
    RivalMoverService.instance.stop();
    _timeLapseTimer?.cancel();
    _timeLapseTimer = null;
    onRunStateChange?.call(false);
    debugPrint('[Sim] stopped');
  }

  void resetTimeLapseFlag() {
    // State is owned by SimNotifier — nothing to reset here.
  }

  Future<void> resetWorld() async {
    stop();
    final db = DatabaseService.instance.db;
    await db.delete('zones', where: 'city = ?', whereArgs: ['Valencia']);
    RivalMoverService.instance.clearTails();
    debugPrint('[Sim] world reset — bots will repopulate organically');
  }

  void startTimeLapse({
    required VoidCallback onComplete,
    required void Function(String city) onZoneChange,
  }) {
    _onZoneChange = onZoneChange;
    _wireMover();
    RivalMoverService.instance.start(speedMultiplier: 20.0);
    onRunStateChange?.call(true);

    _timeLapseTimer?.cancel();
    _timeLapseTimer = Timer(const Duration(seconds: 60), () {
      RivalMoverService.instance.setSpeed(1.0);
      onTimeLapseComplete?.call();
      onComplete();
      debugPrint('[Sim] time-lapse complete');
    });
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _wireMover() {
    final mover = RivalMoverService.instance;
    mover.onZoneChange = (city) {
      _onZoneChange?.call(city);
    };
    mover.onEvent = (event) => onEvent?.call(event);
  }
}
