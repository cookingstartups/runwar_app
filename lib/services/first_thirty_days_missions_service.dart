// lib/services/first_thirty_days_missions_service.dart
//
// Model/service for the first-30-days curriculum (rw_app-T0593).
// Ships the bespoke catalogue, the daily-cadence fill logic (proposal §7,
// operator directive 2026-07-24), unlock-by-day logic, and completion-hook
// wiring — NOT the dot-stepper widget (pending an operator mockup-variant
// choice at a separate step).
//
// Full proposal: ~/AIOS/infra/meta/specs/runwar/first-30-days-missions/proposal.md

import 'package:shared_preferences/shared_preferences.dart';

import '../models/day30_mission.dart';
import '../models/daily_mission.dart';
import '../utils/runwar_constants.dart';
import 'daily_missions_service.dart';
import 'database_service.dart';

class FirstThirtyDaysMissionsService {
  FirstThirtyDaysMissionsService._();
  static final FirstThirtyDaysMissionsService instance =
      FirstThirtyDaysMissionsService._();

  /// The daily-cadence core window (proposal §7): every day in
  /// `[0, dailyCadenceThroughDay]` must resolve to exactly one curriculum
  /// slot, bespoke or resolved. Sourced from [kFirstThirtyDaysCapstoneDay]
  /// (paywall-day21-revision R8) rather than an independent literal, so
  /// this window and the hard-paywall gate's threshold can never drift
  /// apart again. The capstone is now `curriculum`'s day-21 entry, included
  /// via [dailySeries]'s ordinary bespoke-day lookup — see [fullSeries] for
  /// why no loop logic needed to change when the capstone moved inside this
  /// window.
  static const int dailyCadenceThroughDay = kFirstThirtyDaysCapstoneDay;

  // ── Bespoke curriculum catalogue (proposal §2, ordered, 12 entries) ────────
  //
  // These are the "special" curriculum beats: fixed title/teaching-hook,
  // reused as-is by the daily-cadence series below. This list is NOT the
  // full player-facing series any more — see [dailySeries].

