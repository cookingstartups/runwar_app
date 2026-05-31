// lib/providers/disputes_repository_provider.dart
//
// DisputesRepository provider. Design.md §5.
// Offline path not required in Phase 1 — always returns Supabase implementation.
// Offline: watchOpenForZone stream yields null once (label renders SizedBox.shrink).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database/disputes_repository.dart';
import '../services/database/disputes_repository_supabase.dart';

/// Provides the SupabaseDisputesRepository.
/// ref.onDispose owns the lifecycle.
final disputesRepositoryProvider = Provider<DisputesRepository>((ref) {
  final repo = SupabaseDisputesRepository();
  ref.onDispose(repo.dispose);
  return repo;
});
