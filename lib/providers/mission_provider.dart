import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';

class MissionStatus {
  const MissionStatus({
    required this.firstMissionCompletedAt,
    required this.firstAttackCompletedAt,
    required this.zoneCount,
  });

  final DateTime? firstMissionCompletedAt;
  final DateTime? firstAttackCompletedAt;
  final int zoneCount;

  bool get needsMission1 => firstMissionCompletedAt == null && zoneCount == 0;

  bool get needsMission2 =>
      firstMissionCompletedAt != null && firstAttackCompletedAt == null;

  /// True when the player bypasses the mission gate:
  /// - attack already completed (full onboarding done), OR
  /// - legacy tester who already owns zones before onboarding existed.
  bool get bypass =>
      firstAttackCompletedAt != null ||
      (firstMissionCompletedAt == null && zoneCount > 0);
}

/// True after the player taps "ACCEPT MISSION" on FirstMissionBriefingScreen.
/// Read by _RouteGuard Gate 5a to switch from briefing to MapScreen.
/// Lives in module scope — survives _RouteGuard rebuilds; resets on cold start.
final mission1BriefingAcceptedProvider = StateProvider<bool>((_) => false);

/// True after the player taps "ENTER THE WAR" on FirstAttackBriefingScreen.
/// Read by _RouteGuard Gate 5b to switch from briefing to MapScreen.
final mission2BriefingAcceptedProvider = StateProvider<bool>((_) => false);

/// Stores the rival zone ID returned by BotSpawnerService.checkOrSpawn
/// after Mission 1 completes. Read by _RouteGuard Gate 5b.
/// Null means spawner has not yet run (or failed). Gate 5b falls back to ''.
final pendingBotZoneIdProvider = StateProvider<String?>((_) => null);

/// Reads mission completion state from Supabase — no local round-trip.
/// Fast enough to be used as a synchronous gate in _RouteGuard.
final missionStatusProvider =
    FutureProvider.family<MissionStatus, String>((ref, userId) async {
  try {
    final ds = DatabaseService.instance;

    final profile = await ds.getProfile(userId);

    DateTime? firstMission;
    DateTime? firstAttack;

    if (profile != null) {
      final missionAt = profile['first_mission_completed_at'] as String?;
      final attackAt = profile['first_attack_completed_at'] as String?;
      if (missionAt != null) {
        try {
          firstMission = DateTime.parse(missionAt);
        } catch (_) {}
      }
      if (attackAt != null) {
        try {
          firstAttack = DateTime.parse(attackAt);
        } catch (_) {}
      }
    }

    final zones = await ds.getZonesByOwner(userId);
    final zoneCount = zones.length;

    return MissionStatus(
      firstMissionCompletedAt: firstMission,
      firstAttackCompletedAt: firstAttack,
      zoneCount: zoneCount,
    );
  } catch (_) {
    // On error, default to bypass so the gate never hard-blocks.
    return const MissionStatus(
      firstMissionCompletedAt: null,
      firstAttackCompletedAt: null,
      zoneCount: 1, // triggers bypass path
    );
  }
});
