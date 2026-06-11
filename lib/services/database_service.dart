import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Child table column sets (used by updateProfile routing) ───────────────────

const _kIdentityCols = <String>{
  'username', 'color', 'phone', 'bio', 'avatar_url', 'avatar_metadata',
  'referral_code', 'is_active', 'is_tester', 'invited_at',
};
const _kEconomyCols = <String>{
  'credits', 'total_kickback_earned', 'subscription_tier',
  'subscription_expires', 'reputation',
};
const _kProgressCols = <String>{
  'score', 'first_mission_completed_at', 'first_attack_completed_at',
};
const _kStreaksCols = <String>{
  'streak', 'longest_streak', 'last_login_at', 'streak_started_at',
  'milestones_claimed', 'freeze_tokens', 'freeze_refreshed_at',
};
const _kTrialCols = <String>{
  'trial_started_at', 'trial_days_remaining', 'trial_last_tick_date',
};

// ── Patch normalisation ───────────────────────────────────────────────────────

/// Strips any character that is not `+` or a digit from phone values, and
/// trims leading/trailing whitespace from username values.
final RegExp _kPhoneStrip = RegExp(r'[^+0-9]');

/// Normalises a [DatabaseService.updateProfile] patch map before it is sent
/// to Supabase:
///   - AC-2: strips non-`+`/digit characters from any `phone` value.
///   - AC-4: trims leading/trailing whitespace from any `username` value.
///
/// Returns a new map; the original [patch] is never mutated.
///
/// Exposed as a top-level function so it can be unit-tested without
/// initialising the Supabase singleton.
@visibleForTesting
Map<String, dynamic> normaliseProfilePatch(Map<String, dynamic> patch) {
  final remote = <String, dynamic>{...patch};
  if (remote.containsKey('phone') && remote['phone'] is String) {
    remote['phone'] = (remote['phone'] as String).replaceAll(_kPhoneStrip, '');
  }
  if (remote.containsKey('username') && remote['username'] is String) {
    remote['username'] = (remote['username'] as String).trim();
  }
  return remote;
}

// ── Daily mission progress test constants ─────────────────────────────────────