  static const List<Day30Mission> curriculum = [
    Day30Mission(
      slot: 1,
      day: 0,
      title: 'Claim Your First Territory',
      teaches: 'Territory claiming (loop-and-close)',
      hook: Day30CompletionHook.firstMissionOnboarding,
      bespoke: true,
      profileCompletionField: 'first_mission_completed_at',
    ),
    Day30Mission(
      slot: 2,
      day: 0,
      title: 'Strike Back',
      teaches: 'Attacking a rival zone',
      hook: Day30CompletionHook.firstMissionOnboarding,
      bespoke: true,
      profileCompletionField: 'first_attack_completed_at',
    ),
    Day30Mission(
      slot: 3,
      day: 1,
      title: 'Hold the Line',
      teaches: 'Zone influence levels (why level 1 is fragile, how '
          're-running raises it)',
      hook: Day30CompletionHook.teachingAcknowledgment,
      bespoke: true,
    ),
    Day30Mission(
      slot: 4,
      day: 2,
      title: 'Grow Your Turf',
      teaches: 'Zone fusion/merge (adjacent captures auto-merge)',
      hook: Day30CompletionHook.teachingAcknowledgment,
      bespoke: true,
    ),
    Day30Mission(
      slot: 5,
      day: 3,
      title: 'Know the Rules',
      teaches: 'Anti-cheat / fair-play (GPS speed thresholds, run don\'t '
          'drive)',
      hook: Day30CompletionHook.teachingAcknowledgment,
      bespoke: true,
    ),
    Day30Mission(
      slot: 6,
      day: 4,
      title: 'Streak Starter',
      teaches: 'Daily missions + streak mechanic',
      hook: Day30CompletionHook.dailyMissionSlug,
      bespoke: true,
      dailyMissionSlug: 'streak_check_in',
    ),
    Day30Mission(
      slot: 7,
      day: 5,
      title: 'Bring a Rival',
      teaches: 'Referral / invite-a-friend',
      hook: Day30CompletionHook.dailyMissionSlug,
      bespoke: true,
      dailyMissionSlug: 'invite_friend',
    ),
    Day30Mission(
      slot: 8,
      day: 7,
      title: 'Milestone: One Week Strong',
      teaches: 'Milestone/streak payoff',
      hook: Day30CompletionHook.milestone,
      bespoke: true,
      milestoneDay: 7,
    ),
    Day30Mission(
      slot: 9,
      day: 10,
      title: "Defend What's Yours",
      teaches: 'Defense / dispute mechanic (surviving an attack)',
      hook: Day30CompletionHook.dailyMissionSlug,
      bespoke: true,
      dailyMissionSlug: 'defend_zone',
    ),
    Day30Mission(
      slot: 10,
      day: 14,
      title: 'Power Up',
      teaches: 'Superpowers (use one)',
      hook: Day30CompletionHook.dailyMissionSlug,
      bespoke: true,
      dailyMissionSlug: 'use_superpower',
    ),
    Day30Mission(
      slot: 11,
      day: 17,
      title: 'Map the City',
      teaches: 'Fog-of-war exploration',
      hook: Day30CompletionHook.dailyMissionSlug,
      bespoke: true,
      dailyMissionSlug: 'enter_new_zone',
    ),
    Day30Mission(
      slot: 12,
      day: kFirstThirtyDaysCapstoneDay,
      title: 'Milestone: Founding Runner',
      teaches: 'Capstone — retrospective on everything learned',
      hook: Day30CompletionHook.teachingAcknowledgment,
      bespoke: true,
    ),
    Day30Mission(
      slot: 13,
      day: 8,
      title: 'Bring Another Rival',
      teaches: 'Referral / invite-a-friend, again',
      hook: Day30CompletionHook.dailyMissionSlug,
      bespoke: true,
      dailyMissionSlug: 'invite_friend',
      slugCompletionSinceUnlockDay: true,
    ),
    Day30Mission(
      slot: 14,
      day: 19,
      title: 'Rivals Are Circling',
      teaches: 'Defending against an active PvE bot attack',
      hook: Day30CompletionHook.pveZoneDefense,
      bespoke: true,
    ),
    Day30Mission(
      slot: 15,
      day: 20,
      title: 'Unite Your Empire',
      teaches: 'Fusion/merge showcase — bringing zones together',
      hook: Day30CompletionHook.teachingAcknowledgment,
      bespoke: true,
    ),
  ];

  // ── Daily-cadence series (proposal §7, generated) ───────────────────────────

  /// Builds the full ordered series for days `[0, throughDay]`: one bespoke
  /// entry per bespoke day (two on Day 0, matching the shipped 2-step
  /// onboarding), and a generated cadence-fill entry (hook
  /// [Day30CompletionHook.resolvedDaily]) for every other day in the window,
  /// so no day in `[0, throughDay]` is left without a curriculum slot.
  ///
  /// Slots for generated entries continue numbering after the highest
  /// bespoke slot, in day order.
  static List<Day30Mission> dailySeries({int throughDay = dailyCadenceThroughDay}) {
    final bespokeByDay = <int, List<Day30Mission>>{};
    for (final mission in curriculum) {
      if (mission.day > throughDay) continue; // e.g. Day 30 capstone
      bespokeByDay.putIfAbsent(mission.day, () => []).add(mission);
    }

    var nextFillerSlot =
        curriculum.map((m) => m.slot).reduce((a, b) => a > b ? a : b) + 1;

    final series = <Day30Mission>[];
    for (var day = 0; day <= throughDay; day++) {
      final bespokeForDay = bespokeByDay[day];
      if (bespokeForDay != null && bespokeForDay.isNotEmpty) {
        series.addAll(bespokeForDay);
      } else {
        series.add(Day30Mission(
          slot: nextFillerSlot++,
          day: day,
          bespoke: false,
          title: "Today's Challenge",
          teaches: "Complete one of today's missions",
          hook: Day30CompletionHook.resolvedDaily,
        ));
      }
    }
    return series;
  }

