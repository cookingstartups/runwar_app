// lib/services/database/challenges_repository.dart
//
// ChallengesRepository — open-challenge lookup, outcome submission, live watch.
// Phase 3 trust layer. P3-FL-05.
//
// CONTRACT:
//   - getOpenChallenge() returns Ok(null) when no open challenge exists.
//   - submitChallengeOutcome() returns Ok(null) on success, Err on failure.
//   - watchOpenChallenge() emits null when no open challenge exists.
//   - Never throw on business failure — return RepoResult.err instead.
//   - Network / infrastructure failures return RepoResult.err(RepoError.network).
//
// CI GATE: supabase_flutter import permitted here (lib/services/database/).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import 'repository.dart';

/// Immutable snapshot of a single row from the `challenges` table.
class Challenge {
  Challenge({
    required this.id,
    required this.playerId,
    required this.status,
    required this.challengeType,
    required this.expiresAt,
    this.pendingPayload,
  });

  factory Challenge.fromRow(Map<String, dynamic> j) => Challenge(
        id: j['id'] as String,
        playerId: j['user_id'] as String,
        status: j['status'] as String,
        challengeType: j['challenge_type'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        pendingPayload:
            (j['pending_payload'] as Map?)?.cast<String, dynamic>(),
      );

  /// Primary key.
  final String id;

  /// Owning player's UUID.
  final String playerId;

  /// DB string: 'open' | 'resolved' | 'failed' | 'expired'
  final String status;

  /// e.g. 'flag_capture' | 'zone_control' | 'pvp_duel'
  final String challengeType;

  /// Structured payload attached to the pending challenge (nullable).
  final Map<String, dynamic>? pendingPayload;

  /// When the challenge expires server-side.
  final DateTime expiresAt;
}

/// Abstract interface for challenge data access.
abstract interface class ChallengesRepository {
  /// Fetch the open challenge for [playerId], if any.
  ///
  /// Returns Ok(null) when the player has no open challenge.
  /// Returns Err(network) on infrastructure failure.
  Future<RepoResult<Challenge?>> getOpenChallenge(String playerId);

  /// Submit an outcome for [challengeId].
  ///
  /// [outcome] must be 'resolve' or 'fail'.
  /// Returns Ok(null) on success, Err on failure.
  Future<RepoResult<void>> submitChallengeOutcome(
      String challengeId, String outcome);

  /// Broadcast stream of the open challenge for [playerId].
  ///
  /// Emits null when the player has no open challenge.
  /// Re-emits on every Realtime change to the challenges table for this player.
  Stream<Challenge?> watchOpenChallenge(String playerId);
}

/// Supabase-backed [ChallengesRepository].
///
/// Uses SupabaseService.instance.supabase for the client (singleton access).
/// Each playerId gets one broadcast StreamController for the watch stream.
/// Realtime subscription on the challenges table re-fetches on any change.
class SupabaseChallengesRepository implements ChallengesRepository {
  SupabaseChallengesRepository();

  final _controllers = <String, StreamController<Challenge?>>{};
  final _channels = <String, RealtimeChannel>{};
  bool _disposed = false;

  SupabaseClient get _client => SupabaseService.instance.supabase;

  // ── ChallengesRepository interface ──────────────────────────────────────────

  @override
  Future<RepoResult<Challenge?>> getOpenChallenge(String playerId) async {
    if (_disposed) {
      return RepoResult.err(RepoError.unknown, detail: 'disposed');
    }
    try {
      final rows = await _client
          .from('challenges')
          .select()
          .eq('user_id', playerId)
          .eq('status', 'open')
          .order('expires_at', ascending: true)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return RepoResult.ok(null);
      return RepoResult.ok(
          Challenge.fromRow(list.first as Map<String, dynamic>));
    } catch (e) {
      debugPrint('[SupabaseChallengesRepository] getOpenChallenge error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Future<RepoResult<void>> submitChallengeOutcome(
      String challengeId, String outcome) async {
    if (_disposed) {
      return RepoResult.err(RepoError.unknown, detail: 'disposed');
    }
    try {
      final r = await _client.functions.invoke(
        'submit_challenge_outcome',
        body: {'challenge_id': challengeId, 'outcome': outcome},
      );
      final data = r.data as Map<String, dynamic>?;
      if (data == null) {
        return RepoResult.err(RepoError.unknown,
            detail: 'submit_challenge_outcome returned null');
      }
      if (data['error'] != null) {
        return RepoResult.err(RepoError.conflict,
            detail: data['error'].toString());
      }
      return RepoResult.ok(null);
    } catch (e) {
      debugPrint(
          '[SupabaseChallengesRepository] submitChallengeOutcome error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Stream<Challenge?> watchOpenChallenge(String playerId) {
    if (_disposed) return Stream.value(null);

    if (_controllers.containsKey(playerId)) {
      _fetchAndEmit(playerId);
      return _controllers[playerId]!.stream;
    }

    final controller = StreamController<Challenge?>.broadcast(
      onListen: () {
        _subscribeForPlayer(playerId);
        _fetchAndEmit(playerId);
      },
      onCancel: () {
        _channels.remove(playerId)?.unsubscribe();
        _controllers.remove(playerId)?.close();
      },
    );
    _controllers[playerId] = controller;

    return controller.stream;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _subscribeForPlayer(String playerId) {
    if (_channels.containsKey(playerId)) return;

    final channel = _client
        .channel('challenges:$playerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: playerId,
          ),
          callback: (_) => _fetchAndEmit(playerId),
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint(
                '[SupabaseChallengesRepository] channel error ($playerId): $error');
          }
        });
    _channels[playerId] = channel;
  }

  Future<void> _fetchAndEmit(String playerId) async {
    if (_disposed) return;
    final result = await getOpenChallenge(playerId);
    if (result is Ok<Challenge?>) {
      _controllers[playerId]?.add(result.value);
    }
  }

  /// Release all resources. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final ch in _channels.values) {
      await ch.unsubscribe();
    }
    _channels.clear();
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}
