// lib/services/trust/anticheat_orientation_service.dart
// Phase 3 P3-FL — AntiCheat orientation sampling service.
// Reads gyroscope, accumulates GPS samples, submits batch to AntiCheatRepository.
// sensors_plus is exempt from the no-supabase-outside-repos rule (design §3.1).

import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../database/anticheat_repository.dart';
import '../database/repository.dart';

/// Accumulates gyroscope readings and GPS samples during a run session,
/// then submits a scored batch via [AntiCheatRepository].
///
/// Lifecycle: call [start] when the run begins, [addSample] for each GPS fix,
/// [submitBatch] to flush and score, [stop] when the run ends.
class AntiCheatOrientationService {
  AntiCheatOrientationService(this._repo);
  final AntiCheatRepository _repo;

  /// Throttle the gyroscope stream instead of sampling at the platform's
  /// raw hardware rate — the mean orientation summary needs no more than
  /// 5 samples/sec, and an unthrottled stream on a long run accumulates
  /// hundreds of thousands of readings for no anti-cheat benefit.
  static const Duration _kSamplingPeriod = Duration(milliseconds: 200);

  /// Hard cap on buffered gyro readings — bounds memory on a long run
  /// regardless of duration. At 200 ms/sample this is ~30 minutes of data;
  /// oldest readings are dropped first (rolling window).
  static const int _kMaxGyroSamples = 9000;

  final List<GpsSample> _samples = [];
  final List<double> _gyroRx = [], _gyroRy = [], _gyroRz = [];
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  bool _running = false;

  /// Start accumulating sensor data. Clears any previous session data.
  /// Idempotent — safe to call if already running.
  void start() {
    if (_running) return;
    _running = true;
    _samples.clear();
    _gyroRx.clear();
    _gyroRy.clear();
    _gyroRz.clear();
    _gyroSub = gyroscopeEventStream(samplingPeriod: _kSamplingPeriod)
        .listen((e) {
      _gyroRx.add(e.x);
      _gyroRy.add(e.y);
      _gyroRz.add(e.z);
      if (_gyroRx.length > _kMaxGyroSamples) {
        _gyroRx.removeAt(0);
        _gyroRy.removeAt(0);
        _gyroRz.removeAt(0);
      }
    });
  }

  /// Record a GPS sample. No-op if [start] has not been called.
  void addSample(GpsSample s) {
    if (_running) _samples.add(s);
  }

  /// Stop accumulating sensor data and cancel the gyroscope subscription.
  void stop() {
    _gyroSub?.cancel();
    _gyroSub = null;
    _running = false;
  }

  /// Build a [GyroSummary] from the accumulated gyroscope readings.
  ///
  /// Returns null when no gyro readings have been collected.
  GyroSummary? buildGyroSummary() {
    if (_gyroRx.isEmpty) return null;
    double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    return GyroSummary(
      meanRx: mean(_gyroRx),
      meanRy: mean(_gyroRy),
      meanRz: mean(_gyroRz),
    );
  }

  /// Submit all accumulated samples to the anti-cheat scoring edge function.
  ///
  /// Returns the [AntiCheatBatchResult] on success, or null when:
  ///   - No samples have been collected.
  ///   - The repository returns an [Err].
  ///
  /// On success, clears the accumulated GPS + gyro buffers so a caller that
  /// submits periodically during a long run never resends the same data or
  /// grows the buffers unbounded. Does not call [stop] — the caller controls
  /// the session lifecycle, and gyro accumulation continues after a submit.
  Future<AntiCheatBatchResult?> submitBatch({
    required String runId,
    required String playerId,
    AntiCheatTrigger trigger = AntiCheatTrigger.telemetry,
    String? gpsPatternHash,
  }) async {
    if (_samples.isEmpty) return null;
    final result = await _repo.submitBatch(
      runId: runId,
      playerId: playerId,
      samples: List.unmodifiable(_samples),
      gyroSummary: buildGyroSummary(),
      gpsPatternHash: gpsPatternHash,
      trigger: trigger,
    );
    if (result is Ok<AntiCheatBatchResult>) {
      _samples.clear();
      _gyroRx.clear();
      _gyroRy.clear();
      _gyroRz.clear();
      return result.value;
    }
    return null;
  }
}
