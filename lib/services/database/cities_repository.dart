import '../supabase_service.dart';
import '../../data/cities_catalog.dart';

class CitiesRepository {
  CitiesRepository._();
  static final instance = CitiesRepository._();

  Future<List<CityEntry>> list() async {
    if (!SupabaseService.instance.isConnected) return kCitiesCatalog;
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

      // Count waitlist entries per city_slug
      final counts = <String, int>{};
      for (final r in waitlistRows) {
        final slug = r['city_slug'] as String;
        counts[slug] = (counts[slug] ?? 0) + 1;
      }

      return cityRows.map<CityEntry>((r) {
        final entry = CityEntry.fromMap(r as Map<String, dynamic>);
        return entry.copyWith(joinedCount: counts[entry.slug] ?? 0);
      }).toList();
    } catch (_) {
      return kCitiesCatalog;
    }
  }
}
