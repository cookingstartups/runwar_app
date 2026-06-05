// lib/services/daily_missions_service.dart
// Single Dart-side authority for daily-missions slate derivation, local mirror
// persistence, and edge-function invocation.

import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database_service.dart';
import 'telemetry_service.dart';
import '../models/daily_mission.dart';

class DailyMissionsService {
  DailyMissionsService._();
  static final DailyMissionsService instance = DailyMissionsService._();

  // ── Mission catalogue ────────────────────────────────────────────────────────

  static const List<DailyMission> missions = [
    DailyMission(slug: 'streak_check_in',  title: 'Check In',         mechanic: 'open',    rewardCredits: 10,  rewardPower: null, targetValue: 1,    weight: 10, isHard: false),
    DailyMission(slug: 'claim_one_zone',   title: 'Claim Territory',  mechanic: 'claim',   rewardCredits: 30,  rewardPower: null, targetValue: 1,    weight: 9,  isHard: false),
    DailyMission(slug: 'walk_2km',         title: 'Walk 2 km',        mechanic: 'run',     rewardCredits: 40,  rewardPower: null, targetValue: 2000, weight: 8,  isHard: false),
    DailyMission(slug: 'attack_rival',     title: 'Attack a Rival',   mechanic: 'attack',  rewardCredits: 50,  rewardPower: null, targetValue: 1,    weight: 7,  isHard: false),
    DailyMission(slug: 'claim_drop',       title: 'Claim a Drop',     mechanic: 'drop',    rewardCredits: 25,  rewardPower: null, targetValue: 1,    weight: 6,  isHard: false),
    DailyMission(slug: 'use_superpower',   title: 'Use a Superpower', mechanic: 'power',   rewardCredits: 30,  rewardPower: null, targetValue: 1,    weight: 5,  isHard: false),
    DailyMission(slug: 'defend_zone',      title: 'Defend a Zone',    mechanic: 'defend',  rewardCredits: 60,  rewardPower: null, targetValue: 1,    weight: 4,  isHard: false),
    DailyMission(slug: 'share_zone',       title: 'Share a Zone',     mechanic: 'social',  rewardCredits: 20,  rewardPower: null, targetValue: 1,    weight: 3,  isHard: false),
    DailyMission(slug: 'invite_friend',    title: 'Invite a Friend',  mechanic: 'social',  rewardCredits: 200, rewardPower: null, targetValue: 1,    weight: 2,  isHard: false),
    DailyMission(slug: 'enter_new_zone',   title: 'Explore Fog',      mechanic: 'explore', rewardCredits: 35,  rewardPower: null, targetValue: 1,    weight: 5,  isHard: false),
    DailyMission(slug: 'back_to_back',     title: 'Two Runs Today',   mechanic: 'run',     rewardCredits: 80,  rewardPower: null, targetValue: 2,    weight: 3,  isHard: false),
    DailyMission(slug: 'capture_ctf',      title: 'Capture a Flag',   mechanic: 'ctf',     rewardCredits: 100, rewardPower: 'SHIELD_1H', targetValue: 1, weight: 2, isHard: true),
  ];

  static final List<DailyMission> _standardPool =
      missions.where((m) => !m.isHard).toList();
  static final List<DailyMission> _hardPool =
      missions.where((m) => m.isHard).toList();

  // ── Public API ───────────────────────────────────────────────────────────────

  /// FR-1/FR-2: derive once per day, cache in Supabase, return slate.
  Future<List<DailyMission>> getTodaysMissions(String userId) async {
    final ds = DatabaseService.instance;
    final today = _todayString();

    // Cache hit: rows exist for today.
    final cached = await ds.getDailyMissions(userId, today);
    if (cached.isNotEmpty) {
      return cached.map(_rowToMission).toList();
    }

    // Derive slate deterministically from sha256(userId|date).
    final streak = await _getCurrentStreak(userId);
    final slate = _deriveSlate(
      userId: userId,
      localDate: DateTime.now(),
      streak: streak,
    );

    // Upsert slate rows.
    for (final mission in slate) {
      await ds.upsertMissionProgress({
        'id': '${userId}_${today}_${mission.slug}',
        'user_id': userId,
        'date': today,
        'slug': mission.slug,
        'progress': 0,
        'target': mission.targetValue,
        'completed_at': null,
        'synced_at': null,
      });
    }

    // Fire-and-forget: retry any pending completions from offline sessions.
    _retryPendingCompletions(userId).catchError((_) {});

    return slate;
  }

