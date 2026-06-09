// lib/services/database/credits_repository.dart
//
// CreditsRepository — read-only credit balance interface.
// Phase 2 design.md §3.1 + §3.2: Phase 2 repos throw on infrastructure
// failure and use streams for live data. No RepoResult wrapping on streams.
//
// IMPORTANT: LedgerEntry is declared here because the spec (§6.1) co-locates
// it alongside CreditsRepository and both SupabaseCreditsRepository and
// SupabaseLedgerRepository import the same client. LedgerRepository is
// declared in ledger_repository.dart and references LedgerEntry from here.
//
// CI GATE: supabase_flutter import is ONLY permitted in lib/services/database/.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row from the credit_transactions ledger table.
/// Immutable. Parse via [LedgerEntry.fromJson].
class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.delta,
    required this.reason,
    required this.createdAt,
    this.relatedEntityId,
    this.relatedEntityType,
    this.metadata = const {},
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as String,
        delta: (j['delta'] as num).toInt(),
        reason: j['reason'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        relatedEntityId: j['related_entity_id'] as String?,
        relatedEntityType: j['related_entity_type'] as String?,
        metadata:
            (j['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  final String id;
  final int delta;
  final String reason;
  final DateTime createdAt;
  final String? relatedEntityId;
  final String? relatedEntityType;
  final Map<String, dynamic> metadata;
}

/// Read-only credit balance interface.
/// Credits ONLY move via server-side apply_credit_delta — the client NEVER
/// mutates credits directly. This contract is enforced by the DB grant:
///   GRANT EXECUTE ON FUNCTION apply_credit_delta TO service_role;
///   -- NOT to authenticated/anon roles.
abstract interface class CreditsRepository {
  /// Broadcast stream of the player's credit balance.
  /// Emits the current balance immediately on subscribe, then on every change.
  /// Throws on infrastructure failure (caller handles via AsyncValue.error).
  Stream<int> watchBalance(String playerId);

  /// One-shot fetch of the current balance.
  /// Throws on infrastructure failure.
  Future<int> fetchBalance(String playerId);
}

/// Supabase-backed CreditsRepository.
/// Uses the supabase-flutter `.stream()` API which is already a broadcast
/// stream - no additional StreamController wrapper needed (design.md §3.3).
class SupabaseCreditsRepository implements CreditsRepository {
  SupabaseCreditsRepository(this._client);
  final SupabaseClient _client;

  @visibleForTesting
  static const String watchTable = 'player_economy';
  @visibleForTesting
  static const String fetchTable = 'player_economy';
  @visibleForTesting
  static const String watchPrimaryKey = 'player_id';
  @visibleForTesting
  static const String watchFilterColumn = 'player_id';
  @visibleForTesting
  static const String fetchFilterColumn = 'player_id';

  @override
  Stream<int> watchBalance(String playerId) => _client
      .from(watchTable)
      .stream(primaryKey: [watchPrimaryKey])
      .eq(watchFilterColumn, playerId)
      .map((rows) =>
          rows.isEmpty ? 0 : (rows.first['credits'] as num).toInt());

  @override
  Future<int> fetchBalance(String playerId) async {
    final r = await _client
        .from(fetchTable)
        .select('credits')
        .eq(fetchFilterColumn, playerId)
        .single();
    return (r['credits'] as num).toInt();
  }
}
