// lib/services/database/drops_repository.dart
//
// DropsRepository — active drops stream + proximity claim.
// Phase 2 design.md §3.2. Models: Drop, ClaimDropResult (sealed).
//
// CI GATE: supabase_flutter import permitted here (lib/services/database/).

import 'package:supabase_flutter/supabase_flutter.dart';

/// Immutable snapshot of a single drop from the `drops` table.
class Drop {
  Drop({
    required this.id,
    required this.city,
    required this.lat,
    required this.lng,
    required this.dropType,
    required this.value,
    required this.expiresAt,
    required this.status,
  });

  factory Drop.fromJson(Map<String, dynamic> j) => Drop(
        id: j['id'] as String,
        city: j['city'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        dropType: j['drop_type'] as String,
        value: (j['value'] as num? ?? 0).toInt(),
        expiresAt: DateTime.parse(j['expires_at'] as String),
        status: j['status'] as String,
      );

  final String id;
  final String city;
  final double lat;
  final double lng;

  /// DB string: 'influence_crystal' | 'credits_cache' | 'power_core'
  final String dropType;
  final int value;
  final DateTime expiresAt;

  /// DB string: 'active' | 'claimed' | 'expired'
  final String status;
}

/// Discriminated result returned by [DropsRepository.claim].
/// Sealed — consumers switch exhaustively.
sealed class ClaimDropResult {
  const ClaimDropResult();

  /// Parse the JSON envelope from the claim_drop edge function.
  factory ClaimDropResult.fromJson(Map<String, dynamic> j) {
    if (j['success'] == true) {
      return switch (j['drop_type']) {
        'credits_cache' => ClaimDropCash(j),
        'influence_crystal' => ClaimDropCrystal(j),
        'power_core' => ClaimDropPower(j),
        _ => const ClaimDropFailure('not_found'),
      };
    }
    return ClaimDropFailure(
      j['reason'] as String? ?? 'unknown',
      distanceM: (j['distance_m'] as num?)?.toDouble(),
    );
  }

  bool get success => switch (this) {
        ClaimDropCash _ => true,
        ClaimDropCrystal _ => true,
        ClaimDropPower _ => true,
        ClaimDropFailure _ => false,
      };
}

/// Drop was a credits_cache — player received credits.
class ClaimDropCash extends ClaimDropResult {
  ClaimDropCash(Map<String, dynamic> j)
      : credits = (j['credits_awarded'] as num).toInt(),
        newBalance = (j['new_balance'] as num).toInt();
  final int credits;
  final int newBalance;
}

/// Drop was an influence_crystal — boosted influence on a nearby zone.
class ClaimDropCrystal extends ClaimDropResult {
  ClaimDropCrystal(Map<String, dynamic> j)
      : zoneId = j['zone_id'] as String,
        newInfluence = (j['new_influence'] as num).toInt();
  final String zoneId;
  final int newInfluence;
}

/// Drop was a power_core — granted a superpower charge.
class ClaimDropPower extends ClaimDropResult {
  ClaimDropPower(Map<String, dynamic> j)
      : grantedPower = j['granted_power'] as String,
        tier = j['tier'] as String,
        charges = (j['charges'] as num).toInt();
  final String grantedPower;
  final String tier;
  final int charges;
}

/// Claim failed for a business reason (not an infrastructure error).
class ClaimDropFailure extends ClaimDropResult {
  const ClaimDropFailure(this.reason, {this.distanceM});

  /// Machine code from the server: not_found | expired | already_claimed |
  /// too_far | no_zone_nearby
  final String reason;

  /// Distance from player to drop in metres (present when reason == 'too_far').
  final double? distanceM;
}

/// Repository interface for active drops + proximity claim.
abstract interface class DropsRepository {
  /// Broadcast stream of active drops for [city].
  /// Emits the filtered list (status == 'active') on subscribe and on any
  /// Realtime change. Throws on infrastructure failure.
  Stream<List<Drop>> watchActive(String city);

  /// Invoke the claim_drop edge function for [dropId] at [lat]/[lng].
  /// Returns a [ClaimDropResult] discriminating success variants and failure
  /// reasons. Never throws on business failure — only on infra failure.
  Future<ClaimDropResult> claim(String dropId, double lat, double lng);
}

/// Supabase-backed DropsRepository.
/// Uses .stream() for Realtime (already broadcast per supabase-flutter).
/// The client-side `status == 'active'` filter keeps expired/claimed drops
/// out of the marker layer between Realtime ticks.
class SupabaseDropsRepository implements DropsRepository {
  SupabaseDropsRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<List<Drop>> watchActive(String city) => _client
      .from('drops')
      .stream(primaryKey: ['id'])
      .eq('city', city)
      .map((rows) => rows
          .where((r) => r['status'] == 'active')
          .map(Drop.fromJson)
          .toList());

  @override
  Future<ClaimDropResult> claim(String dropId, double lat, double lng) async {
    final r = await _client.functions.invoke(
      'claim_drop',
      body: {'drop_id': dropId, 'player_lat': lat, 'player_lng': lng},
    );
    return ClaimDropResult.fromJson(r.data as Map<String, dynamic>);
  }
}
