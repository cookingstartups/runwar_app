// lib/providers/first_thirty_days_missions_provider.dart
//
// Riverpod providers for the first-30-days curriculum (rw_app-T0593).
// A future dot-stepper widget (pending operator mockup-variant choice)
// consumes `firstThirtyDaysMissionsProvider` — no UI is wired here.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/day30_mission.dart';
import '../services/first_thirty_days_missions_service.dart';

/// Exposes [FirstThirtyDaysMissionsService.instance] as a Riverpod provider.
/// Tests can override this provider with a mock.
final firstThirtyDaysMissionsServiceProvider =
    Provider<FirstThirtyDaysMissionsService>(
  (ref) => FirstThirtyDaysMissionsService.instance,
);

/// Watches the 12-entry curriculum state (unlocked/completed) for [userId].
final firstThirtyDaysMissionsProvider =
    FutureProvider.family<List<Day30MissionState>, String>(
  (ref, userId) =>
      ref.watch(firstThirtyDaysMissionsServiceProvider).getState(userId),
);

/// Invalidates curriculum state after a completion event (daily mission,
/// milestone, or teaching acknowledgment) so a future stepper widget
/// re-renders with fresh state.
void invalidateFirstThirtyDaysMissions(Ref ref, String userId) {
  ref.invalidate(firstThirtyDaysMissionsProvider(userId));
}

/// Variant of [invalidateFirstThirtyDaysMissions] for use in widget/
/// ConsumerState contexts.
void widgetRefInvalidateFirstThirtyDaysMissions(WidgetRef ref, String userId) {
  ref.invalidate(firstThirtyDaysMissionsProvider(userId));
}
