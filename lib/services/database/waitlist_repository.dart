import '../supabase_service.dart';

class WaitlistRepository {
  WaitlistRepository._();
  static final instance = WaitlistRepository._();

  Future<void> joinCities(
    String userId,
    List<String> slugs, {
    String? referralSourceCode,
  }) async {
    final rows = slugs
        .map((s) => {
              'user_id': userId,
              'city_slug': s,
              if (referralSourceCode != null)
                'referral_source_code': referralSourceCode,
            })
        .toList();
    await SupabaseService.instance.supabase
        .from('city_waitlists')
        .upsert(rows, onConflict: 'user_id,city_slug');
  }

  Future<List<String>> joinedCitySlugs(String userId) async {
    if (!SupabaseService.instance.isConnected) return [];
    try {
      final rows = await SupabaseService.instance.supabase
          .from('city_waitlists')
          .select('city_slug')
          .eq('user_id', userId);
      return rows.map<String>((r) => r['city_slug'] as String).toList();
    } catch (_) {
      return [];
    }
  }
}
