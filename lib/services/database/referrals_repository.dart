// lib/services/database/referrals_repository.dart
//
// ReferralsRepository — read-only referral and kickback interface.
// Phase 3 trust layer (P3-FL-03).
//
// CONTRACT:
//   - Referral writes are server-side only (Edge functions / DB triggers).
//   - Client reads inviter data and kickback totals only.
//
// CI GATE: supabase_flutter import is ONLY permitted in lib/services/database/.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';

/// Read-only referral access interface.
abstract interface class ReferralsRepository {
  /// Returns the inviter row for [playerId], or null if the player was not
  /// referred by anyone.
  Future<Map<String, dynamic>?> getInviterFor(String playerId);

  /// Returns the most recent [limit] kickback transactions credited to
  /// [inviterId] (reason = 'referral_kickback'), newest first.
  Future<List<Map<String, dynamic>>> kickbackHistory(
    String inviterId, {
    int limit = 50,
  });

  /// One-shot fetch of the total kickback credits earned by [playerId].
  Future<int> totalKickbackEarned(String playerId);

  /// Broadcast stream of [playerId]'s total kickback earned.
  /// Emits the current value immediately on subscribe, then on every change.
  Stream<int> watchTotalKickback(String playerId);
}

/// Supabase-backed ReferralsRepository.
///
/// Uses the supabase-flutter `.stream()` API for the live watch — already a
/// broadcast stream, no extra StreamController wrapper needed.
class SupabaseReferralsRepository implements ReferralsRepository {
  SupabaseReferralsRepository();

  SupabaseClient get _client => SupabaseService.instance.supabase;

  @override
  Future<Map<String, dynamic>?> getInviterFor(String playerId) async {
    final row = await _client
        .from('referrals')
        .select('inviter_id')
        .eq('invitee_id', playerId)
        .maybeSingle();
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> kickbackHistory(
    String inviterId, {
    int limit = 50,
  }) async {
    final rows = await _client
        .from('credit_transactions')
        .select()
        .eq('user_id', inviterId)
        .eq('reason', 'referral_kickback')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  @override
  Future<int> totalKickbackEarned(String playerId) async {
    final row = await _client
        .from('players')
        .select('total_kickback_earned')
        .eq('user_id', playerId)
        .single();
    return (row['total_kickback_earned'] as num).toInt();
  }

  @override
  Stream<int> watchTotalKickback(String playerId) => _client
      .from('players')
      .stream(primaryKey: ['user_id'])
      .eq('user_id', playerId)
      .map((rows) => rows.isEmpty
          ? 0
          : (rows.first['total_kickback_earned'] as num).toInt());
}