  /// The full player-facing series: the daily-cadence window
  /// (`[0, dailyCadenceThroughDay]`, one slot per day). The capstone is now
  /// day 21 (== `dailyCadenceThroughDay`), so it is emitted by [dailySeries]
  /// itself via the ordinary bespoke-day lookup; the append clause below
  /// contributes nothing for it (`21 > 21` is false) — see design.md §6 for
  /// why this needed no loop-logic change, only the data/constant change.
  static List<Day30Mission> fullSeries() => [
        ...dailySeries(),
        ...curriculum.where((m) => m.day > dailyCadenceThroughDay),
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

  /// Computes unlocked/current/completed state for the full daily-cadence
  /// series ([fullSeries]) for [userId]. Exposed to widgets via
  /// `firstThirtyDaysMissionsProvider`.
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
    final currentStreak = (profile?['streak'] as num?)?.toInt() ?? 0;

    final rawMilestones = profile?['milestones_claimed'];
    final milestonesClaimed = rawMilestones is List
        ? rawMilestones.whereType<int>().toSet()
        : <int>{};

    final states = <Day30MissionState>[];
    for (final mission in fullSeries()) {
      final unlocked = isUnlocked(mission, dayIndex);
      bool completed = false;
      DateTime? completedAt;
      DailyMission? resolvedMission;

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
          if (mission.slugCompletionSinceUnlockDay) {
            // paywall-day21-revision R2: only a completion recorded on/after
            // this entry's own unlock day satisfies it (e.g. Day-8 "Bring
            // Another Rival" must not auto-complete off a pre-day-8
            // invite_friend completion that already satisfied Day-5). The
            // cutoff is computed from trialStartedAt's UTC calendar
            // midnight, matching dayIndexFor's own truncation, so "unlock
            // day" means the same thing in both places.
            final unlockDate = _utcMidnight(trialStartedAt ?? DateTime.now())
                .add(Duration(days: mission.day));
            completed = await ds.hasCompletedDailyMissionSlugSince(
              userId,
              mission.dailyMissionSlug!,
              unlockDate,
            );
          } else {
            completed = await ds.hasCompletedDailyMissionSlug(
              userId,
              mission.dailyMissionSlug!,
            );
          }
          break;

        case Day30CompletionHook.pveZoneDefense:
          // Reserved stub (paywall-day21-revision, design.md §4.2): the
          // real Day-19 PvE bot-attack completion condition ships in a
          // follow-up SDD track. Always incomplete until then — same
          // "day is unlock, not deadline" convention as every other entry;
          // no auto-complete, no false-positive completion.
          completed = false;
          break;

        case Day30CompletionHook.milestone:
          completed = milestonesClaimed.contains(mission.milestoneDay);
          break;

        case Day30CompletionHook.teachingAcknowledgment:
          completed = await isTeachingMomentAcknowledged(userId, mission.slot);
          break;

        case Day30CompletionHook.resolvedDaily:
          // Deterministic rule (proposal §7): the day's slot is filled by
          // the FIRST mission in that calendar date's deterministically-
          // derived DailyMissionsService slate (`previewSlateForDate`,
          // seeded by sha256(userId|date)) — stable and reproducible even
          // for a day the player never opened as "today".
          final base = trialStartedAt ?? DateTime.now();
          final targetDate = base.add(Duration(days: mission.day));
          final slate = DailyMissionsService.instance.previewSlateForDate(
            userId,
            targetDate,
            streak: currentStreak,
          );
          if (slate.isNotEmpty) {
            resolvedMission = slate.first;
            completed = await ds.hasCompletedDailyMissionSlug(
              userId,
              resolvedMission.slug,
            );
          }
          break;
      }

      states.add(Day30MissionState(
        mission: mission,
        unlocked: unlocked,
        completed: completed,
        completedAt: completedAt,
        resolvedMission: resolvedMission,
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

  /// UTC calendar-midnight truncation, matching [dayIndexFor]'s own
  /// truncation exactly (paywall-day21-revision R2 correctness detail) —
  /// used so "on or after this entry's unlock day" means the same instant
  /// [dayIndexFor] itself considers that day to begin.
  static DateTime _utcMidnight(DateTime d) {
    final utc = d.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}
