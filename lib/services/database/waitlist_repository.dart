import '../../config/supabase_config.dart';
import '../database_service.dart';
import '../supabase_service.dart';

class WaitlistRepository {
  WaitlistRepository._();
  static final instance = WaitlistRepository._();

  Future<void> joinCities(
    String userId,
    List<String> slugs, {
    String? referralSourceCode,
  }) async {
    // Always persist remotely first — never throws.
    for (final slug in slugs) {
      await DatabaseService.instance.joinCityWaitlist(userId, slug);
    }
    // Best-effort remote sync via edge function.
    if (SupabaseService.instance.isConnected) {
      try {
        await SupabaseService.instance.supabase.functions.invoke(
          SupabaseConfig.fnJoinCityWaitlists,
          body: {
            'slugs': slugs,
            if (referralSourceCode != null)
              'referral_source_code': referralSourceCode,
          },
        );
      } catch (_) {
        // Sync failure is non-fatal; Supabase record is the source of truth.
      }
    }
  }

  Future<List<String>> joinedCitySlugs(String userId) async {
    // Read from Supabase (always available when connected).
    final remote = await DatabaseService.instance.getJoinedCities(userId);
    final slugs = remote.toSet();

    // Merge remote direct query when connected.
    if (SupabaseService.instance.isConnected) {
      try {
        final rows = await SupabaseService.instance.supabase
            .from('city_waitlists')
            .select('city_slug')
            .eq('user_id', userId);
        for (final r in rows) {
          slugs.add(r['city_slug'] as String);
        }
      } catch (_) {}
    }
    return slugs.toList();
  }
}
