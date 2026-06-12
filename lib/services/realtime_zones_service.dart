// DEPRECATED (Phase 1): superseded by SupabaseZonesRepository.
// All functionality moved to lib/services/database/zones_repository_supabase.dart.
// This file is retained for the Phase 1 transition; remove in Phase 2 (task RW-P2-01).
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../config/supabase_config.dart';

/// @Deprecated Use SupabaseZonesRepository via zonesRepositoryProvider instead.
/// Subscribes to the `zones` Realtime channel and re-queries `zones_geojson`
/// on every change. Emits zone lists in the same shape as ZonesService so
/// zonesProvider can switch between the two without touching map_screen.dart.
class RealtimeZonesService {
  RealtimeZonesService._();
  static final RealtimeZonesService instance = RealtimeZonesService._();

  final _controllers = <String, StreamController<List<Map<String, dynamic>>>>{};
  RealtimeChannel? _channel;

  /// Returns a broadcast stream of zones for [city].
  /// On first call for a given city, opens the Realtime channel if not yet open.
  Stream<List<Map<String, dynamic>>> watchZonesByCity(String city) {
    _controllers.putIfAbsent(
      city,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(
        onListen: () => _ensureSubscribed(city),
      ),
    );
    // Emit current state immediately on subscribe.
    _fetchAndEmit(city);
    return _controllers[city]!.stream;
  }

  void _ensureSubscribed(String city) {
    if (_channel != null) return;

    _channel = SupabaseService.instance.supabase
        .channel(SupabaseConfig.channelZones)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'zones',
          callback: (payload) => _fetchAndEmit(city),
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint('[RealtimeZonesService] subscribe error: $error');
          }
        });
  }

  Future<void> _fetchAndEmit(String city) async {
    try {
      final rows = await SupabaseService.instance.supabase
          .from('zones_geojson')
          .select()
          .eq('city', city);

      final zones = (rows as List<dynamic>)
          .map((r) => _normalise(r as Map<String, dynamic>))
          .toList();

      _controllers[city]?.add(zones);
    } catch (e) {
      debugPrint('[RealtimeZonesService] fetch error: $e');
    }
  }

  /// Maps Supabase schema → shape expected by existing Flutter code.
  /// SQLite uses `influence` (double), `geom_json` (String).
  /// Supabase uses `influence_level` (int), `geom_json` (JSONB Map).
  @visibleForTesting
  Map<String, dynamic> normaliseForTest(Map<String, dynamic> r) =>
      _normalise(r);

  Map<String, dynamic> _normalise(Map<String, dynamic> r) {
    final geomRaw = r['geom_json'];
    final geomStr = geomRaw is String ? geomRaw : jsonEncode(geomRaw);

    return {
      'id': r['id'] as String,
      'owner_id': r['owner_id'] as String?,
      'city': r['city'] as String? ?? 'Valencia',
      'geom_json': geomStr,
      'influence': ((r['influence_level'] as num?) ?? 1).toDouble(),
      'status': r['status'] as String? ?? 'owned',
      'shield_active': r['shield_active'] as bool? ?? false,
      'shield_expires_at': r['shield_expires_at'] as String?,
      'dispute_expires_at': r['dispute_expires_at'] as String?,
      'created_at': r['created_at'] as String?,
      'updated_at': r['updated_at'] as String?,
    };
  }

  Future<void> dispose() async {
    await _channel?.unsubscribe();
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}
