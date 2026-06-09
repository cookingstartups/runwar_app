import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'outbox_service.dart';
import 'local_db.dart';
import 'error_log_service.dart';
import 'supabase_service.dart';

/// Drains the sqflite outbox queue to Supabase.
/// Call [drain] on app foreground and connectivity-restored events.
class OutboxDrainer {
  OutboxDrainer._();
  static final OutboxDrainer instance = OutboxDrainer._();

  bool _draining = false;
  DateTime? _lastDrainAt;

  /// Drains up to 50 pending outbox rows against Supabase.
  /// Debounced to 2 s to avoid thrash when foreground + connectivity events
  /// fire within the same second.
  Future<void> drain() async {
    // Debounce: skip if a drain ran within the last 2 seconds.
    final now = DateTime.now();
    if (_lastDrainAt != null &&
        now.difference(_lastDrainAt!) < const Duration(seconds: 2)) {
      return;
    }
    if (_draining) return;
    _draining = true;
    _lastDrainAt = now;
    try {
      final db = await LocalDb.instance.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // Batch cap of 50 rows per drain cycle (LIMIT 50) to stay within
      // PostgREST 1 MB request size limit.
      final rows = await db.rawQuery(
        'SELECT * FROM outbox_queue WHERE next_retry_at <= ? '
        'ORDER BY created_at ASC LIMIT 50',
        [nowMs],
      );
      for (final row in rows) {
        await _processRow(Map<String, dynamic>.from(row));
      }
    } catch (e, st) {
      debugPrint('[OutboxDrainer] drain failed: $e\n$st');
    } finally {
      _draining = false;
    }
  }

  Future<void> _processRow(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final tableName = row['table_name'] as String;
    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final attemptCount = row['attempt_count'] as int;

    // Known local-only tables — discard silently without network call.
    if (tableName == 'run_scratch') {
      await OutboxService.instance.markSuccess(id);
      return;
    }

    try {
      // Use upsert with onConflict: 'id' for idempotent replay on retry.
      // gps_samples has no PK so upsert falls back to insert for that table.
      if (tableName == 'gps_samples') {
        final samplesRaw = payload['samples'];
        final List<Map<String, dynamic>> samples;
        if (samplesRaw is List) {
          samples = samplesRaw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else {
          samples = [payload];
        }
        await SupabaseService.instance.supabase
            .from('gps_samples')
            .insert(samples);
      } else {
        await SupabaseService.instance.supabase
            .from(tableName)
            .upsert(payload, onConflict: 'id');
      }
      await OutboxService.instance.markSuccess(id);
    } on PostgrestException catch (e) {
      // RLS denial: HTTP 401 / 403 / code 42501 — discard immediately.
      if (e.code == '42501' ||
          e.code == '401' ||
          e.code == '403' ||
          (e.message.contains('row-level security') == true)) {
        ErrorLogService.logClientError(
          provider: 'outbox_drainer',
          error: 'RLS discard: $tableName/$id — ${e.message}',
          stackTrace: StackTrace.empty,
          retryCount: attemptCount,
        );
        await OutboxService.instance.markSuccess(id);
      } else {
        // Retryable — increment attempt_count and update next_retry_at.
        await OutboxService.instance.markFailure(
          id,
          attemptCount,
          error: e.message,
        );
      }
    } catch (e) {
      await OutboxService.instance.markFailure(id, attemptCount,
          error: e.toString());
    }
  }
}
