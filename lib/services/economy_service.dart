// lib/services/economy_service.dart
//
// EconomyService — pure observer over credit balance and ledger.
// Phase 2 design.md §4.1.
//
// CONTRACT:
//   - Credits ONLY move via server-side apply_credit_delta (SECURITY DEFINER).
//   - EconomyService NEVER mutates credits client-side.
//   - No supabase_flutter import — calls repos only.

import 'package:flutter/foundation.dart';

import 'database/credits_repository.dart';
import 'database/ledger_repository.dart';

/// Pure observer over the player's credit state.
///
/// Owns: balance() stream, currentBalance(), ledger(), balanceDeltas().
/// Does NOT own credit mutation — that is entirely server-side via edge fns.
class EconomyService {
  EconomyService({
    required CreditsRepository credits,
    required LedgerRepository ledger,
  })  : _credits = credits,
        _ledger = ledger;

  final CreditsRepository _credits;
  final LedgerRepository _ledger;

  /// Live stream of [playerId]'s credit balance.
  Stream<int> balance(String playerId) => _credits.watchBalance(playerId);

  /// One-shot fetch of [playerId]'s current balance.
  Future<int> currentBalance(String playerId) =>
      _credits.fetchBalance(playerId);

  /// Most recent [limit] ledger entries for [playerId].
  Future<List<LedgerEntry>> ledger(String playerId, {int limit = 50}) =>
      _ledger.fetchRecent(playerId, limit: limit);

  /// Emits successive (previous, next) balance pairs — useful for animation
  /// cues (e.g. credits_chip pulse on credit gain).
  Stream<({int previous, int next})> balanceDeltas(String playerId) {
    int? previous;
    return _credits.watchBalance(playerId).map((next) {
      final tuple = (previous: previous ?? next, next: next);
      previous = next;
      return tuple;
    });
  }

  @visibleForTesting
  CreditsRepository get debugCredits => _credits;
}
