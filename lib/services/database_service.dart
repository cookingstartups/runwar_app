import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  // In-memory scratch store for in-progress GPS runs.
  final List<Map<String, dynamic>> _scratchPoints = [];

  /// No-op — Supabase client is already initialised by SupabaseService.init().
  Future<void> init() async {}

  // ── Players (maps from SQLite "profiles") ──────────────────────────────────

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('players')
        .select()
        .eq('id', userId)
        .limit(1);
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    return _normalizeProfile(list.first as Map<String, dynamic>);
  }

  Future<void> insertProfile(
    String id,
    String username,
    String city,
    String color, {
    double influence = 1,
    String? invitedAt,
    int isTester = 0,
    int isBot = 0,
    String? createdAt,
  }) async {
    final client = Supabase.instance.client;
    await client.from('players').insert({
      'id': id,
      'username': username,
      'city': city,
      'color': color,
      'invited_at': invitedAt,
      'is_tester': isTester,
      'is_bot': isBot,
      'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> upsertProfileIgnore(
    String id,
    String username,
    String city,
    String color, {
    double influence = 1,
    String? invitedAt,
    int isTester = 0,
    int isBot = 0,
  }) async {
    final client = Supabase.instance.client;
    await client.from('players').upsert(
      {
        'id': id,
        'username': username,
        'city': city,
        'color': color,
        'invited_at': invitedAt,
        'is_tester': isTester,
        'is_bot': isBot,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'id',
      ignoreDuplicates: true,
    );
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final client = Supabase.instance.client;
    // Map local column names to Supabase column names.
    final remote = <String, dynamic>{};
    patch.forEach((k, v) {
      remote[k] = v;
    });
    await client.from('players').update(remote).eq('id', userId);
  }

  Future<bool> isProfileInvited(String userId) async {
    final profile = await getProfile(userId);
    if (profile == null) return false;
    return profile['invited_at'] != null;
  }

  Future<String?> getUsername(String userId) async {
    final profile = await getProfile(userId);
    return profile?['username'] as String?;
  }

  Future<bool> hasPhoneLinked(String userId) async {
    final profile = await getProfile(userId);
    if (profile == null) return true; // no profile yet — defer to invited_at gate
    // Testers bypass phone requirement.
    if ((profile['is_tester'] as int? ?? 0) == 1) return true;
    final phone = profile['phone'] as String?;
    return phone != null && phone.isNotEmpty;
  }

  Future<Map<String, dynamic>?> getTrialState(String userId) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('players')
        .select(
          'trial_started_at, trial_days_remaining, trial_last_tick_date, '
          'freeze_tokens, freeze_refreshed_at, current_streak',
        )
        .eq('id', userId)
        .limit(1);
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    return Map<String, dynamic>.from(list.first as Map<String, dynamic>);
  }

  Future<void> updateTrialState(
    String userId, {
    String? trialStartedAt,
    int? trialDaysRemaining,
    String? trialLastTickDate,
    int? freezeTokens,
    String? freezeRefreshedAt,
    int? currentStreak,
    String? streakStartedAt,
    int? longestStreak,
  }) async {
    final patch = <String, dynamic>{};
    if (trialStartedAt != null) patch['trial_started_at'] = trialStartedAt;
    if (trialDaysRemaining != null) patch['trial_days_remaining'] = trialDaysRemaining;
    if (trialLastTickDate != null) patch['trial_last_tick_date'] = trialLastTickDate;
    if (freezeTokens != null) patch['freeze_tokens'] = freezeTokens;
    if (freezeRefreshedAt != null) patch['freeze_refreshed_at'] = freezeRefreshedAt;
    if (currentStreak != null) patch['current_streak'] = currentStreak;
    if (streakStartedAt != null) patch['streak_started_at'] = streakStartedAt;
    if (longestStreak != null) patch['longest_streak'] = longestStreak;
    if (patch.isEmpty) return;
    await updateProfile(userId, patch);
  }

  Future<void> updateInvitationStatus(
    String userId,
    String invitedAt, {
    int isTester = 1,
  }) async {
    await updateProfile(userId, {
      'invited_at': invitedAt,
      'is_tester': isTester,
    });
  }

  // ── Bots (NPC players — no auth.users FK) ──────────────────────────────────

  Future<List<Map<String, dynamic>>> getBotsByCity(String city) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('bots')
        .select()
        .eq('city', city)
        .eq('is_active', true);
    return (rows as List<dynamic>)
        .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> bulkUpsertBots(List<Map<String, dynamic>> bots) async {
    if (bots.isEmpty) return;
    final client = Supabase.instance.client;
    await client.from('bots').upsert(bots, onConflict: 'id', ignoreDuplicates: true);
  }

  // ── Zones ───────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getZonesByCity(
    String city, {
    String? status,
  }) async {
    final client = Supabase.instance.client;
    final List<dynamic> rows;
    if (status != null) {
      rows = await client
          .from('zones')
          .select()
          .eq('city', city)
          .eq('status', status);
    } else {
      rows = await client.from('zones').select().eq('city', city);
    }
    return rows
        .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getOwnedZonesByUser(
    String userId,
    String city,
  ) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('zones')
        .select()
        .eq('owner_id', userId)
        .eq('city', city)
        .eq('status', 'owned');
    return (rows as List<dynamic>)
        .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>?> getZone(String zoneId) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('zones')
        .select()
        .eq('id', zoneId)
        .limit(1);
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    return Map<String, dynamic>.from(list.first as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> getZonesByOwner(
    String ownerId, {
    int? limit,
  }) async {
    final client = Supabase.instance.client;
    final List<dynamic> rows;
    if (limit != null) {
      rows = await client
          .from('zones')
          .select()
          .eq('owner_id', ownerId)
          .limit(limit);
    } else {
      rows = await client.from('zones').select().eq('owner_id', ownerId);
    }
    return rows
        .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> insertZone(Map<String, dynamic> zone) async {
    final client = Supabase.instance.client;
    await client.from('zones').insert(zone);
  }

  Future<void> updateZone(String id, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final client = Supabase.instance.client;
    await client.from('zones').update(patch).eq('id', id);
  }

  Future<void> deleteZone(String id) async {
    final client = Supabase.instance.client;
    await client.from('zones').delete().eq('id', id);
  }

  Future<void> bulkInsertZones(List<Map<String, dynamic>> zones) async {
    if (zones.isEmpty) return;
    final client = Supabase.instance.client;
    await client.from('zones').upsert(zones, onConflict: 'id', ignoreDuplicates: true);
  }

  // ── Prefs ───────────────────────────────────────────────────────────────────

  Future<String?> getPref(String userId, String key) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('prefs')
        .select('value')
        .eq('user_id', userId)
        .eq('key', key)
        .limit(1);
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    return list.first['value'] as String?;
  }

  Future<void> setPref(String userId, String key, String value) async {
    final client = Supabase.instance.client;
    await client.from('prefs').upsert(
      {'user_id': userId, 'key': key, 'value': value},
      onConflict: 'user_id,key',
    );
  }

  // ── Runs ────────────────────────────────────────────────────────────────────

  Future<void> insertRun(Map<String, dynamic> run) async {
    final client = Supabase.instance.client;
    await client.from('runs').insert(run);
  }

  Future<List<Map<String, dynamic>>> getUserRuns(
    String userId,
    String city,
  ) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('runs')
        .select('track_json')
        .eq('user_id', userId)
        .eq('city', city);
    return (rows as List<dynamic>)
        .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
        .toList();
  }

  // ── Run scratch (in-memory) ─────────────────────────────────────────────────

  void insertScratchPoint(
    String userId,
    double lat,
    double lng,
    double? accuracy,
    String ts,
  ) {
    _scratchPoints.add({
      'user_id': userId,
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'ts': ts,
    });
  }

  List<Map<String, dynamic>> getScratchRun(String userId) {
    return _scratchPoints
        .where((r) => r['user_id'] == userId)
        .map((r) => Map<String, dynamic>.from(r))
        .toList()
      ..sort((a, b) => (a['ts'] as String).compareTo(b['ts'] as String));
  }

  void deleteScratchRun(String userId) {
    _scratchPoints.removeWhere((r) => r['user_id'] == userId);
  }

  void deleteScratchBefore(String userId, String cutoffIso) {
    _scratchPoints.removeWhere(
      (r) => r['user_id'] == userId && (r['ts'] as String).compareTo(cutoffIso) < 0,
    );
  }

  // ── Events / Telemetry ──────────────────────────────────────────────────────

  Future<void> insertEvent(
    String id,
    String? userId,
    String name, {
    Map<String, dynamic>? props,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.from('events').insert({
        'id': id,
        'user_id': userId,
        'name': name,
        'props_json': props?.toString(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Telemetry is fire-and-forget; never rethrow.
    }
  }

  // ── Feedback ────────────────────────────────────────────────────────────────

  Future<void> insertFeedback(
    String id,
    String? userId,
    String trigger,
    String rating, {
    String? note,
    String? createdAt,
  }) async {
    final client = Supabase.instance.client;
    await client.from('feedback').insert({
      'id': id,
      'user_id': userId,
      'trigger': trigger,
      'rating': rating,
      'note': note,
      'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
    });
  }

  // ── City waitlists ──────────────────────────────────────────────────────────

  Future<List<String>> getJoinedCities(String userId) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('city_waitlists')
        .select('city_slug')
        .eq('user_id', userId);
    return (rows as List<dynamic>)
        .map((r) => r['city_slug'] as String)
        .toList();
  }

  Future<void> joinCityWaitlist(String userId, String citySlug) async {
    final client = Supabase.instance.client;
    await client.from('city_waitlists').upsert(
      {
        'user_id': userId,
        'city_slug': citySlug,
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,city_slug',
      ignoreDuplicates: true,
    );
  }

  Future<void> leaveCityWaitlist(String userId, String citySlug) async {
    final client = Supabase.instance.client;
    await client.from('city_waitlists')
        .delete()
        .eq('user_id', userId)
        .eq('city_slug', citySlug);
  }

  // ── Daily mission progress ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getDailyMissions(
    String userId,
    String date,
  ) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('daily_mission_progress')
        .select()
        .eq('user_id', userId)
        .eq('date', date);
    return (rows as List<dynamic>)
        .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> upsertMissionProgress(Map<String, dynamic> row) async {
    final client = Supabase.instance.client;
    await client.from('daily_mission_progress').upsert(
      row,
      onConflict: 'user_id,date,slug',
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Normalise the Supabase `players` row to match the local profile field
  /// names used throughout the app (e.g. `display_name` → `username`).
  Map<String, dynamic> _normalizeProfile(Map<String, dynamic> row) {
    final out = Map<String, dynamic>.from(row);
    // Supabase column is `username`; fall back to `display_name` for old rows.
    if (!out.containsKey('username')) {
      out['username'] = out['display_name'] ?? '';
    }
    return out;
  }
}
