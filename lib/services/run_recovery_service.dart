import 'run_scratch_store.dart';

/// Metadata about an orphaned (unfinished) run found in run_scratch.
class OrphanedRun {
  final String userId;
  final int pointCount;
  final DateTime earliestTs;
  /// Durable session identity recovered from the run_scratch rows.
  /// Null for legacy rows written before schema v2 (no session_id column).
  final String? sessionId;
  const OrphanedRun({
    required this.userId,
    required this.pointCount,
    required this.earliestTs,
    this.sessionId,
  });
}

/// Handles app-start recovery of GPS points saved in-memory to run_scratch.
///
/// All methods swallow errors — recovery is best-effort and must never block
/// the normal auth flow.
class RunRecoveryService {
  RunRecoveryService._();
  static final RunRecoveryService instance = RunRecoveryService._();

  /// Rows older than this are considered stale and purged silently (AC-11).
  static const Duration _staleCutoff = Duration(hours: 12);

  /// Delete all in-memory scratch points older than 12 hours (AC-11).
  ///
  /// Called from [main()] immediately after [DatabaseService.instance.init()],
  /// before [runApp]. Never throws.
  Future<void> sweepStale() async {
    try {
      // In-memory scratch is lost on process kill — no sweep needed on cold boot.
      // This is a no-op for the Supabase migration; kept for API compatibility.
    } catch (_) {}
  }

  /// Returns an [OrphanedRun] summary if [userId] has run_scratch rows within
  /// the last 12 hours. Returns null if there are no qualifying rows.
  ///
  /// Called from [RecoveryGate] after authentication resolves.
  Future<OrphanedRun?> detectOrphan(String userId) async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(_staleCutoff);
      final rows = await RunScratchStore.instance.getPoints(userId);
      if (rows.isEmpty) return null;

      // Filter to rows within the stale cutoff.
      final recent = rows.where((r) {
        final ts = r['ts'] as String?;
        if (ts == null) return false;
        final dt = DateTime.tryParse(ts);
        if (dt == null) return false;
        return dt.toUtc().isAfter(cutoff);
      }).toList();

      if (recent.isEmpty) return null;

      // Find earliest timestamp and recover the durable session_id.
      DateTime? earliest;
      String? sessionId;
      for (final r in recent) {
        final ts = r['ts'] as String?;
        if (ts == null) continue;
        final dt = DateTime.tryParse(ts)?.toUtc();
        if (dt == null) continue;
        if (earliest == null || dt.isBefore(earliest)) {
          earliest = dt;
        }
        // Use session_id from the first row that has one set.
        sessionId ??= r['session_id'] as String?;
      }

      return OrphanedRun(
        userId: userId,
        pointCount: recent.length,
        earliestTs: earliest ?? DateTime.now().toUtc(),
        sessionId: sessionId,
      );
    } catch (_) {
      return null; // fail-closed — no orphan reported on error
    }
  }
}
