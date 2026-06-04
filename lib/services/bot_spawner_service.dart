import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'supabase_service.dart';

/// Finds or creates a ConquerBot zone near the player's location.
///
/// Local SQLite is probed first (zero network cost). If no rival zone is
/// cached, the spawn_conquer_bot Edge Function is called. The server handles
/// the city-wide idempotency invariant (exactly one bot zone per 2 km radius).
///
/// Throws on network / location failure — callers should render a retry CTA.
class BotSpawnerService {
  BotSpawnerService._();
  static final BotSpawnerService instance = BotSpawnerService._();

  /// Returns the bot/rival zone ID to target for Mission 2.
  ///
  /// [userId] — current player's local ID (used to exclude self-owned zones).
  /// [lat], [lng] — player's current GPS position.
  /// [city] — city slug (e.g. 'Valencia').
  Future<String> checkOrSpawn({
    required String userId,
    required double lat,
    required double lng,
    required String city,
  }) async {
    // 1. Opportunistic local probe — any non-self zone already cached?
    final nearbyId = await _findNearbyRivalLocal(userId, city);
    if (nearbyId != null) {
      debugPrint('[BotSpawnerService] local rival zone found: $nearbyId');
      return nearbyId;
    }

    // 2. No local hit → delegate to server (handles BR-O4 dedup + advisory lock).
    final resp = await SupabaseService.instance.supabase.functions.invoke(
      'spawn_conquer_bot',
      body: {'lat': lat, 'lng': lng, 'city': city},
    );
    final data = resp.data as Map<String, dynamic>;
    final zoneId = data['bot_zone_id'] as String;
    debugPrint('[BotSpawnerService] server returned bot zone: $zoneId '
        '(spawned=${data["spawned"]})');
    return zoneId;
  }

  /// Queries local SQLite for any zone in [city] not owned by [userId].
  Future<String?> _findNearbyRivalLocal(String userId, String city) async {
    try {
      final db = DatabaseService.instance.db;
      final rows = await db.query(
        'zones',
        columns: ['id'],
        where: 'city = ? AND owner_id != ?',
        whereArgs: [city, userId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['id'] as String;
    } catch (_) {
      return null;
    }
  }
}
