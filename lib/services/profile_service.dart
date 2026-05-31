import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'supabase_service.dart';

// Deterministic zone-polygon colors for Supabase-only players (no local profile).
const _kColorPalette = [
  '#FF6B35', '#00A8CC', '#5CB85C', '#9B59B6',
  '#E74C3C', '#3498DB', '#27AE60', '#F39C12',
];

String _colorForId(String id) {
  final sum = id.codeUnits.fold(0, (a, b) => a + b);
  return _kColorPalette[sum % _kColorPalette.length];
}

class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  /// AC-12. Returns the row map (7 keys) or null if no row exists.
  /// Falls back to Supabase `players` when local profile is missing and
  /// Supabase is connected (covers bot players and future server-only users).
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    final db = DatabaseService.instance.db;
    final rows = await db.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);

    if (!SupabaseService.instance.isConnected) return null;
    try {
      final result = await SupabaseService.instance.supabase
          .from('players')
          .select('id, display_name')
          .eq('id', userId)
          .limit(1);
      final list = result as List<dynamic>;
      if (list.isEmpty) return null;
      final p = list.first as Map<String, dynamic>;
      return {
        'id': p['id'],
        'username': p['display_name'] ?? '',
        'color': _colorForId(userId),
        'city': '',
        'influence_level': 0,
        'invited_at': null,
        'is_tester': 0,
      };
    } catch (e) {
      debugPrint('[ProfileService] Supabase fallback error: $e');
      return null;
    }
  }

  /// AC-13. Updates only the supplied non-null fields. All-null is a no-op.
  /// Non-matching userId is a no-op (sqflite UPDATE with no rows affected).
  Future<void> updateProfile(
    String userId, {
    String? username,
    String? city,
    String? color,
  }) async {
    final patch = <String, Object?>{};
    if (username != null) patch['username'] = username;
    if (city != null) patch['city'] = city;
    if (color != null) patch['color'] = color;
    if (patch.isEmpty) return; // AC-13 unwanted behaviour: all-null no-op

    final db = DatabaseService.instance.db;
    await db.update('profiles', patch, where: 'id = ?', whereArgs: [userId]);
  }

  /// AC-14. True iff `invited_at IS NOT NULL`. Missing row → false.
  Future<bool> isInvited(String userId) async {
    final db = DatabaseService.instance.db;
    final rows = await db.query(
      'profiles',
      columns: ['invited_at'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return rows.first['invited_at'] != null;
  }
}
