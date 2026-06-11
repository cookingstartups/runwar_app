// lib/services/database/superpowers_repository.dart
//
// SuperpowersRepository — active grants stream + earn-event reporting.
// Phase 2 design.md §3.2. Models: SuperpowerGrant, EarnEvent, EarnResult.
// Offers (watchPending / accept / decline) live in offers_repository.dart.
//
// CI GATE: supabase_flutter import permitted here (lib/services/database/).

import 'package:supabase_flutter/supabase_flutter.dart';

import 'offers_repository.dart' show SuperpowerOffer;

/// Immutable snapshot of a superpower grant row.
/// powerType matches DB UPPER_SNAKE strings: RUSH | SHIELD | GHOST_RUN |
///   BLITZ | FORTIFY | OVERCLOCK
class SuperpowerGrant {
  SuperpowerGrant({
    required this.id,
    required this.playerId,
    required this.powerType,
    required this.charges,
    required this.chargesUsed,
    required this.source,
    this.expiresAt,
    this.consumedAt,
  });

  factory SuperpowerGrant.fromJson(Map<String, dynamic> j) => SuperpowerGrant(
        id: j['id'] as String,
        playerId: j['user_id'] as String,
        powerType: j['power_type'] as String,
        charges: (j['charges'] as num).toInt(),
        chargesUsed: (j['charges_used'] as num).toInt(),
        source: j['source'] as String,
        expiresAt: j['expires_at'] == null
            ? null
            : DateTime.parse(j['expires_at'] as String),
        consumedAt: j['consumed_at'] == null
            ? null
            : DateTime.parse(j['consumed_at'] as String),
      );

  final String id;
  final String playerId;

  /// DB value: 'RUSH' | 'SHIELD' | 'GHOST_RUN' | 'BLITZ' | 'FORTIFY' | 'OVERCLOCK'
  final String powerType;
  final int charges;
  final int chargesUsed;
  final String source;
  final DateTime? expiresAt;
  final DateTime? consumedAt;

  int get chargesRemaining => charges - chargesUsed;

  bool get isActive =>
      chargesRemaining > 0 &&
      consumedAt == null &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
}

/// Named-constructor event type sent to the earn_superpower edge function.
class EarnEvent {
  EarnEvent.claim(this.zoneId)
      : event = 'claim',
        runId = null;
  EarnEvent.conquest(this.zoneId)
      : event = 'conquest',
        runId = null;
  EarnEvent.defence(this.zoneId)
      : event = 'defence',
        runId = null;
  EarnEvent.runEnd(this.runId)
      : event = 'run_end',
        zoneId = null;
  EarnEvent.zoneCountChange()
      : event = 'zone_count_change',
        runId = null,
        zoneId = null;

  final String event;
  final String? runId;
  final String? zoneId;

  Map<String, dynamic> toJson() => {
        'event': event,
        if (runId != null) 'run_id': runId,
        if (zoneId != null) 'zone_id': zoneId,
      };
}

/// Result returned by [SuperpowersRepository.reportEvent].
/// When [granted] is true, [offer] may be non-null if a contextual offer
/// was generated server-side within the same earn invocation.
class EarnResult {
  EarnResult({
    required this.granted,
    this.powerType,
    this.grantId,
    this.tier,
    this.charges,
    this.expiresAt,
    this.offer,
    this.reason,
  });

  factory EarnResult.fromJson(Map<String, dynamic> j) => EarnResult(
        granted: j['granted'] == true,
        powerType: j['power_type'] as String?,
        grantId: j['grant_id'] as String?,
        tier: j['tier'] as String?,
        charges: (j['charges'] as num?)?.toInt(),
        expiresAt: j['expires_at'] == null
            ? null
            : DateTime.parse(j['expires_at'] as String),
        offer: j['offer'] == null
            ? null
            : SuperpowerOffer.fromJson(j['offer'] as Map<String, dynamic>),
        reason: j['reason'] as String?,
      );

  final bool granted;
  final String? powerType;
  final String? grantId;
  final String? tier;
  final int? charges;
  final DateTime? expiresAt;
  final SuperpowerOffer? offer;
  final String? reason;
}

/// Repository interface for active superpower grants + earn-event reporting.
/// Offer management (watchPending, accept, decline) is in OffersRepository.
abstract interface class SuperpowersRepository {
  /// Broadcast stream of active grants for [playerId].
  /// Filters to isActive == true client-side after each Realtime tick.
  Stream<List<SuperpowerGrant>> watchActiveGrants(String playerId);

  /// Report a gameplay event to the earn_superpower edge function.
  /// Returns an [EarnResult] with the grant details (and optional offer).
  /// Throws on infrastructure failure; never throws on a "not earned" result.
  Future<EarnResult> reportEvent(EarnEvent event);
}

/// Supabase-backed SuperpowersRepository.
class SupabaseSuperpowersRepository implements SuperpowersRepository {
  SupabaseSuperpowersRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<List<SuperpowerGrant>> watchActiveGrants(String playerId) => _client
      .from('superpower_grants')
      .stream(primaryKey: ['id'])
      .eq('user_id', playerId)
      .map((rows) => rows
          .map(SuperpowerGrant.fromJson)
          .where((g) => g.isActive)
          .toList());

  @override
  Future<EarnResult> reportEvent(EarnEvent event) async {
    final r = await _client.functions.invoke(
      'earn_superpower',
      body: event.toJson(),
    );
    return EarnResult.fromJson(r.data as Map<String, dynamic>);
  }
}