@visibleForTesting
const String kGetDailyMissionsFilterColumn = 'user_id';
@visibleForTesting
const String kUpsertMissionProgressOnConflict = 'user_id,mission_id,date';
@visibleForTesting
const String kUpsertMissionProgressPlayerKey = 'user_id';
@visibleForTesting
const String kUpsertMissionProgressMissionKey = 'mission_id';

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
        .select(
          '*, '
          'player_economy(credits, total_kickback_earned, subscription_tier, subscription_expires, reputation), '
          'player_progress(score, first_mission_completed_at, first_attack_completed_at), '
          'player_streaks(streak, longest_streak, last_login_at, streak_started_at, milestones_claimed, freeze_tokens, freeze_refreshed_at), '
          'player_trial(trial_started_at, trial_days_remaining, trial_last_tick_date)',
        )
        .eq('user_id', userId)
        .limit(1);
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;

    final row = Map<String, dynamic>.from(list.first as Map<String, dynamic>);
    final economy  = row.remove('player_economy')  as Map<String, dynamic>?;
    final progress = row.remove('player_progress') as Map<String, dynamic>?;
    final streaks  = row.remove('player_streaks')  as Map<String, dynamic>?;
    final trial    = row.remove('player_trial')    as Map<String, dynamic>?;

    if (economy  != null) row.addAll(economy);
    if (progress != null) row.addAll(progress);
    if (streaks  != null) row.addAll(streaks);
    if (trial    != null) row.addAll(trial);

    return row;
  }

  Future<void> insertProfile(
    String id,
    String username,
    String color, {
    double influence = 1,
    String? invitedAt,
    int isTester = 0,
    String? createdAt,
  }) async {
    final client = Supabase.instance.client;
    await client.from('players').insert({
      'user_id': id,
      'username': username.trim(),
      'color': color,
      'invited_at': invitedAt,
      'is_tester': isTester,
      'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> upsertProfileIgnore(
    String id,
    String username,
    String color, {
    double influence = 1,
    String? invitedAt,
    int isTester = 0,
  }) async {
    final client = Supabase.instance.client;
    await client.from('players').upsert(
      {
        'user_id': id,
        'username': username.trim(),
        'color': color,
        'invited_at': invitedAt,
        'is_tester': isTester,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final normalised = normaliseProfilePatch(patch);
    final client = Supabase.instance.client;

    final identityPatch  = <String, dynamic>{};
    final economyPatch   = <String, dynamic>{};
    final progressPatch  = <String, dynamic>{};
    final streaksPatch   = <String, dynamic>{};
    final trialPatch     = <String, dynamic>{};

    final unknownKeys = <String>[];
    for (final entry in normalised.entries) {
      if (_kIdentityCols.contains(entry.key)) {
        identityPatch[entry.key] = entry.value;
      } else if (_kEconomyCols.contains(entry.key)) {
        economyPatch[entry.key] = entry.value;
      } else if (_kProgressCols.contains(entry.key)) {
        progressPatch[entry.key] = entry.value;
      } else if (_kStreaksCols.contains(entry.key)) {
        streaksPatch[entry.key] = entry.value;
      } else if (_kTrialCols.contains(entry.key)) {
        trialPatch[entry.key] = entry.value;
      } else {
        unknownKeys.add(entry.key);
      }
    }
    // In debug builds, surface unknown patch keys so they don't silently vanish.
    assert(unknownKeys.isEmpty, 'updateProfile: unknown patch keys dropped: $unknownKeys');

    if (identityPatch.isNotEmpty) {
      await client.from('players').update(identityPatch).eq('user_id', userId);
    }
    if (economyPatch.isNotEmpty) {
      await client.from('player_economy').upsert(
        {'user_id': userId, ...economyPatch},
        onConflict: 'user_id',
      );
    }
    if (progressPatch.isNotEmpty) {
      await client.from('player_progress').upsert(
        {'user_id': userId, ...progressPatch},
        onConflict: 'user_id',
      );
    }
    if (streaksPatch.isNotEmpty) {
      await client.from('player_streaks').upsert(
        {'user_id': userId, ...streaksPatch},
        onConflict: 'user_id',
      );
    }
    if (trialPatch.isNotEmpty) {
      await client.from('player_trial').upsert(
        {'user_id': userId, ...trialPatch},
        onConflict: 'user_id',
      );
    }
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
        .select('user_id, player_trial(*), player_streaks(freeze_tokens, freeze_refreshed_at, streak)')
        .eq('user_id', userId)
        .limit(1);
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;

    final row = Map<String, dynamic>.from(list.first as Map<String, dynamic>);
    final trial   = row['player_trial']   as Map<String, dynamic>?;
    final streaks = row['player_streaks'] as Map<String, dynamic>?;

    return {
      'trial_started_at':     trial?['trial_started_at'],
      'trial_days_remaining': trial?['trial_days_remaining'],
      'trial_last_tick_date': trial?['trial_last_tick_date'],
      'freeze_tokens':        streaks?['freeze_tokens'],
      'freeze_refreshed_at':  streaks?['freeze_refreshed_at'],
      'streak':               streaks?['streak'],
    };
  }

  Future<void> updateTrialState(
    String userId, {
    String? trialStartedAt,
    int? trialDaysRemaining,
    String? trialLastTickDate,
    int? freezeTokens,
    String? freezeRefreshedAt,
    int? streak,
    String? streakStartedAt,
    int? longestStreak,
  }) async {
    final patch = <String, dynamic>{};
    if (trialStartedAt != null) patch['trial_started_at'] = trialStartedAt;
    if (trialDaysRemaining != null) patch['trial_days_remaining'] = trialDaysRemaining;
    if (trialLastTickDate != null) patch['trial_last_tick_date'] = trialLastTickDate;
    if (freezeTokens != null) patch['freeze_tokens'] = freezeTokens;
    if (freezeRefreshedAt != null) patch['freeze_refreshed_at'] = freezeRefreshedAt;
    if (streak != null) patch['streak'] = streak;
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
        .select('*, daily_mission_definitions(slug)')
        .eq('user_id', userId)
        .eq('date', date);
    return (rows as List<dynamic>).map((r) {
      final m = Map<String, dynamic>.from(r as Map<String, dynamic>);
      m['slug'] = (m['daily_mission_definitions'] as Map?)?['slug'];
      m.remove('daily_mission_definitions');
      return m;
    }).toList();
  }

  /// Upserts a daily_mission_progress row. Resolves `mission_id` from
  /// `daily_mission_definitions` via the `slug` key before writing, since
  /// the live UNIQUE constraint is (user_id, mission_id, date).
  ///
  /// Required row map keys:
  ///   - 'user_id' (String UUID)
  ///   - 'slug' (String, used for definition lookup; stripped before write)
  ///   - 'date' (String, yyyy-MM-dd)
  /// Optional keys: 'progress', 'target', 'completed_at', 'synced_at'.
  ///
  /// Throws StateError if the slug does not match any definition row.
  Future<void> upsertMissionProgress(Map<String, dynamic> row) async {
    final client = Supabase.instance.client;
    final slug = row['slug'] as String?;
    if (slug == null) {
      throw StateError('upsertMissionProgress requires a slug in the row map');
    }

    // Resolve mission_id from definitions table.
    final defRow = await client
        .from('daily_mission_definitions')
        .select('id')
        .eq('slug', slug)
        .maybeSingle();
    if (defRow == null) {
      throw StateError('Unknown mission slug: $slug');
    }
    final missionId = defRow['id'] as int;

    // Build payload: strip slug; inject mission_id.
    final payload = Map<String, dynamic>.from(row)
      ..remove('slug')
      ..remove('id'); // drop legacy composite id; live table generates UUID
    payload['mission_id'] = missionId;

    await client.from('daily_mission_progress').upsert(
      payload,
      onConflict: 'user_id,mission_id,date',
    );
  }

}
