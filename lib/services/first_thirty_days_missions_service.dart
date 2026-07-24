// lib/services/first_thirty_days_missions_service.dart
//
// Model/service skeleton for the first-30-days curriculum (rw_app-T0593).
// This pass ships the 12-mission catalogue, unlock-by-day logic, and
// completion-hook wiring only — NOT the dot-stepper widget (pending an
// operator mockup-variant choice at a separate step).
//
// Full proposal: ~/AIOS/infra/meta/specs/runwar/first-30-days-missions/proposal.md

import 'package:shared_preferences/shared_preferences.dart';

import '../models/day30_mission.dart';
import 'database_service.dart';

class FirstThirtyDaysMissionsService {
  FirstThirtyDaysMissionsService._();
  static final FirstThirtyDaysMissionsService instance =
      FirstThirtyDaysMissionsService._();

  // ── Curriculum catalogue (proposal §2, ordered, 12 entries) ─────────────────

  static const List<Day30Mission> curriculum = [
    Day30Mission(
      slot: 1,
      day: 0,
      title: 'Claim Your First Territory',
      teaches: 'Territory claiming (loop-and-close)',
      hook: Day30CompletionHook.firstMissionOnboarding,
      profileCompletionField: 'first_mission_completed_at',
    ),
    Day30Mission(
      slot: 2,
      day: 0,
      title: 'Strike Back',
      teaches: 'Attacking a rival zone',
      hook: Day30CompletionHook.firstMissionOnboarding,
      profileCompletionField: 'first_attack_completed_at',
    ),
    Day30Mission(
      slot: 3,
      day: 1,
      title: 'Hold the Line',
      teaches: 'Zone influence levels (why level 1 is fragile, how '
          're-running raises it)',
      hook: Day30CompletionHook.teachingAcknowledgment,
    ),
    Day30Mission(
      slot: 4,
      day: 2,
      title: 'Grow Your Turf',
      teaches: 'Zone fusion/merge (adjacent captures auto-merge)',
      hook: Day30CompletionHook.teachingAcknowledgment,
    ),
    Day30Mission(
      slot: 5,
      day: 3,
      title: 'Know the Rules',
      teaches: 'Anti-cheat / fair-play (GPS speed thresholds, run don\'t '
          'drive)',
      hook: Day30CompletionHook.teachingAcknowledgment,
    ),
    Day30Mission(
      slot: 6,
      day: 4,
      title: 'Streak Starter',
      teaches: 'Daily missions + streak mechanic',
      hook: Day30CompletionHook.dailyMissionSlug,
      dailyMissionSlug: 'streak_check_in',
    ),
    Day30Mission(
      slot: 7,
      day: 5,
      title: 'Bring a Rival',
      teaches: 'Referral / invite-a-friend',
      hook: Day30CompletionHook.dailyMissionSlug,
      dailyMissionSlug: 'invite_friend',
    ),
    Day30Mission(
      slot: 8,
      day: 7,
      title: 'Milestone: One Week Strong',
      teaches: 'Milestone/streak payoff',
      hook: Day30CompletionHook.milestone,
      milestoneDay: 7,
    ),
    Day30Mission(
      slot: 9,
      day: 10,
      title: "Defend What's Yours",
      teaches: 'Defense / dispute mechanic (surviving an attack)',
      hook: Day30CompletionHook.dailyMissionSlug,
      dailyMissionSlug: 'defend_zone',
    ),
    Day30Mission(
      slot: 10,
      day: 14,
      title: 'Power Up',
      teaches: 'Superpowers (use one)',
      hook: Day30CompletionHook.dailyMissionSlug,
      dailyMissionSlug: 'use_superpower',
    ),
    Day30Mission(
      slot: 11,
      day: 21,
      title: 'Map the City',
      teaches: 'Fog-of-war exploration',
      hook: Day30CompletionHook.dailyMissionSlug,
      dailyMissionSlug: 'enter_new_zone',
    ),
    Day30Mission(
      slot: 12,
      day: 30,
      title: 'Milestone: Founding Runner',
      teaches: 'Capstone — retrospective on everything learned',
      hook: Day30CompletionHook.milestone,
      milestoneDay: 30,
    ),
  ];

