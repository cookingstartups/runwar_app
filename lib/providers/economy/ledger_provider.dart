// lib/providers/economy/ledger_provider.dart
//
// FutureProvider.family for credit transaction ledger.
// Phase 2 design.md §5.1. Key: playerId (String).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/database/credits_repository.dart' show LedgerEntry;
import '../repositories.dart';

/// Most recent 50 ledger entries for [playerId], newest-first.
/// autoDispose: re-fetches when UI re-mounts (wallet screen pull-to-refresh).
final ledgerProvider = FutureProvider.family<List<LedgerEntry>, String>(
  (ref, playerId) => ref.read(ledgerRepoProvider).fetchRecent(playerId),
);
