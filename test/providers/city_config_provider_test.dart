// test/providers/city_config_provider_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Each test maps to one GIVEN/WHEN/THEN from design.md §5 + phase spec §8.
//
// Design contract (design.md §5):
//   cityConfigProvider = FutureProvider<CityConfig>((ref) async {
//     final r = await repo.loadCityConfig().timeout(Duration(seconds: 3));
//     return r.valueOr(CityConfig.valencia);
//   });
//   - 3-second timeout; TimeoutException → falls back to CityConfig.valencia
//   - CityConfig.valencia: lat=39.4699, lng=-0.3763 (static final, not const)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:runwar_app/providers/app_config_provider.dart';
import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/app_config_repository.dart';
import 'package:runwar_app/services/database/models/city_config.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// Simulates a slow AppConfigRepository that never resolves within 3s.
class SlowAppConfigRepository implements AppConfigRepository {
  @override
  Future<RepoResult<CityConfig>> loadCityConfig() async {
    // Hangs for 10 seconds — longer than the 3s timeout in cityConfigProvider.
    await Future<void>.delayed(const Duration(seconds: 10));
    return RepoResult.ok(CityConfig.valencia);
  }

  @override
  void invalidateCache() {}
}

/// Responds immediately with a real Valencia config.
class FastAppConfigRepository implements AppConfigRepository {
  @override
  Future<RepoResult<CityConfig>> loadCityConfig() async {
    return RepoResult.ok(CityConfig.valencia);
  }

  @override
  void invalidateCache() {}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('cityConfigProvider', () {
    // GIVEN AppConfigRepository takes longer than 3 seconds to respond
    // WHEN cityConfigProvider awaits loadCityConfig with a 3s timeout
    // THEN returns CityConfig.valencia as the timeout fallback
    test('returns CityConfig.valencia on 3s timeout', () async {
      final container = ProviderContainer(overrides: [
        appConfigRepositoryProvider.overrideWithValue(SlowAppConfigRepository()),
      ]);
      addTearDown(container.dispose);

      // The provider has a 3s .timeout(); we give it 4s wall-clock
      // to resolve (the fake resolves after 10s so it will always time out).
      final config = await container
          .read(cityConfigProvider.future)
          .timeout(const Duration(seconds: 4));

      expect(config.launchCity, equals('Valencia'));
      expect(config.center.latitude, closeTo(39.4699, 0.0001));
      expect(config.center.longitude, closeTo(-0.3763, 0.0001));
    });

    // GIVEN AppConfigRepository responds within 3 seconds
    // WHEN cityConfigProvider resolves
    // THEN returns the real CityConfig from the repository
    test('returns real CityConfig when repository responds within 3s', () async {
      final container = ProviderContainer(overrides: [
        appConfigRepositoryProvider
            .overrideWithValue(FastAppConfigRepository()),
      ]);
      addTearDown(container.dispose);

      final config = await container.read(cityConfigProvider.future);

      expect(config.launchCity, equals('Valencia'));
      expect(config.center.latitude, closeTo(39.4699, 0.0001));
      expect(config.center.longitude, closeTo(-0.3763, 0.0001));
    });

    // GIVEN CityConfig.valencia is the locked fallback
    // WHEN its literal values are accessed
    // THEN lat=39.4699 and lng=-0.3763 (verbatim from design.md §1)
    test('CityConfig.valencia has lat=39.4699, lng=-0.3763', () {
      final v = CityConfig.valencia;

      expect(v.center.latitude, closeTo(39.4699, 0.0001),
          reason: 'Latitude must match locked Valencia coordinates');
      expect(v.center.longitude, closeTo(-0.3763, 0.0001),
          reason: 'Longitude must match locked Valencia coordinates');
      expect(v.launchCity, equals('Valencia'));
    });
  });
}
