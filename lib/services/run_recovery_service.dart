import 'database_service.dart';

/// Metadata about an orphaned (unfinished) run found in run_scratch.
class OrphanedRun {
  final String userId;
  final int pointCount;
  final DateTime earliestTs;
  const OrphanedRun({
    required this.userId,
    required this.pointCount,
    required this.earliestTs,
  });
}

/// Handles app-start recovery of GPS points saved to run_scratch when the
/// process was killed mid-run (AC-11, AC-12).
///
/// All methods swallow errors — recovery is best-effort and must never block
/// the normal auth flow.
class RunRecoveryService {
  RunRecoveryService._();
  static final RunRecoveryService instance = RunRecoveryService._();

  /// Rows older than this are considered stale and purged silently (AC-11).
  static const Duration _staleCutoff = Duration(hours: 12);

  /// Delete all run_scratch rows whose [ts] is older than 12 hours (AC-11).
  ///
  /// Called from [main()] immediately after [DatabaseService.instance.init()],
  /// before [runApp]. Never throws.
  Future<void> sweepStale() async {
    try {
      final cutoff =
          DateTime.now().toUtc().subtract(_staleCutoff).toIso8601String();
      await DatabaseService.instance.db.delete(
        'run_scratch',
        where: 'ts < ?',
        whereArgs: [cutoff],
      );
    } catch (_) {}
  }

  /// Returns an [OrphanedRun] summary if [userId] has run_scratch rows within
  /// the last 12 hours. Returns null if there are no qualifying rows.
  ///
  /// Called from [RecoveryGate] after authentication resolves (AC-12).
  Future<OrphanedRun?> detectOrphan(String userId) async {
    try {
      final db = DatabaseService.instance.db;
      final cutoff =
          DateTime.now().toUtc().subtract(_staleCutoff).toIso8601String();
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c, MIN(ts) AS earliest FROM run_scratch '
        'WHERE user_id = ? AND ts >= ?',
        [userId, cutoff],
      );
      if (rows.isEmpty) return null;
      final count = rows.first['c'] as int? ?? 0;
      if (count == 0) return null;
      final earliest = rows.first['earliest'] as String?;
      return OrphanedRun(
        userId: userId,
        pointCount: count,
        earliestTs: DateTime.parse(
          earliest ?? DateTime.now().toUtc().toIso8601String(),
        ).toUtc(),
      );
    } catch (_) {
      return null; // fail-closed — no orphan reported on error
    }
  }
}
