import '../supabase_service.dart';
import '../../data/cities_catalog.dart';

class CitiesRepository {
  CitiesRepository._();
  static final instance = CitiesRepository._();

  Future<List<CityEntry>> list() async {
    if (!SupabaseService.instance.isConnected) return kCitiesCatalog;
    try {
      final rows = await SupabaseService.instance.supabase
          .from('cities')
          .select()
          .order('is_unlocked', ascending: false)
          .order('name');
      return rows.map<CityEntry>((r) => CityEntry.fromMap(r)).toList();
    } catch (_) {
      return kCitiesCatalog;
    }
  }
}
