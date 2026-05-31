// lib/providers/economy/credits_provider.dart
//
// StreamProvider.family for live credit balance.
// Phase 2 design.md §5.1. Key: playerId (String).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories.dart';

/// Live credit balance for [playerId].
/// Rebuilds widgets on every balance change via Supabase Realtime.
/// autoDispose ensures the subscription stops when all listeners unmount.
final creditsBalanceProvider = StreamProvider.family<int, String>(
  (ref, playerId) => ref.read(creditsRepoProvider).watchBalance(playerId),
);
