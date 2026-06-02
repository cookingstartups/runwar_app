import 'package:sqflite/sqflite.dart';
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
    final now = DateTime.now().toIso8601String();
    // Always persist locally first — never throws.
    for (final slug in slugs) {
      await DatabaseService.instance.db.insert(
        'city_waitlists',
        {'user_id': userId, 'city_slug': slug, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    // Best-effort Supabase sync.
    if (SupabaseService.instance.isConnected) {
      try {
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
            .upsert(rows, onConflict: 'city_waitlists_user_id_city_slug_key');
      } catch (_) {
        // Sync failure is non-fatal; local record is the source of truth.
      }
    }
  }

  Future<List<String>> joinedCitySlugs(String userId) async {
    // Read local SQLite first (always available).
    final local = await DatabaseService.instance.db.query(
      'city_waitlists',
      columns: ['city_slug'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final slugs = local.map((r) => r['city_slug'] as String).toSet();

    // Merge remote when connected.
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
