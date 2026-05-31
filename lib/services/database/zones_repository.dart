// lib/services/database/zones_repository.dart
//
// Abstract interface for zone data access. Design.md §1.
// Implementations: SupabaseZonesRepository, LocalZonesRepository.
// Consumers (providers, widgets) only reference this interface — never implementations.

import 'repository.dart';
import 'models/zone.dart';

abstract interface class ZonesRepository {
  /// Fetches all zones for [city] as a one-shot snapshot.
  Future<RepoResult<List<Zone>>> fetchByCity(String city);

  /// Returns a broadcast stream of zone lists for [city].
  /// The stream re-emits on every Realtime change (Supabase) or polling tick (local).
  /// First subscriber triggers the initial fetch + subscription.
  /// Last subscriber teardown closes the underlying channel.
  Stream<List<Zone>> watchByCity(String city);

  /// Fetches a single zone by [id].
  Future<RepoResult<Zone>> fetchById(String id);

  /// Releases all resources: cancels subscriptions, closes StreamControllers.
  /// Called by Riverpod via ref.onDispose. Idempotent.
  Future<void> dispose();
}