  /// FR-3: called by TerritoryService / RunRecorderService etc.
  /// Increments local progress; if progress >= target, triggers completeMission.
  Future<void> reportProgress(String userId, String slug, int delta) async {
    final ds = DatabaseService.instance;
    final today = _todayString();

    final allRows = await ds.getDailyMissions(userId, today);
    final rows = allRows.where((r) => r['slug'] == slug).toList();
    if (rows.isEmpty) return; // slug not on today's slate

    final row = rows.first;
    final alreadyCompleted = row['completed_at'] != null;
    if (alreadyCompleted) return;

    final current = (row['progress'] as int?) ?? 0;
    final target = (row['target'] as int?) ?? 1;
    final newProgress = math.min(current + delta, target);

    await ds.upsertMissionProgress({
      'id': '${userId}_${today}_$slug',
      'user_id': userId,
      'date': today,
      'slug': slug,
      'progress': newProgress,
      'target': target,
      'completed_at': row['completed_at'],
      'synced_at': row['synced_at'],
    });

    // Fire-and-forget telemetry.
    TelemetryService.instance.logEvent('mission_progressed', props: {
      'slug': slug,
      'progress': newProgress,
      'target': target,
    }).catchError((_) {});

    if (newProgress >= target) {
      // Fire-and-forget with typed catchError to avoid lint warning.
      completeMission(userId, slug).catchError((Object _) => MissionCompletionResult(
        slug: slug,
        creditsGranted: 0,
        newBalance: 0,
      ));
    }
  }

  /// FR-4: posts to complete_daily_mission edge fn, applies result locally.
  Future<MissionCompletionResult> completeMission(
      String userId, String slug) async {
    final supabase = Supabase.instance.client;
    final today = _todayString();

    final session = supabase.auth.currentSession;
    if (session == null) {
      throw StateError('No active Supabase session');
    }

    final response = await supabase.functions.invoke(
      'complete_daily_mission',
      body: {
        'player_id': userId,
        'mission_slug': slug,
        'date': today,
      },
    );

    if (response.status == 409) {
      // Already completed — treat as success.
      final data = (response.data is Map<String, dynamic>)
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};
      return MissionCompletionResult(
        slug: slug,
        creditsGranted: (data['credits_granted'] as num?)?.toInt() ?? 0,
        powerGranted: data['power_granted'] as String?,
        newBalance: (data['new_balance'] as num?)?.toInt() ?? 0,
        alreadyCompleted: true,
      );
    }

    if (response.status != 200) {
      throw StateError(
          'complete_daily_mission failed with status ${response.status}');
    }

    final data = response.data as Map<String, dynamic>;
    final completedAt = data['completed_at'] != null
        ? DateTime.tryParse(data['completed_at'] as String)
        : DateTime.now().toUtc();

    // Update remote mirror.
    final ds = DatabaseService.instance;
    await ds.upsertMissionProgress({
      'id': '${userId}_${today}_$slug',
      'user_id': userId,
      'date': today,
      'slug': slug,
      'completed_at': (completedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    });

    final result = MissionCompletionResult(
      slug: slug,
      creditsGranted: (data['credits_granted'] as num?)?.toInt() ?? 0,
      powerGranted: data['power_granted'] as String?,
      newBalance: (data['new_balance'] as num?)?.toInt() ?? 0,
      alreadyCompleted: false,
      completedAt: completedAt,
    );

    // Fire-and-forget telemetry.
    TelemetryService.instance.logEvent('mission_completed', props: {
      'slug': slug,
      'credits_granted': result.creditsGranted,
      'power_granted': result.powerGranted,
    }).catchError((_) {});

    return result;
  }

  /// Called from main_shell on resume after gating check.
  Future<RecordDailyLoginResult> recordDailyLogin(String userId) async {
    final supabase = Supabase.instance.client;
    final today = _todayString();
    final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;

    final response = await supabase.functions.invoke(
      'record_daily_login',
      body: {
        'player_id': userId,
        'local_date': today,
        'tz_offset_minutes': tzOffsetMinutes,
      },
    );

    if (response.status != 200) {
      throw StateError(
          'record_daily_login failed with status ${response.status}');
    }

    final data = response.data as Map<String, dynamic>;
    final streakEvent = data['streak_event'] as String? ?? 'first_login';
    final newStreak = (data['streak'] as num?)?.toInt() ?? 1;
    final previousStreak = (data['previous_streak'] as num?)?.toInt() ?? 0;

    MilestoneUnlock? milestoneUnlocked;
    final rawMilestone = data['milestone_unlocked'];
    if (rawMilestone is Map<String, dynamic>) {
      milestoneUnlocked = MilestoneUnlock(
        day: (rawMilestone['day'] as num).toInt(),
        credits: (rawMilestone['credits'] as num).toInt(),
        power: rawMilestone['power'] as String?,
        powerDurationSeconds:
            (rawMilestone['power_duration_s'] as num?)?.toInt(),
      );
    }

    // Fire-and-forget telemetry based on streak event.
    if (streakEvent == 'incremented') {
      TelemetryService.instance.logEvent('streak_increment',
          props: {'new_streak': newStreak}).catchError((_) {});
    } else if (streakEvent == 'broken') {
      TelemetryService.instance.logEvent('streak_break',
          props: {'broken_at_streak': previousStreak}).catchError((_) {});
    }

    return RecordDailyLoginResult(
      streak: newStreak,
      longestStreak: (data['longest_streak'] as num?)?.toInt() ?? newStreak,
      previousStreak: previousStreak,
      streakEvent: streakEvent,
      milestoneUnlocked: milestoneUnlocked,
      newBalance: (data['new_balance'] as num?)?.toInt(),
      checkInGranted: data['check_in_granted'] as bool? ?? false,
    );
  }

