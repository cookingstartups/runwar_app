// test/services/database/app_config_repository_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Each test maps to one GIVEN/WHEN/THEN from design.md §1 + phase spec §8
// (lines 950-954).
//
// Design contract (design.md §1):
//   AppConfigRepository interface:
//     Future<RepoResult<CityConfig>> loadCityConfig();
//     void invalidateCache();
//
//   SupabaseAppConfigRepository:
//     - Reads city_config view (jsonb row with 7 keys)
//     - 60-second in-memory cache: second call within 60s reuses cached value
//     - invalidateCache() clears cache; next call re-queries
//     - Returns Err on client failure; callers fall back to CityConfig.valencia

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/app_config_repository.dart';
import 'package:runwar_app/services/database/models/city_config.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// A valid city_config JSONB blob as returned by migration 0015's view.
/// The view emits a single row with one `config` jsonb column.
Map<String, dynamic> _validConfigRow() => {
      'config': {
        'launch_city': 'Valencia',
        'city_center_lat': 39.4699,
        'city_center_lng': -0.3763,
        'city_bounds_north': 39.55,
        'city_bounds_south': 39.38,
        'city_bounds_east': -0.29,
        'city_bounds_west': -0.50,
      },
    };

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// A controllable AppConfigRepository fake that tracks client call count
/// and supports cache bypass via invalidateCache().
class FakeAppConfigRepository implements AppConfigRepository {
  final Map<String, dynamic>? _row;
  final bool _throwOnFetch;

  int fetchCallCount = 0;
  CityConfig? _cache;
  DateTime? _cacheExpiresAt;

  static const Duration _cacheDuration = Duration(seconds: 60);

  FakeAppConfigRepository({
    Map<String, dynamic>? row,
    bool throwOnFetch = false,
  })  : _row = row,
        _throwOnFetch = throwOnFetch;

  @override
  Future<RepoResult<CityConfig>> loadCityConfig() async {
    // Return cache if still valid.
    final now = DateTime.now();
    if (_cache != null &&
        _cacheExpiresAt != null &&
        now.isBefore(_cacheExpiresAt!)) {
      return RepoResult.ok(_cache!);
    }

    fetchCallCount++;

    if (_throwOnFetch) {
      return RepoResult.err(RepoError.network,
          detail: 'Supabase unreachable');
    }

    if (_row == null) {
      return RepoResult.err(RepoError.notFound);
    }

    final config = CityConfig.fromJsonRow(_row!);
    _cache = config;
    _cacheExpiresAt = now.add(_cacheDuration);
    return RepoResult.ok(config);
  }

  @override
  void invalidateCache() {
    _cache = null;
    _cacheExpiresAt = null;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AppConfigRepository', () {
    // GIVEN a valid JSONB row from the city_config view
    // WHEN loadCityConfig is called
    // THEN parses it into CityConfig with correct center lat/lng and bounds
    test('parses valid JSONB row into CityConfig with correct center and bounds', () async {
      final repo = FakeAppConfigRepository(row: _validConfigRow());

      final result = await repo.loadCityConfig();

      expect(result, isA<Ok<CityConfig>>());
      final config = (result as Ok<CityConfig>).value;
      expect(config.launchCity, equals('Valencia'));
      expect(config.center.latitude, closeTo(39.4699, 0.0001));
      expect(config.center.longitude, closeTo(-0.3763, 0.0001));
      // Bounds: north > south, east > west.
      expect(config.bounds.north, closeTo(39.55, 0.001));
      expect(config.bounds.south, closeTo(39.38, 0.001));
      expect(config.bounds.east, closeTo(-0.29, 0.001));
      expect(config.bounds.west, closeTo(-0.50, 0.001));
    });

    // GIVEN a repository that hits a 60-second cache after the first call
    // WHEN loadCityConfig is called twice within 60 seconds
    // THEN only one client fetch is performed (cache hit on second call)
    test('second loadCityConfig call within 60s reuses cache (single client call)', () async {
      final repo = FakeAppConfigRepository(row: _validConfigRow());

      await repo.loadCityConfig(); // first call — fetches from "client"
      await repo.loadCityConfig(); // second call — must hit cache

      expect(repo.fetchCallCount, equals(1),
          reason: 'Cache should have prevented a second client fetch within 60s');
    });

    // GIVEN a repository whose cache has been invalidated
    // WHEN loadCityConfig is called after invalidateCache()
    // THEN a fresh fetch is performed (fetchCallCount increments to 2)
    test('invalidateCache forces a re-query on next loadCityConfig call', () async {
      final repo = FakeAppConfigRepository(row: _validConfigRow());

      await repo.loadCityConfig(); // first fetch
      repo.invalidateCache();
      await repo.loadCityConfig(); // must fetch again

      expect(repo.fetchCallCount, equals(2),
          reason: 'invalidateCache must clear the cache so the next call re-queries');
    });

    // GIVEN a client that throws on fetch
    // WHEN loadCityConfig is called and then valueOr is applied
    // THEN returns CityConfig.valencia as the fallback value
    test('valueOr returns CityConfig.valencia when client throws', () async {
      final repo = FakeAppConfigRepository(throwOnFetch: true);

      final result = await repo.loadCityConfig();
      final config = result.valueOr(CityConfig.valencia);

      expect(config.launchCity, equals('Valencia'));
      expect(config.center.latitude, closeTo(39.4699, 0.0001));
      expect(config.center.longitude, closeTo(-0.3763, 0.0001));
    });

    // GIVEN a 60-second cache window
    // WHEN the cache expires (simulated with fake_async)
    // THEN the next loadCityConfig call fetches fresh data
    test('cache expires after 60 seconds and triggers fresh fetch', () {
      fakeAsync((async) {
        final repo = FakeAppConfigRepository(row: _validConfigRow());

        // First call populates cache.
        repo.loadCityConfig();
        async.flushMicrotasks();
        expect(repo.fetchCallCount, equals(1));

        // Advance 59 seconds — still within cache window.
        async.elapse(const Duration(seconds: 59));
        repo.loadCityConfig();
        async.flushMicrotasks();
        expect(repo.fetchCallCount, equals(1),
            reason: 'Cache should still be valid at 59s');

        // Advance past the 60s expiry.
        async.elapse(const Duration(seconds: 2));
        repo.loadCityConfig();
        async.flushMicrotasks();
        expect(repo.fetchCallCount, equals(2),
            reason: 'Cache expired at 60s; should have fetched again');
      });
    });
  });
}
