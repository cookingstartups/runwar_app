// test/_helpers/test_container.dart
//
// Phase 1 mandatory factory — every widget + integration test MUST construct
// its ProviderContainer via makeTestContainer(). Direct ProviderContainer()
// construction without overriding cityConfigProvider is forbidden in
// test/widgets/ and test/integration/ (Risk #6 mitigation; design.md §6).
//
// Phase 2 extension (design.md §5.3): adds optional Phase 2 repo overrides for
// creditsRepo, ledgerRepo, dropsRepo, superpowersRepo, offersRepo.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:runwar_app/providers/app_config_provider.dart';
import 'package:runwar_app/providers/zones_repository_provider.dart';
import 'package:runwar_app/providers/disputes_repository_provider.dart';
import 'package:runwar_app/providers/repositories.dart';
import 'package:runwar_app/services/database/models/city_config.dart';
import 'package:runwar_app/services/database/zones_repository.dart';
import 'package:runwar_app/services/database/disputes_repository.dart';
import 'package:runwar_app/services/database/credits_repository.dart';
import 'package:runwar_app/services/database/ledger_repository.dart';
import 'package:runwar_app/services/database/drops_repository.dart';
import 'package:runwar_app/services/database/superpowers_repository.dart';
import 'package:runwar_app/services/database/offers_repository.dart';

// ── Mock classes ──────────────────────────────────────────────────────────────

class MockZonesRepository extends Mock implements ZonesRepository {}

class MockDisputesRepository extends Mock implements DisputesRepository {}

// Phase 2 mocks — used for simple stub scenarios; prefer FakeXxxRepository
// subclasses in test files that need fine-grained stream control.
class MockCreditsRepository extends Mock implements CreditsRepository {}

class MockLedgerRepository extends Mock implements LedgerRepository {}

class MockDropsRepository extends Mock implements DropsRepository {}

class MockSuperpowersRepository extends Mock implements SuperpowersRepository {}

class MockOffersRepository extends Mock implements OffersRepository {}

// ── Fallback registrations ────────────────────────────────────────────────────
// Call registerFallbackValues() once per test suite (in setUpAll) so mocktail
// can handle argument matchers for custom types returned by these repos.

void registerFallbackValues() {
  // Phase 1 — no custom non-nullable types needed.
  // Phase 2 — register mocktail fallback values for types used in matcher-based
  // stubbing calls (e.g. when(repo.claim(any(), any(), any()))).
  registerFallbackValue(EarnEvent.runEnd('run-fallback'));
}

// ── Factory ───────────────────────────────────────────────────────────────────

/// Creates a [ProviderContainer] with safe test overrides.
///
/// Phase 1 overrides:
/// - [cityConfig] defaults to [CityConfig.valencia] (synchronous, no Supabase).
/// - [zonesRepo] overrides [zonesRepositoryProvider] when provided.
/// - [disputesRepo] overrides [disputesRepositoryProvider] when provided.
///
/// Phase 2 overrides (design.md §5.3):
/// - [creditsRepo] overrides [creditsRepoProvider] when provided.
/// - [ledgerRepo] overrides [ledgerRepoProvider] when provided.
/// - [dropsRepo] overrides [dropsRepoProvider] when provided.
/// - [superpowersRepo] overrides [superpowersRepoProvider] when provided.
/// - [offersRepo] overrides [offersRepoProvider] when provided.
///
/// - [overrides] accepts additional overrides (e.g. profileCacheProvider,
///   runRecorderProvider) that will be pre-seeded at construction time so that
///   subsequent [ProviderContainer.updateOverrides] calls can update them.
///   Riverpod requires that any provider passed to updateOverrides was present
///   in the initial overrides list with a matching type.
ProviderContainer makeTestContainer({
  // Phase 1
  CityConfig? cityConfig,
  ZonesRepository? zonesRepo,
  DisputesRepository? disputesRepo,
  // Phase 2
  CreditsRepository? creditsRepo,
  LedgerRepository? ledgerRepo,
  DropsRepository? dropsRepo,
  SuperpowersRepository? superpowersRepo,
  OffersRepository? offersRepo,
  // Arbitrary extras
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
    // Phase 2 repo overrides
    if (creditsRepo != null)
      creditsRepoProvider.overrideWithValue(creditsRepo),
    if (ledgerRepo != null)
      ledgerRepoProvider.overrideWithValue(ledgerRepo),
    if (dropsRepo != null)
      dropsRepoProvider.overrideWithValue(dropsRepo),
    if (superpowersRepo != null)
      superpowersRepoProvider.overrideWithValue(superpowersRepo),
    if (offersRepo != null)
      offersRepoProvider.overrideWithValue(offersRepo),
    ...overrides,
  ]);
}
