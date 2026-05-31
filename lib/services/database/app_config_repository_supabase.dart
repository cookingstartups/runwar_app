// lib/services/database/app_config_repository_supabase.dart
//
// Supabase-backed AppConfigRepository implementation.
// Design.md §1 SupabaseAppConfigRepository spec.
// 60-second in-memory cache; invalidateCache() clears it.
//
// CI GATE: supabase_flutter import is allowed here (lib/services/ layer).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import 'repository.dart';
import 'app_config_repository.dart';
import 'models/city_config.dart';

/// Supabase-backed AppConfigRepository with a 60-second in-memory cache.
///
/// Reads `SELECT config FROM city_config LIMIT 1` (the jsonb_object_agg view
/// created in migration 0015). Caches the parsed CityConfig for 60 seconds.
/// invalidateCache() clears the tuple; next call re-queries.
class SupabaseAppConfigRepository implements AppConfigRepository {
  SupabaseAppConfigRepository();

  static const Duration _cacheDuration = Duration(seconds: 60);

  CityConfig? _cache;
  DateTime? _cacheExpiresAt;

  SupabaseClient get _client => SupabaseService.instance.supabase;

  @override
  Future<RepoResult<CityConfig>> loadCityConfig() async {
    // Return cached value if still valid.
    final now = DateTime.now();
    if (_cache != null &&
        _cacheExpiresAt != null &&
        now.isBefore(_cacheExpiresAt!)) {
      return RepoResult.ok(_cache!);
    }

    try {
      final rows = await _client.from('city_config').select('config').limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) {
        return RepoResult.err(RepoError.notFound,
            detail: 'city_config view returned no rows');
      }
      final config =
          CityConfig.fromJsonRow(list.first as Map<String, dynamic>);
      _cache = config;
      _cacheExpiresAt = now.add(_cacheDuration);
      return RepoResult.ok(config);
    } catch (e) {
      debugPrint('[SupabaseAppConfigRepository] loadCityConfig error: $e');
      return RepoResult.err(RepoError.network, detail: e.toString());
    }
  }

  @override
  void invalidateCache() {
    _cache = null;
    _cacheExpiresAt = null;
  }
}
