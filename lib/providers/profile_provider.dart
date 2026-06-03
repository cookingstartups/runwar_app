import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
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

/// Player's referral code — format: username[0:3] + 3 monthly-rotating chars = 6 chars total.
///
/// The 6-char suffix is derived from userId + current year/month, so it
/// changes automatically on the first access of each new month. The local
/// cache key is scoped to year+month so stale codes are never returned.
final referralCodeProvider =
    FutureProvider.family<String?, String>((ref, userId) async {
  // Gate: only players who are invited AND have redeemed an invitation code can refer.
  try {
    final db = DatabaseService.instance.db;
    final profile = await db.query(
      'profiles', columns: ['invited_at'], where: 'id = ?', whereArgs: [userId], limit: 1,
    );
    final isInvited = profile.isNotEmpty && profile.first['invited_at'] != null;
    if (!isInvited) return null;
    final redeemed = await db.query(
      'redeemed_codes', columns: ['code'], where: 'user_id = ?', whereArgs: [userId], limit: 1,
    );
    if (redeemed.isEmpty) return null;
  } catch (_) {
    return null;
  }
  final now = DateTime.now();
  final monthKey = 'referral_code_${userId}_${now.year}_${now.month}';
  // 1. Local prefs cache scoped to current month (avoids Supabase round-trip).
  try {
    final cached = await DatabaseService.instance.db.query(
      'prefs',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [monthKey],
      limit: 1,
    );
    if (cached.isNotEmpty) return cached.first['value'] as String;
  } catch (_) {}
  // 2. Generate deterministically from username + userId + year + month.
  String username = '';
  try {
    final rows = await DatabaseService.instance.db.query(
      'profiles', columns: ['username'], where: 'id = ?', whereArgs: [userId], limit: 1,
    );
    username = rows.isEmpty ? '' : (rows.first['username'] as String? ?? '');
  } catch (_) {}
  final code = _buildReferralCode(username, userId, now);
  // Persist with month-scoped key so next month it regenerates.
  try {
    await DatabaseService.instance.db.insert(
      'prefs', {'key': monthKey, 'value': code},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  } catch (_) {}
  // Sync current code to Supabase (overwrites any previous month's value).
  if (SupabaseService.instance.isConnected) {
    try {
      await SupabaseService.instance.supabase
          .from('players')
          .upsert({'id': userId, 'referral_code': code}, onConflict: 'id');
    } catch (_) {}
  }
  return code;
});

/// Builds a 6-char invite code: username[0:3] + 3 monthly-rotating chars.
///
/// Last 3: derived from userId + year + month → rotates each calendar month.
String _buildReferralCode(String username, String userId, DateTime now) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final clean = username.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final prefix = (clean.length >= 3 ? clean : (clean + 'XXX')).substring(0, 3);
  final seed = userId.replaceAll('-', '') + now.year.toString() + now.month.toString();
  final hash = seed.codeUnits.fold(0, (a, b) => a * 31 + b);
  final rotating = List.generate(3, (i) => chars[(hash.abs() >> (i * 5)) % chars.length]).join();
  return '$prefix$rotating';
}

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
