import 'database_service.dart';

class TrialStatus {
  final bool started;
  final int daysRemaining;
  final int streak;
  const TrialStatus({
    required this.started,
    required this.daysRemaining,
    required this.streak,
  });
  bool get isExpired => started && daysRemaining <= 0;
  bool get isDownsellEligible => streak >= 7;
}

/// Manages the 14-day activity-based trial.
///
/// Trial starts on first FAB tap (call [initTrial]).
/// Each app-foreground fires [processDailyTick] — idempotent same-day.
/// Missing days burn 2 credits (penalty) unless freeze tokens absorb the gap.
class TrialService {
  TrialService._();
  static final TrialService instance = TrialService._();

  /// Sets trial_started_at on first run FAB tap. No-op if already set.
  Future<void> initTrial(String userId) async {
    final row = await DatabaseService.instance.getTrialState(userId);
    if (row == null || row['trial_started_at'] != null) return;
    final today = _todayStr();
    await DatabaseService.instance.updateTrialState(
      userId,
      trialStartedAt: DateTime.now().toUtc().toIso8601String(),
      trialLastTickDate: today,
      freezeRefreshedAt: today,
    );
  }

  /// Called on app foreground. Applies streak/freeze mechanics to trial credits.
  /// Same-day calls are no-ops.
  Future<void> processDailyTick(String userId) async {
    final row = await DatabaseService.instance.getTrialState(userId);
    if (row == null) return;
    if (row['trial_started_at'] == null) return;

    final today = _todayStr();
    final lastTick = row['trial_last_tick_date'] as String?;
    if (lastTick == today) return;

    int daysRemaining = (row['trial_days_remaining'] as int?) ?? 14;
    if (daysRemaining <= 0) return;

    int freezeTokens = (row['freeze_tokens'] as int?) ?? 2;
    final refreshedAt = row['freeze_refreshed_at'] as String?;
    final daysSinceRefresh =
        refreshedAt == null ? 999 : _daysBetween(refreshedAt, today);
    if (daysSinceRefresh >= 30) {
      freezeTokens = 2;
    }

    final daysSince = lastTick == null ? 1 : _daysBetween(lastTick, today);
    int newStreak = (row['streak'] as int?) ?? 0;

    if (daysSince <= 0) return;

    if (daysSince == 1) {
      // Active day — normal burn
      daysRemaining -= 1;
      newStreak += 1;
    } else if (daysSince == 2 && freezeTokens > 0) {
      // Missed 1 day, freeze token absorbs it
      freezeTokens -= 1;
      daysRemaining -= 1;
      newStreak += 1;
    } else {
      // Missed days without protection — penalty: -1 for today + -(missedDays)
      final penalty = daysSince - 1;
      daysRemaining = (daysRemaining - 1 - penalty).clamp(0, 14);
      newStreak = 1;
    }

    await DatabaseService.instance.updateTrialState(
      userId,
      trialDaysRemaining: daysRemaining.clamp(0, 14),
      trialLastTickDate: today,
      freezeTokens: freezeTokens,
      freezeRefreshedAt: refreshedAt ?? today,
      streak: newStreak,
    );
  }

  Future<TrialStatus> getStatus(String userId) async {
    final row = await DatabaseService.instance.getTrialState(userId);
    if (row == null) {
      return const TrialStatus(started: false, daysRemaining: 14, streak: 0);
    }
    return TrialStatus(
      started: row['trial_started_at'] != null,
      daysRemaining: (row['trial_days_remaining'] as int?) ?? 14,
      streak: (row['streak'] as int?) ?? 0,
    );
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int _daysBetween(String from, String to) {
    try {
      final a = DateTime.parse(from);
      final b = DateTime.parse(to);
      return b.difference(a).inDays;
    } catch (_) {
      return 1;
    }
  }
}
