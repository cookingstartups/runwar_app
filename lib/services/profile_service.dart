import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'supabase_service.dart';
import '../config/constants.dart';

// Deterministic color fallback for Supabase-only players (no local profile).
String _colorForId(String id) {
  final sum = id.codeUnits.fold(0, (a, b) => a + b);
  return kPlayerColors[sum % kPlayerColors.length];
}

class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  /// AC-12. Returns the row map (7 keys) or null if no row exists.
  /// Falls back to Supabase `players` when local profile is missing and
  /// Supabase is connected (covers bot players and future server-only users).
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    final profile = await DatabaseService.instance.getProfile(userId);
    if (profile != null) return profile;

    if (!SupabaseService.instance.isConnected) return null;
    try {
      final result = await SupabaseService.instance.supabase
          .from('players')
          .select('user_id, username, color')
          .eq('user_id', userId)
          .limit(1);
      final list = result as List<dynamic>;
      if (list.isEmpty) return null;
      final p = list.first as Map<String, dynamic>;
      return {
        'id': p['user_id'],
        'username': p['username'] ?? '',
        'color': p['color']?.toString() ?? _colorForId(userId),
        'score': 0,
        'invited_at': null,
        'is_tester': 0,
      };
    } catch (e) {
      debugPrint('[ProfileService] Supabase fallback error: $e');
      return null;
    }
  }

  /// AC-13. Updates only the supplied non-null fields. All-null is a no-op.
  Future<void> updateProfile(
    String userId, {
    String? username,
    String? color,
    String? avatarUrl,
    String? bio,
    Map<String, dynamic>? avatarMetadata,
  }) async {
    final patch = <String, Object?>{};
    if (username != null) patch['username'] = username;
    if (color != null) patch['color'] = color;
    if (avatarUrl != null) patch['avatar_url'] = avatarUrl;
    if (bio != null) patch['bio'] = bio;
    if (avatarMetadata != null) patch['avatar_metadata'] = avatarMetadata;
    if (patch.isEmpty) return; // AC-13 unwanted behaviour: all-null no-op

    await DatabaseService.instance.updateProfile(userId, patch);
  }

  /// AC-14. True iff `invited_at IS NOT NULL`. Missing row → false.
  Future<bool> isInvited(String userId) async {
    return DatabaseService.instance.isProfileInvited(userId);
  }
}
