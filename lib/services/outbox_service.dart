import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'local_db.dart';

/// Wraps the sqflite `outbox_queue` table.
/// Pure data access — no network calls.
class OutboxService {
  OutboxService._();
  static final OutboxService instance = OutboxService._();

  /// Enqueues a row for later drain.
  /// [id] is provided by the caller and doubles as the Supabase row id
  /// so upsert replay is idempotent.
  /// Returns [id] so callers can pass it to [markFailure] on inline write error.
  Future<String> enqueue(
    String tableName,
    String id,
    Map<String, dynamic> payload,
  ) async {
    final db = await LocalDb.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'outbox_queue',
      {
        'id': id,
        'table_name': tableName,
        'payload': jsonEncode(payload),
        'created_at': now,
        'attempt_count': 0,
        'next_retry_at': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<List<Map<String, dynamic>>> peekBatch({int limit = 50}) async {
    final db = await LocalDb.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      'SELECT * FROM outbox_queue WHERE next_retry_at <= ? '
      'ORDER BY created_at ASC LIMIT $limit',
      [now],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> markSuccess(String id) async {
    final db = await LocalDb.instance.db;
    await db.delete('outbox_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailure(
    String id,
    int attemptCount, {
    String? error,
  }) async {
    final db = await LocalDb.instance.db;
    final backoffMs = _backoffMs(attemptCount);
    final nextRetry = DateTime.now().millisecondsSinceEpoch + backoffMs;
    await db.update(
      'outbox_queue',
      {
        'attempt_count': attemptCount + 1,
        'next_retry_at': nextRetry,
        if (error != null) 'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() async {
    final db = await LocalDb.instance.db;
    await db.delete('outbox_queue');
  }

  /// Exponential backoff: 5000 * 2^attempt, capped at 300 000 ms (5 min).
  int _backoffMs(int attempt) {
    final base = 5000 * (1 << attempt.clamp(0, 6));
    return base.clamp(5000, 300000);
  }
}
