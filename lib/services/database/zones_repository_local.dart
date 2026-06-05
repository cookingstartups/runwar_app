// lib/services/database/zones_repository_local.dart
//
// Supabase-backed ZonesRepository fallback (was SQLite in Phase 1).
// Used only when SupabaseService.instance.isConnected == false.
// Design.md §1 LocalZonesRepository spec.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database_service.dart';
import 'repository.dart';
import 'zones_repository.dart';
import 'models/zone.dart';

/// Supabase-backed ZonesRepository (replaces SQLite LocalZonesRepository).
///
/// watchByCity uses a 5-second Timer.periodic (matches existing PoC cadence).
/// dispose() cancels the timer and closes the StreamController.
class LocalZonesRepository implements ZonesRepository {
  LocalZonesRepository();

  final _timers = <String, Timer>{};
  final _controllers = <String, StreamController<List<Zone>>>{};
  bool _disposed = false;

  // ── ZonesRepository interface ───────────────────────────────────────────────

  @override
  Future<RepoResult<List<Zone>>> fetchByCity(String city) async {
    if (_disposed) return RepoResult.err(RepoError.unknown, detail: 'disposed');
    try {
      final rows = await DatabaseService.instance.getZonesByCity(city);
      final zones = rows
          .map((r) => Zone.fromGeoJsonRow(r))
          .toList();
      return RepoResult.ok(zones);
    } catch (e) {
      debugPrint('[LocalZonesRepository] fetchByCity error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Stream<List<Zone>> watchByCity(String city) {
    if (_disposed) return const Stream.empty();

    if (_controllers.containsKey(city)) {
      return _controllers[city]!.stream;
    }

    final controller = StreamController<List<Zone>>.broadcast(
      onCancel: () {
        _timers.remove(city)?.cancel();
        _controllers.remove(city)?.close();
      },
    );
    _controllers[city] = controller;

    // Emit immediately, then every 5s.
    _emitForCity(city);
    _timers[city] = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _emitForCity(city),
    );

    return controller.stream;
  }

  @override
  Future<RepoResult<Zone>> fetchById(String id) async {
    if (_disposed) return RepoResult.err(RepoError.unknown, detail: 'disposed');
    try {
      final row = await DatabaseService.instance.getZone(id);
      if (row == null) return RepoResult.err(RepoError.notFound);
      return RepoResult.ok(Zone.fromGeoJsonRow(row));
    } catch (e) {
      debugPrint('[LocalZonesRepository] fetchById error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<void> _emitForCity(String city) async {
    if (_disposed) return;
    final result = await fetchByCity(city);
    if (result is Ok<List<Zone>>) {
      _controllers[city]?.add(result.value);
    }
  }
}
