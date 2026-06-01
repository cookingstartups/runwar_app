// lib/services/database/invitations_repository.dart
//
// InvitationsRepository — generate, redeem, and list invitation codes.
// Phase 3 trust layer. P3-FL-01.
//
// CONTRACT:
//   - generate() calls edge fn 'generate_invite_code'.
//   - redeem()   calls edge fn 'redeem_invite_code'.
//   - listMine() queries invitation_codes table filtered to current user.
//   - All methods return RepoResult<T> — never throw on business failure.
//   - Network / infrastructure failures return RepoResult.err(RepoError.network).
//
// CI GATE: supabase_flutter import is ONLY permitted in lib/services/database/.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository.dart';

/// Abstract interface for invitation-code operations.
abstract interface class InvitationsRepository {
  /// Generate a new invitation code for the current user.
  ///
  /// [label]           — optional human-readable label for this code.
  /// [maxRedemptions]  — max number of times the code can be redeemed (default 1).
  /// [expiresAt]       — optional expiry; null means no expiry.
  ///
  /// Returns the full row produced by the edge function on success.
  Future<RepoResult<Map<String, dynamic>>> generate({
    String? label,
    int maxRedemptions = 1,
    DateTime? expiresAt,
  });

  /// Redeem an invitation code [code] for the current user.
  ///
  /// Returns the redemption record produced by the edge function on success.
  /// Returns [RepoError.conflict] when the code is invalid, expired, or
  /// already fully redeemed.
  Future<RepoResult<Map<String, dynamic>>> redeem(String code);

  /// List all invitation codes created by the current user.
  Future<RepoResult<List<Map<String, dynamic>>>> listMine();
}

/// Supabase-backed [InvitationsRepository].
///
/// Edge functions used:
///   - `generate_invite_code`  — creates & persists the code server-side.
///   - `redeem_invite_code`    — validates & records redemption server-side.
///
/// Direct table query for [listMine] — read-only, no RLS bypass needed.
class SupabaseInvitationsRepository implements InvitationsRepository {
  SupabaseInvitationsRepository(this._client);
  final SupabaseClient _client;

  // ── InvitationsRepository interface ────────────────────────────────────────

  @override
  Future<RepoResult<Map<String, dynamic>>> generate({
    String? label,
    int maxRedemptions = 1,
    DateTime? expiresAt,
  }) async {
    try {
      final r = await _client.functions.invoke(
        'generate_invite_code',
        body: {
          if (label != null) 'label': label,
          'max_redemptions': maxRedemptions,
          if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
        },
      );
      final data = r.data as Map<String, dynamic>?;
      if (data == null) {
        return RepoResult.err(RepoError.unknown,
            detail: 'generate_invite_code returned null');
      }
      if (data['error'] != null) {
        return RepoResult.err(RepoError.unknown,
            detail: data['error'].toString());
      }
      return RepoResult.ok(data);
    } catch (e) {
      debugPrint('[SupabaseInvitationsRepository] generate error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Future<RepoResult<Map<String, dynamic>>> redeem(String code) async {
    try {
      final r = await _client.functions.invoke(
        'redeem_invite_code',
        body: {'code': code},
      );
      final data = r.data as Map<String, dynamic>?;
      if (data == null) {
        return RepoResult.err(RepoError.unknown,
            detail: 'redeem_invite_code returned null');
      }
      if (data['error'] != null) {
        // Business-level failures (invalid/expired/exhausted code).
        return RepoResult.err(RepoError.conflict,
            detail: data['error'].toString());
      }
      return RepoResult.ok(data);
    } catch (e) {
      debugPrint('[SupabaseInvitationsRepository] redeem error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  Future<RepoResult<List<Map<String, dynamic>>>> listMine() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return RepoResult.err(RepoError.auth, detail: 'no authenticated user');
    }
    try {
      final rows = await _client
          .from('invitation_codes')
          .select()
          .eq('created_by', uid)
          .order('created_at', ascending: false);
      final list = (rows as List<dynamic>)
          .cast<Map<String, dynamic>>();
      return RepoResult.ok(list);
    } catch (e) {
      debugPrint('[SupabaseInvitationsRepository] listMine error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }
}
