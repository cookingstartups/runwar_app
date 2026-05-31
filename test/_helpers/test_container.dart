// test/_helpers/test_container.dart
//
// Phase 1 mandatory factory — every widget + integration test MUST construct
// its ProviderContainer via makeTestContainer(). Direct ProviderContainer()
// construction without overriding cityConfigProvider is forbidden in
// test/widgets/ and test/integration/ (Risk #6 mitigation; design.md §6).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:runwar_app/providers/app_config_provider.dart';
import 'package:runwar_app/providers/zones_repository_provider.dart';
import 'package:runwar_app/providers/disputes_repository_provider.dart';
import 'package:runwar_app/services/database/models/city_config.dart';
import 'package:runwar_app/services/database/zones_repository.dart';
import 'package:runwar_app/services/database/disputes_repository.dart';

// ── Mock classes ──────────────────────────────────────────────────────────────

class MockZonesRepository extends Mock implements ZonesRepository {}

class MockDisputesRepository extends Mock implements DisputesRepository {}

// ── Fallback registrations ────────────────────────────────────────────────────
// Call registerFallbackValues() once per test suite (in setUpAll) so mocktail
// can handle argument matchers for custom types returned by these repos.

void registerFallbackValues() {
  // No custom non-nullable argument types need registering for these repos
  // in Phase 1. Add here if Phase 2 adds matcher-based stubbing for Zone,
  // Dispute, etc.
}

// ── Factory ───────────────────────────────────────────────────────────────────

/// Creates a [ProviderContainer] with safe test overrides.
///
/// - [cityConfig] defaults to [CityConfig.valencia] (synchronous, no Supabase).
/// - [zonesRepo] overrides [zonesRepositoryProvider] when provided.
/// - [disputesRepo] overrides [disputesRepositoryProvider] when provided.
/// - [overrides] accepts additional overrides (e.g. profileCacheProvider,
///   runRecorderProvider) that will be pre-seeded at construction time so that
///   subsequent [ProviderContainer.updateOverrides] calls can update them.
///   Riverpod requires that any provider passed to updateOverrides was present
///   in the initial overrides list with a matching type.
ProviderContainer makeTestContainer({
  CityConfig? cityConfig,
  ZonesRepository? zonesRepo,
  DisputesRepository? disputesRepo,
  List<Override> overrides = const [],
}) {
  return ProviderContainer(overrides: [
    cityConfigProvider.overrideWith(
      (_) async => cityConfig ?? CityConfig.valencia,
    ),
    if (zonesRepo != null)
      zonesRepositoryProvider.overrideWithValue(zonesRepo),
    if (disputesRepo != null)
      disputesRepositoryProvider.overrideWithValue(disputesRepo),
    ...overrides,
  ]);
}
