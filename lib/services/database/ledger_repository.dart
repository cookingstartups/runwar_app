// lib/services/database/ledger_repository.dart
//
// LedgerRepository — debug-surface read of credit_transactions.
// Phase 2 design.md §3.2. Separated from CreditsRepository so wallet/debug
// UI has a clean dependency boundary; balance stream doesn't need the ledger.
//
// CI GATE: supabase_flutter import permitted here (lib/services/database/).

import 'package:supabase_flutter/supabase_flutter.dart';

import 'credits_repository.dart' show LedgerEntry;

/// Paged read-access to the credit_transactions immutable ledger.
/// Phase 2: debug-only surface. Full wallet UI is post-MVP.
abstract interface class LedgerRepository {
  /// Returns the [limit] most recent ledger entries for [playerId], newest first.
  /// Throws on infrastructure failure.
  Future<List<LedgerEntry>> fetchRecent(String playerId, {int limit = 50});
}

/// Supabase-backed LedgerRepository.
class SupabaseLedgerRepository implements LedgerRepository {
  SupabaseLedgerRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<LedgerEntry>> fetchRecent(String playerId,
      {int limit = 50}) async {
    final rows = await _client
        .from('credit_transactions')
        .select()
        .eq('user_id', playerId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map(LedgerEntry.fromJson)
        .toList();
  }
}
