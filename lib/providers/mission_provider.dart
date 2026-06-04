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

/// Reads mission completion state from local SQLite only — no remote round-trip.
/// Fast enough to be used as a synchronous gate in _RouteGuard.
final missionStatusProvider =
    FutureProvider.family<MissionStatus, String>((ref, userId) async {
  try {
    final db = DatabaseService.instance.db;

    final profileRows = await db.query(
      'profiles',
      columns: ['first_mission_completed_at', 'first_attack_completed_at'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    DateTime? firstMission;
    DateTime? firstAttack;

    if (profileRows.isNotEmpty) {
      final row = profileRows.first;
      final missionAt = row['first_mission_completed_at'] as String?;
      final attackAt = row['first_attack_completed_at'] as String?;
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

    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM zones WHERE owner_id = ?',
      [userId],
    );
    final zoneCount =
        (countRows.isNotEmpty ? countRows.first['cnt'] as int? : null) ?? 0;

    return MissionStatus(
      firstMissionCompletedAt: firstMission,
      firstAttackCompletedAt: firstAttack,
      zoneCount: zoneCount,
    );
  } catch (_) {
    // On DB error, default to bypass so the gate never hard-blocks.
    return const MissionStatus(
      firstMissionCompletedAt: null,
      firstAttackCompletedAt: null,
      zoneCount: 1, // triggers bypass path
    );
  }
});
