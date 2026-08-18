// lib/services/database/zones_repository_supabase.dart
//
// Supabase-backed ZonesRepository implementation.
// Absorbs all logic from lib/services/realtime_zones_service.dart (deprecated).
// Design.md §1 SupabaseZonesRepository spec.
//
// CI GATE: supabase_flutter import is allowed here (lib/services/ layer).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import '../../config/supabase_config.dart';
import 'repository.dart';
import 'zones_repository.dart';
import 'models/zone.dart';

/// Supabase-backed ZonesRepository.
///
/// Each city gets exactly one broadcast StreamController. First subscriber
/// triggers the initial fetch + Realtime subscribe. Last subscriber teardown
/// closes the channel and removes the entry. Dispose is idempotent.
class SupabaseZonesRepository implements ZonesRepository {
  SupabaseZonesRepository();

  final _controllers = <String, StreamController<List<Zone>>>{};
  final _pendingClose = <String, Timer>{};
  RealtimeChannel? _channel;
  bool _disposed = false;

  static const _kTeardownGrace = Duration(milliseconds: 300);

  SupabaseClient get _client => SupabaseService.instance.supabase;

  // ── ZonesRepository interface ───────────────────────────────────────────────

  @override
  Future<RepoResult<List<Zone>>> fetchByCity(String city) async {
    if (_disposed) return RepoResult.err(RepoError.unknown, detail: 'disposed');
    try {
      final rows = await _client
          .from('zones_geojson')
          .select()
          .eq('city', city);
      final zones = (rows as List<dynamic>)
          .map((r) => Zone.fromGeoJsonRow(r as Map<String, dynamic>))
          .toList();
      return RepoResult.ok(zones);
    } catch (e) {
      debugPrint('[SupabaseZonesRepository] fetchByCity error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Stream<List<Zone>> watchByCity(String city) {
    if (_disposed) {
      return const Stream.empty();
    }

    // A resubscribe within the grace window cancels the pending close and
    // reuses the existing controller instead of tearing down and
    // recreating it. Placed before the containsKey check below so it also
    // covers a resubscribe that lands on that branch (not just onListen).
    _pendingClose.remove(city)?.cancel();

    if (_controllers.containsKey(city)) {
      // Re-emit current data immediately for a new subscriber.
      _fetchAndEmit(city);
      return _controllers[city]!.stream;
    }

    // First subscription for this city — create the controller + subscribe.
    final controller = StreamController<List<Zone>>.broadcast(
      onListen: () {
        _ensureChannelSubscribed(city);
        _fetchAndEmit(city);
      },
      onCancel: () {
        // Defer teardown by 300ms instead of closing synchronously. If a
        // new subscriber arrives first, the watchByCity guard above cancels
        // this timer and reuses the controller. Do NOT unsubscribe the
        // channel here — other cities might share it. Full teardown also
        // happens in dispose().
        _pendingClose[city] = Timer(_kTeardownGrace, () {
          _pendingClose.remove(city);
          _controllers.remove(city)?.close();
        });
      },
    );
    _controllers[city] = controller;

    return controller.stream;
  }

  @override
  Future<RepoResult<Zone>> fetchById(String id) async {
    if (_disposed) return RepoResult.err(RepoError.unknown, detail: 'disposed');
    try {
      final rows = await _client
          .from('zones_geojson')
          .select()
          .eq('id', id)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return RepoResult.err(RepoError.notFound);
      return RepoResult.ok(
          Zone.fromGeoJsonRow(list.first as Map<String, dynamic>));
    } catch (e) {
      debugPrint('[SupabaseZonesRepository] fetchById error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final t in _pendingClose.values) {
      t.cancel();
    }
    _pendingClose.clear();
    await _channel?.unsubscribe();
    _channel = null;
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Subscribes to the zones Realtime channel (once globally).
  /// On any Postgres change, re-fetches and emits to all active city controllers.
  void _ensureChannelSubscribed(String city) {
    if (_channel != null) return;

    _channel = _client
        .channel(SupabaseConfig.channelZones)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'zones',
          callback: (_) {
            // Re-fetch all active cities on any zones change.
            for (final c in _controllers.keys.toList()) {
              _fetchAndEmit(c);
            }
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint(
                '[SupabaseZonesRepository] channel subscribe error: $error');
          }
        });
  }

  Future<void> _fetchAndEmit(String city, [bool isRetry = false]) async {
    if (_disposed) return;
    final result = await fetchByCity(city);
    switch (result) {
      case Ok<List<Zone>>(value: final zones):
        _controllers[city]?.add(zones);
      case Err<List<Zone>>(error: final error, detail: final detail):
        if (!isRetry) {
          // A single bounded retry absorbs transient failures before ever
          // surfacing an error banner to the player.
          Timer(const Duration(seconds: 2), () {
            if (_disposed) return;
            _fetchAndEmit(city, true);
          });
          return;
        }
        debugPrint(
            '[SupabaseZonesRepository] _fetchAndEmit error: $error $detail');
        _controllers[city]?.addError(
          Exception('zones fetch failed: $error${detail != null ? " ($detail)" : ""}'),
        );
    }
  }
}
