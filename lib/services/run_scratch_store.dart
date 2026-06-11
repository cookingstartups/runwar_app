import 'local_db.dart';

/// Local-only sqflite store for in-progress GPS scratch points.
/// Survives process kills; never synced to Supabase (no outbox entry).
class RunScratchStore {
  RunScratchStore._();
  static final RunScratchStore instance = RunScratchStore._();

  Future<void> insertPoint(
    String userId,
    double lat,
    double lng, {
    double? accuracy,
    required String ts,
    String? sessionId,
  }) async {
    final db = await LocalDb.instance.db;
    await db.insert('run_scratch', {
      'user_id': userId,
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'ts': ts,
      if (sessionId != null) 'session_id': sessionId,
    });
  }

  Future<List<Map<String, dynamic>>> getPoints(String userId) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query(
      'run_scratch',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'ts ASC',
    );
    return rows
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  Future<void> deleteForUser(String userId) async {
    final db = await LocalDb.instance.db;
    await db.delete('run_scratch', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> deleteBefore(String userId, String cutoffIso) async {
    final db = await LocalDb.instance.db;
    await db.delete(
      'run_scratch',
      where: 'user_id = ? AND ts < ?',
      whereArgs: [userId, cutoffIso],
    );
  }
}
