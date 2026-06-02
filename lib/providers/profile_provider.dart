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

/// Player's referral code — format: username[0:3].toUpperCase() + 3 deterministic chars.
/// Generated on first access, cached in local prefs, backfilled to Supabase.
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
  // 1. Supabase is canonical.
  if (SupabaseService.instance.isConnected) {
    try {
      final row = await SupabaseService.instance.supabase
          .from('players')
          .select('referral_code')
          .eq('id', userId)
          .maybeSingle();
      final remote = row?['referral_code'] as String?;
      if (remote != null && remote.isNotEmpty) return remote;
    } catch (_) {}
  }
  // 2. Local prefs cache (survives offline).
  try {
    final cached = await DatabaseService.instance.db.query(
      'prefs',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['referral_code_$userId'],
      limit: 1,
    );
    if (cached.isNotEmpty) return cached.first['value'] as String;
  } catch (_) {}
  // 3. Generate: username[0:3] + 3 chars derived from userId hash.
  String username = '';
  try {
    final rows = await DatabaseService.instance.db.query(
      'profiles', columns: ['username'], where: 'id = ?', whereArgs: [userId], limit: 1,
    );
    username = rows.isEmpty ? '' : (rows.first['username'] as String? ?? '');
  } catch (_) {}
  final code = _buildReferralCode(username, userId);
  // Persist locally so it never regenerates differently.
  try {
    await DatabaseService.instance.db.insert(
      'prefs', {'key': 'referral_code_$userId', 'value': code},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  } catch (_) {}
  // Backfill Supabase for existing users.
  if (SupabaseService.instance.isConnected) {
    try {
      await SupabaseService.instance.supabase
          .from('players')
          .upsert({'id': userId, 'referral_code': code}, onConflict: 'id');
    } catch (_) {}
  }
  return code;
});

String _buildReferralCode(String username, String userId) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final clean = username.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final prefix = (clean.length >= 3 ? clean : (clean + 'XXX')).substring(0, 3);
  // Derive 3-char suffix deterministically from userId so it's stable across reinstalls.
  final hash = userId.replaceAll('-', '').codeUnits.fold(0, (a, b) => a * 31 + b);
  final suffix = [
    chars[(hash.abs() >> 0) % chars.length],
    chars[(hash.abs() >> 5) % chars.length],
    chars[(hash.abs() >> 10) % chars.length],
  ].join();
  return '$prefix$suffix';
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
