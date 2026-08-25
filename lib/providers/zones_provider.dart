import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/database/models/zone.dart';
import '../services/profile_service.dart';
import 'zones_repository_provider.dart';

/// AC-16, AC-17. autoDispose so the polling timer stops when the shell
/// unmounts (sign-out). IndexedStack keeps both tab children mounted
/// during Map<->Profile switches -> the watcher count never drops to zero
/// on a tab switch, so autoDispose only fires on actual shell teardown.
///
/// Backed by ZonesRepository (Supabase Realtime or SQLite polling depending
/// on connectivity — branch lives in zonesRepositoryProvider).
final zonesProvider =
    StreamProvider.autoDispose.family<List<Zone>, String>(
  (ref, city) => ref.watch(zonesRepositoryProvider).watchByCity(city),
);

/// Caches owner profile lookups for polygon color (AC-6) and zone-tap
/// bottom sheet (AC-7). Not autoDispose — owners persist across the
/// shell's lifetime and we want the cache hot.
final profileCacheProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, ownerId) => ProfileService.instance.fetchProfile(ownerId),
);

/// Merges a fresh [zones] snapshot with [pending] outlines - outlines a
/// successful claim registered this session (rw_app-territory-vanish) that
/// [zonesProvider]'s Realtime/refetch stream has not yet caught up with.
///
/// This is the render-time counterpart of the scan-time merge
/// RunRecorderNotifier.ownedZoneEdgesProvider already performs for lasso.dart
/// - that closure is consumed only by the GPS scan and stops firing the
/// moment recording stops, so nothing prunes it post-Finish; MapScreen must
/// merge independently, as a pure read with no side effect on [pending].
///
/// A zone id present in [zones] is never duplicated from [pending] - the
/// fresh snapshot always wins once it lands. Every other pending outline is
/// synthesized into a placeholder [Zone] (status: owned, ownerId: [userId])
/// so it renders exactly like any other owned zone until the real row
/// arrives.
List<Zone> mergePendingOwnedZoneEdges(
  List<Zone> zones,
  Map<String, List<List<LatLng>>> pending,
  String userId,
) {
  if (pending.isEmpty) return zones;
  final knownIds = zones.map((z) => z.id).toSet();
  final synthesized = <Zone>[
    for (final entry in pending.entries)
      if (!knownIds.contains(entry.key) && entry.value.isNotEmpty)
        Zone(
          id: entry.key,
          ownerId: userId,
          city: '',
          influenceLevel: 1,
          status: ZoneStatus.owned,
          points: entry.value.first,
          outlines: entry.value,
        ),
  ];
  if (synthesized.isEmpty) return zones;
  return [...zones, ...synthesized];
}
