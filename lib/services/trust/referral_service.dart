// lib/services/trust/referral_service.dart
//
// ReferralService — pure observer over referral and kickback state.
// Phase 3 trust layer (P3-FL-04).
//
// CONTRACT:
//   - No supabase_flutter import — delegates entirely to ReferralsRepository.
//   - Referral writes are server-side only (Edge functions / DB triggers).
//   - ReferralService NEVER mutates referral or credit data client-side.

import '../database/referrals_repository.dart';

/// Pure observer over a player's referral and kickback state.
///
/// Owns: hasReferrer(), getKickbackHistory(), watchKickback().
/// Does NOT own referral creation — that is entirely server-side.
class ReferralService {
  ReferralService(this._repo);

  final ReferralsRepository _repo;

  /// Returns true when [playerId] was referred by another player.
  Future<bool> hasReferrer(String playerId) async =>
      (await _repo.getInviterFor(playerId)) != null;

  /// Returns the kickback transaction history for [inviterId].
  /// Ordered newest-first, up to the repository default limit (50).
  Future<List<Map<String, dynamic>>> getKickbackHistory(String inviterId) =>
      _repo.kickbackHistory(inviterId);

  /// Broadcast stream of [playerId]'s total kickback earned.
  /// Emits the current value on subscribe, then on every change.
  Stream<int> watchKickback(String playerId) =>
      _repo.watchTotalKickback(playerId);
}
