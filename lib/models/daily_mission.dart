// lib/models/daily_mission.dart
// Data models for the daily-missions-retention feature.

class DailyMission {
  const DailyMission({
    required this.slug,
    required this.title,
    required this.mechanic,
    required this.rewardCredits,
    this.rewardPower,
    required this.targetValue,
    required this.weight,
    required this.isHard,
    this.progress = 0,
    this.completedAt,
  });

  final String slug;
  final String title;
  final String mechanic;
  final int rewardCredits;
  final String? rewardPower;
  final int targetValue;
  final int weight;
  final bool isHard;
  final int progress;
  final DateTime? completedAt;

  /// Alias for [targetValue] — matches the design spec field name.
  int get target => targetValue;

  bool get isComplete => completedAt != null;
  double get fraction =>
      targetValue == 0 ? 0.0 : (progress / targetValue).clamp(0.0, 1.0);

  DailyMission copyWith({
    int? progress,
    DateTime? completedAt,
  }) {
    return DailyMission(
      slug: slug,
      title: title,
      mechanic: mechanic,
      rewardCredits: rewardCredits,
      rewardPower: rewardPower,
      targetValue: targetValue,
      weight: weight,
      isHard: isHard,
      progress: progress ?? this.progress,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class DailyStreak {
  const DailyStreak({
    required this.current,
    required this.longest,
    this.lastLoginAt,
    this.milestonesClaimed = const [],
    this.subscriptionTier = 'free',
  });

  final int current;
  final int longest;
  final DateTime? lastLoginAt;
  final List<int> milestonesClaimed;
  final String subscriptionTier;

  factory DailyStreak.fromMap(Map<String, dynamic> row) {
    final rawMilestones = row['milestones_claimed'];
    List<int> milestones = [];
    if (rawMilestones is List) {
      milestones = rawMilestones.whereType<int>().toList();
    }
    DateTime? lastLogin;
    final rawLogin = row['last_login_at'];
    if (rawLogin is String) {
      try {
        lastLogin = DateTime.parse(rawLogin);
      } catch (_) {}
    }
    final streakValue = ((row['streak'] ?? row['current_streak']) as num?)?.toInt() ?? 0;
    return DailyStreak(
      current: streakValue,
      longest: (row['longest_streak'] as num?)?.toInt() ?? 0,
      lastLoginAt: lastLogin,
      milestonesClaimed: milestones,
      subscriptionTier: (row['subscription_tier'] as String?) ?? 'free',
    );
  }
}

class MissionCompletionResult {
  const MissionCompletionResult({
    required this.slug,
    required this.creditsGranted,
    this.powerGranted,
    required this.newBalance,
    this.alreadyCompleted = false,
    this.completedAt,
  });

  final String slug;
  final int creditsGranted;
  final String? powerGranted;
  final int newBalance;
  final bool alreadyCompleted;
  final DateTime? completedAt;
}

class RecordDailyLoginResult {
  const RecordDailyLoginResult({
    required this.streak,
    required this.longestStreak,
    required this.previousStreak,
    required this.streakEvent,
    this.milestoneUnlocked,
    this.newBalance,
    this.checkInGranted = false,
  });

  final int streak;
  final int longestStreak;
  final int previousStreak;
  final String streakEvent; // 'incremented' | 'broken' | 'first_login'
  final MilestoneUnlock? milestoneUnlocked;
  final int? newBalance;
  final bool checkInGranted;
}

class MilestoneUnlock {
  const MilestoneUnlock({
    required this.day,
    required this.credits,
    this.power,
    this.powerDurationSeconds,
  });

  final int day;
  final int credits;
  final String? power;
  final int? powerDurationSeconds;
}
