// lib/models/day30_mission.dart
// Data model for the first-30-days curriculum (rw_app-T0593).
//
// This is a linear, one-time, ordered onboarding curriculum, distinct from:
//   - MissionStep (lib/models/mission_step.dart): the 2-step Day-0 forced
//     onboarding gate (claim + attack).
//   - DailyMission (lib/models/daily_mission.dart): the repeatable daily
//     ladder regenerated every calendar day.
//
// Missions 1-2 of this curriculum reuse the already-shipped
// first-mission-onboarding flow outright; several later slots reuse existing
// daily-mission catalogue slugs as their completion hook; slots 3-5 are new
// teaching-only moments with no mechanic gate of their own. See
// ~/AIOS/infra/meta/specs/runwar/first-30-days-missions/proposal.md for the
// full rationale.

/// How a [Day30Mission]'s completion is determined.
enum Day30CompletionHook {
  /// Reuses the existing 2-step first-mission-onboarding completion flags
  /// (`first_mission_completed_at` / `first_attack_completed_at` on the
  /// player profile). See [Day30Mission.profileCompletionField].
  firstMissionOnboarding,

  /// Reuses an existing `DailyMissionsService` catalogue slug as the
  /// completion signal (any historical completion, not just today's slate).
  /// See [Day30Mission.dailyMissionSlug].
  dailyMissionSlug,

  /// Reuses the existing Day-7/Day-30 streak `MilestoneRewardModal` system.
  /// See [Day30Mission.milestoneDay].
  milestone,

  /// New teaching-only moment with no mechanic gate — the player taps
  /// through an info card and the completion is an explicit local
  /// acknowledgment, not a reward hook.
  teachingAcknowledgment,
}

/// A single entry in the ordered 12-mission first-30-days curriculum.
class Day30Mission {
  const Day30Mission({
    required this.slot,
    required this.day,
    required this.title,
    required this.teaches,
    required this.hook,
    this.profileCompletionField,
    this.dailyMissionSlug,
    this.milestoneDay,
  }) : assert(
          (hook != Day30CompletionHook.firstMissionOnboarding) ||
              profileCompletionField != null,
          'firstMissionOnboarding hook requires profileCompletionField',
        ),
        assert(
          (hook != Day30CompletionHook.dailyMissionSlug) ||
              dailyMissionSlug != null,
          'dailyMissionSlug hook requires dailyMissionSlug',
        ),
        assert(
          (hook != Day30CompletionHook.milestone) || milestoneDay != null,
          'milestone hook requires milestoneDay',
        );

  /// 1-based stepper-dot position, stable ordering for the curriculum.
  final int slot;

  /// Day (relative to the player's trial/account start, Day 0 = first day)
  /// at which this mission becomes unlocked. Not a deadline.
  final int day;

  /// Functional placeholder copy — narrative polish is rw_app-T0594's job.
  final String title;

  /// Short description of the mechanic/concept this mission teaches.
  final String teaches;

  /// How completion of this curriculum entry is determined.
  final Day30CompletionHook hook;

  /// Set when [hook] == [Day30CompletionHook.firstMissionOnboarding]:
  /// the player-profile column name whose non-null timestamp marks this
  /// entry complete (`first_mission_completed_at` or
  /// `first_attack_completed_at`).
  final String? profileCompletionField;

  /// Set when [hook] == [Day30CompletionHook.dailyMissionSlug]: the existing
  /// `DailyMissionsService.missions` catalogue slug reused as the completion
  /// signal for this curriculum entry.
  final String? dailyMissionSlug;

  /// Set when [hook] == [Day30CompletionHook.milestone]: the streak day (7
  /// or 30) whose `MilestoneRewardModal` unlock satisfies this entry.
  final int? milestoneDay;
}

/// Per-player computed state for one [Day30Mission] — unlocked/current/
/// completed. Consumed by a future stepper widget via
/// `firstThirtyDaysMissionsProvider`.
class Day30MissionState {
  const Day30MissionState({
    required this.mission,
    required this.unlocked,
    required this.completed,
    this.completedAt,
  });

  final Day30Mission mission;
  final bool unlocked;
  final bool completed;
  final DateTime? completedAt;

  /// The single mission the stepper should highlight as "active": unlocked
  /// but not yet completed.
  bool get isCurrent => unlocked && !completed;
}
