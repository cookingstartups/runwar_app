// lib/services/database/disputes_repository_supabase.dart
//
// Supabase-backed DisputesRepository implementation.
// Design.md §1 SupabaseDisputesRepository spec.
//
// CI GATE: supabase_flutter import is allowed here (lib/services/ layer).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import 'repository.dart';
import 'disputes_repository.dart';
import 'models/dispute.dart';

/// Supabase-backed DisputesRepository.
///
/// Each zoneId gets one broadcast StreamController. Realtime subscription
/// on the disputes table fires a re-fetch for the matching zone.
/// dispose() closes all controllers and unsubscribes.
class SupabaseDisputesRepository implements DisputesRepository {
  SupabaseDisputesRepository();

  final _controllers = <String, StreamController<Dispute?>>{};
  final _channels = <String, RealtimeChannel>{};
  bool _disposed = false;

  SupabaseClient get _client => SupabaseService.instance.supabase;

  // ── DisputesRepository interface ────────────────────────────────────────────

  @override
  Future<RepoResult<Dispute?>> fetchOpenForZone(String zoneId) async {
    if (_disposed) return RepoResult.err(RepoError.unknown, detail: 'disposed');
    try {
      final rows = await _client
          .from('disputes')
          .select()
          .eq('zone_id', zoneId)
          .isFilter('resolved_at', null)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return RepoResult.ok(null);
      return RepoResult.ok(
          Dispute.fromRow(list.first as Map<String, dynamic>));
    } catch (e) {
      debugPrint('[SupabaseDisputesRepository] fetchOpenForZone error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Stream<Dispute?> watchOpenForZone(String zoneId) {
    if (_disposed) return Stream.value(null);

    if (_controllers.containsKey(zoneId)) {
      _fetchAndEmit(zoneId);
      return _controllers[zoneId]!.stream;
    }

    final controller = StreamController<Dispute?>.broadcast(
      onListen: () {
        _subscribeForZone(zoneId);
        _fetchAndEmit(zoneId);
      },
      onCancel: () {
        _channels.remove(zoneId)?.unsubscribe();
        _controllers.remove(zoneId)?.close();
      },
    );
    _controllers[zoneId] = controller;

    return controller.stream;
  }

  @override
  Future<RepoResult<Dispute>> fetchById(String id) async {
    if (_disposed) return RepoResult.err(RepoError.unknown, detail: 'disposed');
    try {
      final rows = await _client
          .from('disputes')
          .select()
          .eq('id', id)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return RepoResult.err(RepoError.notFound);
      return RepoResult.ok(
          Dispute.fromRow(list.first as Map<String, dynamic>));
    } catch (e) {
      debugPrint('[SupabaseDisputesRepository] fetchById error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
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

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _subscribeForZone(String zoneId) {
    if (_channels.containsKey(zoneId)) return;

    final channel = _client
        .channel('disputes:$zoneId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'disputes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'zone_id',
            value: zoneId,
          ),
          callback: (_) => _fetchAndEmit(zoneId),
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint(
                '[SupabaseDisputesRepository] channel error ($zoneId): $error');
          }
        });
    _channels[zoneId] = channel;
  }

  Future<void> _fetchAndEmit(String zoneId) async {
    if (_disposed) return;
    final result = await fetchOpenForZone(zoneId);
    if (result is Ok<Dispute?>) {
      _controllers[zoneId]?.add(result.value);
    }
  }
}
