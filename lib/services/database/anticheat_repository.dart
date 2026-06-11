// lib/services/database/anticheat_repository.dart
//
// AntiCheatRepository — GPS/gyro telemetry submission and live suspicion scores.
// Phase 3 trust layer. P3-FL.
//
// CONTRACT:
//   - submitBatch() returns Ok(AntiCheatBatchResult) on success, Err on failure.
//   - watchScore() emits SuspicionScore(score: 0.0) when no row exists yet.
//   - Never throw on business failure — return RepoResult.err instead.
//   - Network / infrastructure failures return RepoResult.err(RepoError.network).
//
// CI GATE: supabase_flutter import permitted here (lib/services/database/).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import 'repository.dart';

// ── Value types ───────────────────────────────────────────────────────────────

/// A single GPS telemetry reading.
class GpsSample {
  final double lat, lng, ts;
  final bool? isMocked;

  const GpsSample({
    required this.lat,
    required this.lng,
    required this.ts,
    this.isMocked,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'ts': ts,
        if (isMocked != null) 'is_mocked': isMocked,
      };
}

/// Aggregated gyroscope means for a run session.
class GyroSummary {
  final double? meanRx, meanRy, meanRz;

  const GyroSummary({this.meanRx, this.meanRy, this.meanRz});

  Map<String, dynamic> toJson() => {
        if (meanRx != null) 'mean_rx': meanRx,
        if (meanRy != null) 'mean_ry': meanRy,
        if (meanRz != null) 'mean_rz': meanRz,
      };
}

/// Live suspicion score row from the `suspicion_scores` table.
class SuspicionScore {
  final String playerId;
  final double score;
  final double sessionMaxScore;

  const SuspicionScore({
    required this.playerId,
    required this.score,
    required this.sessionMaxScore,
  });

  factory SuspicionScore.fromJson(Map<String, dynamic> j) => SuspicionScore(
        playerId: j['user_id'] as String,
        score: (j['score'] as num).toDouble(),
        sessionMaxScore: (j['session_max_score'] as num? ?? 0.0).toDouble(),
      );
}

/// Parsed result returned from the `anticheat_score` edge function.
class AntiCheatBatchResult {
  final List<String> flags;
  final double score;
  final String? challengeId;

  const AntiCheatBatchResult({
    required this.flags,
    required this.score,
    this.challengeId,
  });
}

/// When a batch submission was triggered.
enum AntiCheatTrigger { telemetry, claimIntent }

// ── Abstract interface ────────────────────────────────────────────────────────

/// Abstract interface for anti-cheat telemetry data access.
abstract interface class AntiCheatRepository {
  /// Submit a batch of GPS samples (and optional gyro summary) for scoring.
  ///
  /// Returns Ok([AntiCheatBatchResult]) on success.
  /// Returns Err(network) on infrastructure failure.
  Future<RepoResult<AntiCheatBatchResult>> submitBatch({
    required String runId,
    required String playerId,
    required List<GpsSample> samples,
    GyroSummary? gyroSummary,
    String? gpsPatternHash,
    AntiCheatTrigger trigger = AntiCheatTrigger.telemetry,
  });

  /// Live stream of the suspicion score for [playerId].
  ///
  /// Emits a zero-score [SuspicionScore] when no row exists yet.
  /// Re-emits on every change to the `suspicion_scores` table for this player.
  Stream<SuspicionScore> watchScore(String playerId);
}

// ── Supabase implementation ───────────────────────────────────────────────────

/// Supabase-backed [AntiCheatRepository].
///
/// Uses SupabaseService.instance.supabase for the client (singleton access).
/// Each playerId gets one broadcast StreamController for the watch stream,
/// backed by a Supabase Realtime `.stream()` subscription.
class SupabaseAntiCheatRepository implements AntiCheatRepository {
  SupabaseAntiCheatRepository();

  final _controllers = <String, StreamController<SuspicionScore>>{};
  final _streamSubs = <String, StreamSubscription<List<Map<String, dynamic>>>>{};
  bool _disposed = false;

  SupabaseClient get _client => SupabaseService.instance.supabase;

  // ── AntiCheatRepository interface ────────────────────────────────────────────

  @override
  Future<RepoResult<AntiCheatBatchResult>> submitBatch({
    required String runId,
    required String playerId,
    required List<GpsSample> samples,
    GyroSummary? gyroSummary,
    String? gpsPatternHash,
    AntiCheatTrigger trigger = AntiCheatTrigger.telemetry,
  }) async {
    if (_disposed) {
      return RepoResult.err(RepoError.unknown, detail: 'disposed');
    }
    try {
      final r = await _client.functions.invoke(
        'anticheat_score',
        body: {
          'run_id': runId,
          'user_id': playerId,
          'samples': samples.map((s) => s.toJson()).toList(),
          if (gyroSummary != null) 'gyro_summary': gyroSummary.toJson(),
          if (gpsPatternHash != null) 'gps_pattern_hash': gpsPatternHash,
          'triggered_by': trigger.name,
        },
      );
      final data = r.data as Map<String, dynamic>?;
      if (data == null) {
        return RepoResult.err(RepoError.unknown,
            detail: 'anticheat_score returned null');
      }
      if (data['error'] != null) {
        return RepoResult.err(RepoError.conflict,
            detail: data['error'].toString());
      }
      final result = AntiCheatBatchResult(
        flags: (data['flags'] as List<dynamic>? ?? [])
            .map((f) => f.toString())
            .toList(),
        score: (data['score'] as num? ?? 0.0).toDouble(),
        challengeId: data['challenge_id'] as String?,
      );
      return RepoResult.ok(result);
    } catch (e) {
      debugPrint('[SupabaseAntiCheatRepository] submitBatch error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Stream<SuspicionScore> watchScore(String playerId) {
    if (_disposed) {
      return Stream.value(
          SuspicionScore(playerId: playerId, score: 0.0, sessionMaxScore: 0.0));
    }

    if (_controllers.containsKey(playerId)) {
      return _controllers[playerId]!.stream;
    }

    final controller = StreamController<SuspicionScore>.broadcast(
      onListen: () => _subscribeForPlayer(playerId),
      onCancel: () {
        _streamSubs.remove(playerId)?.cancel();
        _controllers.remove(playerId)?.close();
      },
    );
    _controllers[playerId] = controller;

    return controller.stream;
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  void _subscribeForPlayer(String playerId) {
    if (_streamSubs.containsKey(playerId)) return;

    final sub = _client
        .from('suspicion_scores')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', playerId)
        .listen(
          (rows) {
            if (_disposed) return;
            if (rows.isEmpty) {
              _controllers[playerId]?.add(SuspicionScore(
                playerId: playerId,
                score: 0.0,
                sessionMaxScore: 0.0,
              ));
            } else {
              _controllers[playerId]
                  ?.add(SuspicionScore.fromJson(rows.first));
            }
          },
          onError: (Object e) {
            debugPrint(
                '[SupabaseAntiCheatRepository] watchScore error ($playerId): $e');
          },
        );
    _streamSubs[playerId] = sub;
  }

  /// Release all resources. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _streamSubs.values) {
      await sub.cancel();
    }
    _streamSubs.clear();
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}
