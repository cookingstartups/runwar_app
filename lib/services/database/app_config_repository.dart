// lib/services/database/app_config_repository.dart
//
// Abstract interface for app configuration. Design.md §1.
// Implementation: SupabaseAppConfigRepository (60s in-memory cache).

import 'repository.dart';
import 'models/city_config.dart';

abstract interface class AppConfigRepository {
  /// Loads the city config from the city_config view.
  /// Returns Ok(CityConfig) on success; Err on failure.
  /// Implementations must cache the result for 60 seconds.
  Future<RepoResult<CityConfig>> loadCityConfig();

  /// Clears the in-memory cache. Next call to [loadCityConfig] re-queries.
  void invalidateCache();
}
