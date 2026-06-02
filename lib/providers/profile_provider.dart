import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';


/// Fetches the profile for a signed-in user so the route guard can decide
/// which screen to show. Returns null if the profile row doesn't exist.
/// Extracted from main.dart to allow invalidation from onboarding screens
/// without creating a circular import.
final profileGateProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
        (ref, userId) => ProfileService.instance.fetchProfile(userId));

/// P3: Player reputation score (0–100+) from the players table.
/// Defaults to 100 if the row is missing or Supabase is unavailable.
final reputationProvider = FutureProvider.family<int, String>((ref, userId) async {
  if (!SupabaseService.instance.isConnected) return 100;
  try {
    final row = await SupabaseService.instance.supabase
        .from('players')
        .select('reputation')
        .eq('id', userId)
        .maybeSingle();
    return (row?['reputation'] as int?) ?? 100;
  } catch (_) {
    return 100;
  }
});

/// Player's referral code from profiles table.
final referralCodeProvider =
    FutureProvider.family<String?, String>((ref, userId) async {
  if (!SupabaseService.instance.isConnected) return null;
  try {
    final row = await SupabaseService.instance.supabase
        .from('players')
        .select('referral_code, phone')
        .eq('id', userId)
        .maybeSingle();
    return row?['referral_code'] as String?;
  } catch (_) {
    return null;
  }
});

/// Whether the player has linked a phone number (reads from local SQLite profiles).
final hasPhoneProvider =
    FutureProvider.family<bool, String>((ref, userId) async {
  try {
    final rows = await DatabaseService.instance.db.query(
      'profiles',
      columns: ['phone'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return (rows.first['phone'] as String?)?.isNotEmpty ?? false;
  } catch (_) {
    return false;
  }
});
