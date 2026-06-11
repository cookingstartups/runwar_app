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

/// P3: Player reputation score (0-100+) from the player_economy table.
/// Defaults to 100 if the row is missing or Supabase is unavailable.
final reputationProvider = FutureProvider.family<int, String>((ref, userId) async {
  if (!SupabaseService.instance.isConnected) return 100;
  try {
    final row = await SupabaseService.instance.supabase
        .from('player_economy')
        .select('reputation')
        .eq('user_id', userId)
        .maybeSingle();
    return (row?['reputation'] as int?) ?? 100;
  } catch (_) {
    return 100;
  }
});

/// Player's referral code — format: username[0:3] + 3 static chars = 6 chars total.
///
/// The last 3 chars are derived deterministically from userId — permanent, never rotates.
final referralCodeProvider =
    FutureProvider.family<String?, String>((ref, userId) async {
  // Gate: only players who are invited AND have redeemed an invitation code can refer.
  try {
    final profile = await DatabaseService.instance.getProfile(userId);
    final isInvited = profile != null && profile['invited_at'] != null;
    if (!isInvited) return null;

    // Check code_redemptions via Supabase.
    if (SupabaseService.instance.isConnected) {
      final redeemed = await SupabaseService.instance.supabase
          .from('code_redemptions')
          .select('code')
          .eq('user_id', userId)
          .limit(1);
      if ((redeemed as List).isEmpty) return null;
    }
  } catch (_) {
    return null;
  }
  const cacheKey = 'referral_code_';
  // 1. Remote prefs cache (permanent — code never changes).
  try {
    final cached = await DatabaseService.instance.getPref(userId, '$cacheKey$userId');
    if (cached != null && cached.isNotEmpty) return cached;
  } catch (_) {}
  // 2. Generate deterministically from username + userId.
  String username = '';
  try {
    final profile = await DatabaseService.instance.getProfile(userId);
    username = profile == null ? '' : (profile['username'] as String? ?? '');
  } catch (_) {}
  final code = _buildReferralCode(username, userId);
  try {
    await DatabaseService.instance.setPref(userId, '$cacheKey$userId', code);
  } catch (_) {}
  if (SupabaseService.instance.isConnected) {
    try {
      await SupabaseService.instance.supabase
          .from('players')
          .upsert({'user_id': userId, 'referral_code': code}, onConflict: 'user_id');
    } catch (_) {}
  }
  return code;
});

/// Builds a permanent 6-char invite code: username[0:3] + 3 chars from userId hash.
String _buildReferralCode(String username, String userId) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final clean = username.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final prefix = (clean.length >= 3 ? clean : (clean + 'XXX')).substring(0, 3);
  final hash = userId.replaceAll('-', '').codeUnits.fold(0, (a, b) => a * 31 + b);
  final suffix = List.generate(3, (i) => chars[(hash.abs() >> (i * 5)) % chars.length]).join();
  return '$prefix$suffix';
}

/// Whether the player has linked a phone number (reads from Supabase players).
final hasPhoneProvider =
    FutureProvider.family<bool, String>((ref, userId) async {
  try {
    return DatabaseService.instance.hasPhoneLinked(userId);
  } catch (_) {
    return false;
  }
});
