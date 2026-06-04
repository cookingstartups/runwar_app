// lib/providers/daily_missions_provider.dart
//
// Riverpod providers for the daily-missions-retention feature.
// Full service wiring will be completed by the Backend-Developer agent
// once DailyMissionsService has its real implementation.

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

/// Watches the player's streak data from Supabase.
final dailyStreakProvider = FutureProvider.family<DailyStreak, String>(
  (ref, userId) async {
    final client = ref.read(supabaseClientProvider);
    final row = await client
        .from('players')
        .select('streak, longest_streak, last_login_at, milestones_claimed')
        .eq('id', userId)
        .single();
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
