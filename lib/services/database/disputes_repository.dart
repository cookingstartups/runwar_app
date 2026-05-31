// lib/services/database/disputes_repository.dart
//
// Abstract interface for dispute data access. Design.md §1.
// Phase 1: read-only — dispute creation/resolution is done by Edge functions.
// Implementation: SupabaseDisputesRepository.

import 'repository.dart';
import 'models/dispute.dart';

abstract interface class DisputesRepository {
  /// Fetches the open dispute for [zoneId], if any.
  /// Returns Ok(null) when no open dispute exists (resolved_at IS NOT NULL or no row).
  /// Returns Err(network) on client failure.
  Future<RepoResult<Dispute?>> fetchOpenForZone(String zoneId);

  /// Returns a broadcast stream of the open dispute for [zoneId].
  /// Emits null when the zone has no open dispute.
  /// Re-emits on every Realtime change to the disputes table for this zone.
  Stream<Dispute?> watchOpenForZone(String zoneId);

  /// Fetches a single dispute by [id].
  Future<RepoResult<Dispute>> fetchById(String id);

  /// Releases all resources. Called by Riverpod via ref.onDispose. Idempotent.
  Future<void> dispose();
}
