// lib/providers/daily_missions_provider.dart
//
// Riverpod providers for the daily-missions-retention feature.
// Full service wiring will be completed by the Backend-Developer agent
// once DailyMissionsService has its real implementation.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_mission.dart';
import '../services/daily_missions_service.dart';
import 'repositories.dart';

/// Exposes [DailyMissionsService.instance] as a Riverpod provider.
/// Tests can override this provider with a mock.
final dailyMissionsServiceProvider = Provider<DailyMissionsService>(
  (ref) => DailyMissionsService.instance,
);

/// Watches today's mission slate for [userId].
final todaysMissionsProvider =
    FutureProvider.family<List<DailyMission>, String>(
  (ref, userId) =>
      ref.watch(dailyMissionsServiceProvider).getTodaysMissions(userId),
);

@visibleForTesting
const String kDailyStreakSelectString =
    'id, '
    'player_streaks(streak, longest_streak, last_login_at, milestones_claimed), '
    'player_economy(subscription_tier)';

/// Watches the player's streak data from Supabase.
/// Reads from player_streaks and player_economy via nested join, since
/// migration 0044 dropped these columns from `players`.
final dailyStreakProvider = FutureProvider.family<DailyStreak, String>(
  (ref, userId) async {
    final client = ref.read(supabaseClientProvider);
    final row = await client
        .from('players')
        .select(kDailyStreakSelectString)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      debugPrint('[dailyStreakProvider] no row for userId=$userId - check RLS on player_streaks/player_economy');
      return const DailyStreak(current: 0, longest: 0);
    }
    return DailyStreak.fromMap(row);
  },
);

/// Convenience helper to invalidate all daily state after a login or completion.
/// Used from within Riverpod [Ref] contexts (providers, services).
/// From [WidgetRef] contexts (widgets), call the [widgetRefInvalidateDailyState]
/// variant instead.
void invalidateDailyState(Ref ref, String userId) {
  ref.invalidate(todaysMissionsProvider(userId));
  ref.invalidate(dailyStreakProvider(userId));
}

/// Variant of [invalidateDailyState] for use in widget/ConsumerState contexts.
void widgetRefInvalidateDailyState(WidgetRef ref, String userId) {
  ref.invalidate(todaysMissionsProvider(userId));
  ref.invalidate(dailyStreakProvider(userId));
}