  // ── Unlock logic (pure, unit-testable without Supabase init) ────────────────

  /// Days elapsed since [trialStartedAt], relative to [now] (defaults to
  /// `DateTime.now()`). Day 0 covers the account's first calendar day.
  ///
  /// Returns 0 when [trialStartedAt] is null (trial not started yet — only
  /// Day-0 curriculum entries are unlocked, matching the pre-onboarding
  /// state), and clamps negative diffs (clock skew) to 0.
  static int dayIndexFor(DateTime? trialStartedAt, {DateTime? now}) {
    if (trialStartedAt == null) return 0;
    final today = (now ?? DateTime.now()).toUtc();
    final started = trialStartedAt.toUtc();
    final diff = DateTime.utc(today.year, today.month, today.day)
        .difference(DateTime.utc(started.year, started.month, started.day))
        .inDays;
    return diff < 0 ? 0 : diff;
  }

  /// A curriculum entry unlocks once the player's account age reaches its
  /// `day` threshold.
  static bool isUnlocked(Day30Mission mission, int dayIndex) =>
      dayIndex >= mission.day;

  // ── Per-player state ─────────────────────────────────────────────────────────

  /// Computes unlocked/completed state for all 12 curriculum entries for
  /// [userId]. Exposed to widgets via `firstThirtyDaysMissionsProvider`.
  Future<List<Day30MissionState>> getState(String userId) async {
    final ds = DatabaseService.instance;

    final trial = await ds.getTrialState(userId);
    final profile = await ds.getProfile(userId);

    DateTime? trialStartedAt;
    final rawStart = trial?['trial_started_at'] as String?;
    if (rawStart != null) {
      try {
        trialStartedAt = DateTime.parse(rawStart);
      } catch (_) {}
    }
    final dayIndex = dayIndexFor(trialStartedAt);

    final rawMilestones = profile?['milestones_claimed'];
    final milestonesClaimed = rawMilestones is List
        ? rawMilestones.whereType<int>().toSet()
        : <int>{};

    final states = <Day30MissionState>[];
    for (final mission in curriculum) {
      final unlocked = isUnlocked(mission, dayIndex);
      bool completed = false;
      DateTime? completedAt;

      switch (mission.hook) {
        case Day30CompletionHook.firstMissionOnboarding:
          final raw = profile?[mission.profileCompletionField!] as String?;
          completed = raw != null;
          if (raw != null) {
            try {
              completedAt = DateTime.parse(raw);
            } catch (_) {}
          }
          break;

        case Day30CompletionHook.dailyMissionSlug:
          completed = await ds.hasCompletedDailyMissionSlug(
            userId,
            mission.dailyMissionSlug!,
          );
          break;

        case Day30CompletionHook.milestone:
          completed = milestonesClaimed.contains(mission.milestoneDay);
          break;

        case Day30CompletionHook.teachingAcknowledgment:
          completed = await isTeachingMomentAcknowledged(userId, mission.slot);
          break;
      }

      states.add(Day30MissionState(
        mission: mission,
        unlocked: unlocked,
        completed: completed,
        completedAt: completedAt,
      ));
    }
    return states;
  }

  // ── Teaching-only slot acknowledgment (local, no mechanic gate) ─────────────

  /// Marks a teaching-only curriculum [slot] (3, 4, or 5) as acknowledged for
  /// [userId] — called by the future info-card UI when the player taps
  /// through it. Persisted locally via shared_preferences, mirroring the
  /// convention used by `showcase_provider.dart`.
  Future<void> acknowledgeTeachingMoment(String userId, int slot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ackKey(userId, slot), true);
  }

  Future<bool> isTeachingMomentAcknowledged(String userId, int slot) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ackKey(userId, slot)) ?? false;
  }

  String _ackKey(String userId, int slot) =>
      'first30_ack_${userId}_slot$slot';
}