  /// Helper for streak_check_in & defend / share missions where the trigger
  /// is the action itself, not progress accumulation.
  Future<void> autoComplete(String userId, String slug) async {
    // Use a large delta to ensure progress reaches target in one call.
    await reportProgress(userId, slug, 9999);
  }

  /// Returns true if the daily login modal has not yet been shown today.
  /// Gated by shared_preferences key 'daily_login_modal_shown_date'.
  bool shouldShowDailyLoginModal(String lastShownDate) {
    return lastShownDate != _todayString();
  }

  // ── Slate derivation ─────────────────────────────────────────────────────────

  List<DailyMission> _deriveSlate({
    required String userId,
    required DateTime localDate,
    required int streak,
  }) {
    final dateStr = DateFormat('yyyy-MM-dd').format(localDate);
    final seed = sha256.convert(utf8.encode('$userId|$dateStr')).bytes;
    final rng = _SeededRandom(seed);

    final standardSize = streak < 3 ? 2 : 3;
    final standard = _weightedShuffleTake(_standardPool, standardSize, rng);

    if (streak >= 14) {
      final hard = _weightedShuffleTake(_hardPool, 1, rng);
      return [...standard, ...hard];
    }
    return standard;
  }

  // Efraimidis-Spirakis weighted shuffle: key = u^(1/weight).
  List<DailyMission> _weightedShuffleTake(
      List<DailyMission> pool, int take, _SeededRandom rng) {
    if (pool.isEmpty || take <= 0) return [];
    final actual = math.min(take, pool.length);

    final keyed = pool.map((m) {
      final u = rng.nextDouble().clamp(1e-15, 1.0);
      final key = math.exp(math.log(u) / m.weight);
      return _Keyed(m, key);
    }).toList();

    keyed.sort((a, b) => b.key.compareTo(a.key)); // descending
    return keyed.take(actual).map((k) => k.mission).toList();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _todayString() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<int> _getCurrentStreak(String userId) async {
    try {
      final profile = await DatabaseService.instance.getProfile(userId);
      if (profile == null) return 0;
      return (profile['current_streak'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  DailyMission _rowToMission(Map<String, dynamic> row) {
    final slug = row['slug'] as String;
    final definition = missions.firstWhere(
      (m) => m.slug == slug,
      orElse: () => DailyMission(
        slug: slug,
        title: slug,
        mechanic: 'unknown',
        rewardCredits: 0,
        targetValue: 1,
        weight: 1,
        isHard: false,
      ),
    );
    final progress = (row['progress'] as int?) ?? 0;
    DateTime? completedAt;
    final rawCompleted = row['completed_at'] as String?;
    if (rawCompleted != null) {
      try {
        completedAt = DateTime.parse(rawCompleted);
      } catch (_) {}
    }
    return definition.copyWith(
      progress: progress,
      completedAt: completedAt,
    );
  }

  /// R-2: retry missions completed offline (completed_at set, synced_at null).
  Future<void> _retryPendingCompletions(String userId) async {
    try {
      final today = _todayString();
      final rows = await DatabaseService.instance.getDailyMissions(userId, today);
      final pending = rows.where(
        (r) => r['completed_at'] != null && r['synced_at'] == null,
      ).toList();
      for (final row in pending) {
        final slug = row['slug'] as String;
        try {
          await completeMission(userId, slug);
        } catch (_) {
          // Swallow — will retry on next foreground.
        }
      }
    } catch (_) {}
  }
}

// ── Internal helpers ──────────────────────────────────────────────────────────

class _Keyed {
  const _Keyed(this.mission, this.key);
  final DailyMission mission;
  final double key;
}

/// Deterministic PRNG seeded from sha256 bytes.
/// Uses a simple LCG over the seed bytes for reproducibility.
class _SeededRandom {
  _SeededRandom(List<int> seedBytes) {
    int state = 0;
    for (int i = 0; i < seedBytes.length; i++) {
      state = (state * 31 + seedBytes[i]) & 0x7FFFFFFFFFFFFFFF;
    }
    _state = state == 0 ? 1 : state;
  }

  int _state = 1;

  static const int _multiplier = 6364136223846793005;
  static const int _increment = 1442695040888963407;
  static const int _mask = 0x7FFFFFFFFFFFFFFF;

  int _next() {
    _state = ((_state * _multiplier) + _increment) & _mask;
    return _state;
  }

  /// Returns a uniform double in [0, 1).
  double nextDouble() {
    final bits = _next();
    return (bits & 0x1FFFFFFFFFFFFF) / (0x1FFFFFFFFFFFFF + 1.0);
  }
}
