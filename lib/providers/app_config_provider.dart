// lib/providers/app_config_provider.dart
//
// App configuration providers. Design.md §5.
// cityConfigProvider: 3-second timeout, falls back to CityConfig.valencia.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database/app_config_repository.dart';
import '../services/database/app_config_repository_supabase.dart';
import '../services/database/models/city_config.dart';

/// Provides the AppConfigRepository (Supabase-backed with 60s cache).
final appConfigRepositoryProvider =
    Provider<AppConfigRepository>((_) => SupabaseAppConfigRepository());

/// FutureProvider that loads CityConfig with a 3-second timeout.
/// On timeout or any error, falls back to CityConfig.valencia.
/// Preloaded in main.dart and overridden synchronously so the first frame
/// already has a resolved config value.
final cityConfigProvider = FutureProvider<CityConfig>((ref) async {
  final repo = ref.read(appConfigRepositoryProvider);
  try {
    final r =
        await repo.loadCityConfig().timeout(const Duration(seconds: 3));
    return r.valueOr(CityConfig.valencia);
  } on TimeoutException {
    return CityConfig.valencia;
  }
});
