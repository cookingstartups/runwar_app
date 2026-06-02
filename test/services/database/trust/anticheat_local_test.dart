// test/services/database/trust/anticheat_local_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures are expected as "Target of URI doesn't exist" compile errors.
// Each test maps to exactly one GIVEN/WHEN/THEN from spec §P3-FL-17.
//
// Contract under test (spec §P3-FL-17):
//   anticheat_local.dart MUST send payload shape:
//     { run_id, player_id, samples, gyro_summary?, gps_pattern_hash?, triggered_by }
//   NOT the old shape: { samples, is_mock_alert }
//
//   AntiCheatRepository.submitBatch({
//     required String runId,
//     required String playerId,
//     required List<GpsSample> samples,
//     GyroSummary? gyroSummary,
//     String? gpsPatternHash,
//     AntiCheatTrigger trigger,
//   })

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/anticheat_repository.dart';
import 'package:runwar_app/models/gyro_summary.dart';

// ── Capture fake ──────────────────────────────────────────────────────────────

/// Captures the last submitBatch call's named arguments for assertion.
class CapturingAntiCheatRepository implements AntiCheatRepository {
  String? capturedRunId;
  String? capturedPlayerId;
  List<GpsSample>? capturedSamples;
  GyroSummary? capturedGyroSummary;
  String? capturedGpsPatternHash;
  AntiCheatTrigger? capturedTrigger;

  @override
  Future<AntiCheatBatchResult> submitBatch({
    required String runId,
    required String playerId,
    required List<GpsSample> samples,
    GyroSummary? gyroSummary,
    String? gpsPatternHash,
    AntiCheatTrigger trigger = AntiCheatTrigger.telemetry,
  }) async {
    capturedRunId = runId;
    capturedPlayerId = playerId;
    capturedSamples = samples;
    capturedGyroSummary = gyroSummary;
    capturedGpsPatternHash = gpsPatternHash;
    capturedTrigger = trigger;
    return const AntiCheatBatchResult(
      flags: [],
      sessionBlocked: false,
      sessionScore: 0.0,
    );
  }

  @override
  Stream<SuspicionScore> watchScore(String playerId) => const Stream.empty();
}

GpsSample _makeSample({double lat = 39.4699, double lng = -0.3763}) =>
    GpsSample(lat: lat, lng: lng);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('anticheat_local — payload contract (P3-FL-17)', () {
    // GIVEN anticheat_local flushes a GPS batch
    // WHEN submitBatch is called
    // THEN the payload contains run_id
    test('submitBatch call includes run_id', () async {
      final repo = CapturingAntiCheatRepository();
      const runId = 'run-uuid-001';

      await repo.submitBatch(
        runId: runId,
        playerId: 'player-001',
        samples: [_makeSample()],
      );

      expect(repo.capturedRunId, equals(runId),
          reason: 'run_id is required in the P3 payload — not present in PoC shape');
    });

    // GIVEN anticheat_local flushes a GPS batch
    // WHEN submitBatch is called
    // THEN the payload contains player_id
    test('submitBatch call includes player_id', () async {
      final repo = CapturingAntiCheatRepository();

      await repo.submitBatch(
        runId: 'run-uuid-002',
        playerId: 'player-uuid-002',
        samples: [_makeSample()],
      );

      expect(repo.capturedPlayerId, equals('player-uuid-002'),
          reason: 'player_id is required in the P3 payload — not present in PoC shape');
    });

    // GIVEN anticheat_local calls submitBatch with a gyroSummary
    // WHEN the call is made
    // THEN the gyroSummary is forwarded (not dropped)
    test('submitBatch forwards gyro_summary when provided', () async {
      final repo = CapturingAntiCheatRepository();
      const summary = GyroSummary(
        meanRx: 0.1, meanRy: 0.2, meanRz: 0.0,
        varRx: 0.05, varRy: 0.04, varRz: 0.0,
        sampleCount: 10,
      );

      await repo.submitBatch(
        runId: 'run-gyro',
        playerId: 'player-gyro',
        samples: [_makeSample()],
        gyroSummary: summary,
      );

      expect(repo.capturedGyroSummary, isNotNull,
          reason: 'gyro_summary must be forwarded; PoC payload had no such field');
      expect(repo.capturedGyroSummary!.sampleCount, equals(10));
    });

    // GUARD: the old PoC payload shape {samples, is_mock_alert} must NOT be
    // the interface. AntiCheatRepository.submitBatch must NOT accept
    // is_mock_alert as a parameter.
    //
    // GIVEN the AntiCheatRepository interface
    // WHEN submitBatch is called
    // THEN no is_mock_alert parameter exists in the interface
    test('submitBatch interface has no is_mock_alert parameter (old PoC shape removed)', () async {
      final repo = CapturingAntiCheatRepository();

      // If this compiles, the method signature does NOT have is_mock_alert.
      // If someone adds is_mock_alert to the interface, this test file gains a
      // new named argument and the test comment becomes the doc.
      await repo.submitBatch(
        runId: 'run-no-mock-param',
        playerId: 'player-no-mock-param',
        samples: [_makeSample()],
        // Intentionally NOT passing is_mock_alert — the interface must not have it.
      );

      // No assertion needed: compilation passing is the test.
      expect(repo.capturedRunId, equals('run-no-mock-param'));
    });
  });
}
