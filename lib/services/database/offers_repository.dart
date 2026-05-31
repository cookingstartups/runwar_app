// lib/services/database/offers_repository.dart
//
// OffersRepository — pending-offer stream, accept, decline.
// Phase 2 design.md §3.2 + §3.3 + §3.4. Models: SuperpowerOffer, SpendResult.
//
// IMPORTANT:
//   - watchPending wraps .map() in .asBroadcastStream() per design.md §3.3.
//   - decline routes through the decline_offer(p_offer_id) RPC (SECURITY
//     DEFINER, RLS via auth.uid()) — NOT a direct UPDATE, because the
//     superpower_offers RLS is SELECT-only for authenticated users.
//     See design.md §3.4 for the SQL definition.
//   - Only lib/screens/contextual_offer_screen.dart may call accept().
//     Enforced by tool/lint/no_storefront.dart.
//
// CI GATE: supabase_flutter import permitted here (lib/services/database/).

import 'package:supabase_flutter/supabase_flutter.dart';

/// Immutable snapshot of a pending superpower offer row.
class SuperpowerOffer {
  SuperpowerOffer({
    required this.id,
    required this.offerType,
    required this.offeredPowerType,
    required this.tier,
    required this.costCredits,
    required this.expiresAt,
  });

  factory SuperpowerOffer.fromJson(Map<String, dynamic> j) => SuperpowerOffer(
        id: j['id'] as String,
        offerType: j['offer_type'] as String,
        offeredPowerType: j['offered_power_type'] as String,
        tier: j['tier'] as String,
        costCredits: (j['cost_credits'] as num).toInt(),
        expiresAt: DateTime.parse(j['expires_at'] as String),
      );

  final String id;

  /// DB string: 'extra_charge' | 'random_same_tier' | 'complementary_tier'
  final String offerType;

  /// DB UPPER_SNAKE: 'RUSH' | 'SHIELD' | 'GHOST_RUN' | 'BLITZ' | 'FORTIFY' | 'OVERCLOCK'
  final String offeredPowerType;

  /// DB string: 'common' | 'rare'
  final String tier;

  final int costCredits;
  final DateTime expiresAt;

  /// BLITZ and FORTIFY require the player to be standing on a zone at spend time.
  bool get requiresStandingZone =>
      offeredPowerType == 'BLITZ' || offeredPowerType == 'FORTIFY';
}

/// Discriminated result returned by [OffersRepository.accept].
sealed class SpendResult {
  const SpendResult();

  factory SpendResult.fromJson(Map<String, dynamic> j) =>
      (j['success'] == true)
          ? SpendOk(j)
          : SpendFailure(j['reason'] as String? ?? 'unknown');
}

/// Offer accepted successfully — credits debited, grant materialised.
class SpendOk extends SpendResult {
  SpendOk(Map<String, dynamic> j)
      : offerId = j['offer_id'] as String,
        grantId = j['grant_id'] as String,
        newBalance = (j['new_balance'] as num).toInt(),
        effect = (j['effect_applied'] as Map?)?.cast<String, dynamic>();
  final String offerId;
  final String grantId;
  final int newBalance;

  /// Non-null for BLITZ/FORTIFY: {zone_id, influence_delta}.
  final Map<String, dynamic>? effect;
}

/// Offer acceptance rejected for a business reason.
class SpendFailure extends SpendResult {
  const SpendFailure(this.reason);

  /// Machine code: offer_not_found | wrong_player | already_resolved |
  ///   offer_expired | no_target_zone | not_on_zone | insufficient_credits
  final String reason;
}

/// Repository interface for superpower offers.
abstract interface class OffersRepository {
  /// Broadcast stream of the player's current pending offer, or null.
  /// The stream filters to pending + unexpired offers client-side.
  /// Uses .asBroadcastStream() so multiple widget listeners don't fork
  /// the underlying supabase-flutter stream (design.md §3.3).
  Stream<SuperpowerOffer?> watchPending(String playerId);

  /// Invoke spend_credits_on_power edge function for [offerId].
  /// For BLITZ/FORTIFY, pass [targetZoneId], [lat], [lng].
  /// Returns [SpendResult] — never throws on business failure.
  Future<SpendResult> accept(
    String offerId, {
    String? targetZoneId,
    double? lat,
    double? lng,
  });

  /// Mark the offer declined via the decline_offer(p_offer_id) RPC.
  /// Design.md §3.4: direct UPDATE is blocked by RLS; the RPC is SECURITY
  /// DEFINER and enforces player ownership via auth.uid().
  Future<void> decline(String offerId);
}

/// Supabase-backed OffersRepository.
class SupabaseOffersRepository implements OffersRepository {
  SupabaseOffersRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<SuperpowerOffer?> watchPending(String playerId) => _client
      .from('superpower_offers')
      .stream(primaryKey: ['id'])
      .eq('player_id', playerId)
      .map((rows) {
        final pending = rows
            .where((r) =>
                r['status'] == 'pending' &&
                DateTime.parse(r['expires_at'] as String)
                    .isAfter(DateTime.now()))
            .toList();
        if (pending.isEmpty) return null;
        return SuperpowerOffer.fromJson(pending.first);
      })
      // .map on a non-broadcast stream is itself non-broadcast.
      // Wrapping ensures multiple listeners (modal + background listener) share
      // the same subscription without duplicating the Realtime channel.
      .asBroadcastStream();

  @override
  Future<SpendResult> accept(
    String offerId, {
    String? targetZoneId,
    double? lat,
    double? lng,
  }) async {
    final r = await _client.functions.invoke(
      'spend_credits_on_power',
      body: {
        'offer_id': offerId,
        if (targetZoneId != null) 'target_zone_id': targetZoneId,
        if (lat != null) 'player_lat': lat,
        if (lng != null) 'player_lng': lng,
      },
    );
    return SpendResult.fromJson(r.data as Map<String, dynamic>);
  }

  @override
  Future<void> decline(String offerId) async {
    // Routes through SECURITY DEFINER RPC — direct UPDATE is blocked by RLS.
    // SQL: decline_offer(p_offer_id UUID) — added in migration 0017 §3.4.
    await _client.rpc('decline_offer', params: {'p_offer_id': offerId});
  }
}
