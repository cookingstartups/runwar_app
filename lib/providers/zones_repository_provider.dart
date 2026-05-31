// lib/providers/zones_repository_provider.dart
//
// ZonesRepository provider — online/offline branch lives here.
// Design.md §5.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';
import '../services/database/zones_repository.dart';
import '../services/database/zones_repository_supabase.dart';
import '../services/database/zones_repository_local.dart';

/// Provides the correct ZonesRepository implementation based on connectivity.
/// Supabase when connected, local SQLite fallback when offline.
/// ref.onDispose owns the lifecycle — consumers must never call dispose directly.
final zonesRepositoryProvider = Provider<ZonesRepository>((ref) {
  final repo = SupabaseService.instance.isConnected
      ? SupabaseZonesRepository()
      : LocalZonesRepository();
  ref.onDispose(repo.dispose);
  return repo;
});
