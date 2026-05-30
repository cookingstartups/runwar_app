import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/zones_service.dart';
import '../services/realtime_zones_service.dart';
import '../services/supabase_service.dart';
import '../services/profile_service.dart';

/// AC-16, AC-17. autoDispose so the polling timer stops when the shell
/// unmounts (sign-out). IndexedStack keeps both tab children mounted
/// during Map<->Profile switches -> the watcher count never drops to zero
/// on a tab switch, so autoDispose only fires on actual shell teardown.
///
/// When Supabase is connected the stream is backed by Realtime (sub-second
/// updates); otherwise it falls back to the 5-second SQLite polling stream.
final zonesProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
  (ref, city) {
    if (SupabaseService.instance.isConnected) {
      return RealtimeZonesService.instance.watchZonesByCity(city);
    }
    return ZonesService.instance.watchZonesByCity(city);
  },
);

/// Caches owner profile lookups for polygon color (AC-6) and zone-tap
/// bottom sheet (AC-7). Not autoDispose — owners persist across the
/// shell's lifetime and we want the cache hot.
final profileCacheProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, ownerId) => ProfileService.instance.fetchProfile(ownerId),
);
