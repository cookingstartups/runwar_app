import '../supabase_service.dart';
import '../database_service.dart';
import '../../data/cities_catalog.dart';

class CitiesRepository {
  CitiesRepository._();
  static final instance = CitiesRepository._();

  Future<List<CityEntry>> list() async {
    // Always seed local counts first so the current user's joins are reflected
    // even when Supabase RLS hides other users' rows.
    final localCounts = await _localCounts();

    if (!SupabaseService.instance.isConnected) {
      return kCitiesCatalog
          .map((e) => e.copyWith(joinedCount: localCounts[e.slug] ?? e.joinedCount))
          .toList();
    }
    try {
      final results = await Future.wait([
        SupabaseService.instance.supabase
            .from('cities')
            .select()
            .order('is_unlocked', ascending: false)
            .order('name'),
        SupabaseService.instance.supabase
            .from('city_waitlists')
            .select('city_slug'),
      ]);

      final cityRows = results[0] as List<dynamic>;
      final waitlistRows = results[1] as List<dynamic>;

      // Count remote entries per city_slug, then floor with local counts.
      final counts = <String, int>{};
      for (final r in waitlistRows) {
        final slug = r['city_slug'] as String;
        counts[slug] = (counts[slug] ?? 0) + 1;
      }
      // Merge: take the max so local data is never lower than what the user
      // themselves contributed (guards against RLS returning 0 rows).
      for (final entry in localCounts.entries) {
        if ((counts[entry.key] ?? 0) < entry.value) {
          counts[entry.key] = entry.value;
        }
      }

      return cityRows.map<CityEntry>((r) {
        final entry = CityEntry.fromMap(r as Map<String, dynamic>);
        return entry.copyWith(joinedCount: counts[entry.slug] ?? 0);
      }).toList();
    } catch (_) {
      return kCitiesCatalog
          .map((e) => e.copyWith(joinedCount: localCounts[e.slug] ?? e.joinedCount))
          .toList();
    }
  }

  Future<Map<String, int>> _localCounts() async {
    try {
      // Use Supabase-backed getJoinedCities for current user.
      final userId = SupabaseService.instance.currentUserId;
      if (userId == null) return {};
      final slugs = await DatabaseService.instance.getJoinedCities(userId);
      final counts = <String, int>{};
      for (final slug in slugs) {
        counts[slug] = (counts[slug] ?? 0) + 1;
      }
      return counts;
    } catch (_) {
      return {};
    }
  }
}
