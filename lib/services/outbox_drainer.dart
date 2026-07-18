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
      // gps_samples uses the gps_samples_dedup unique index
      // (session_id, ts, user_id) for crash-replay deduplication.
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
            .upsert(samples, onConflict: 'session_id,ts,user_id');
      } else {
        await SupabaseService.instance.supabase
            .from(tableName)
            .upsert(payload, onConflict: 'id');
      }
      await OutboxService.instance.markSuccess(id);
    } on PostgrestException catch (e) {
      // Permanent errors: RLS denial (42501, 401, 403) and FK violations
      // (23503) — discard immediately rather than retrying, since retrying
      // against a missing parent row or a denied policy will never succeed
      // on its own.
      //
      // 23502 (NOT NULL violation) is a permanent discard for every table
      // EXCEPT `runs`. For `runs`, a 23502 means this queued update is a
      // partial payload that happened to hit Postgres as an INSERT (no
      // existing row) instead of an UPDATE, so a required column (e.g.
      // started_at) was missing from this particular payload. Discarding it
      // here would silently and permanently lose the run update. Keep it
      // queued so the existing backoff/retry mechanism in
      // OutboxService.markFailure gets another chance once a fuller payload
      // (e.g. the full stub re-sent by resumeFromScratch) has landed
      // server-side and turned this row's upsert into a true UPDATE.
      final code = e.code ?? '';
      final msg = e.message;
      final isRlsDenial = code == '42501' ||
          code == '401' ||
          code == '403' ||
          msg.contains('row-level security');
      final isForeignKeyViolation = code == '23503';
      final isRetryableNotNullOnRuns = code == '23502' && tableName == 'runs';
      final isPermanentNotNull = code == '23502' && !isRetryableNotNullOnRuns;

      if (isRlsDenial || isForeignKeyViolation || isPermanentNotNull) {
        debugPrint(
          '[OutboxDrainer] permanent error $code on $tableName/$id — discarding',
        );
        ErrorLogService.logClientError(
          provider: 'outbox_drainer',
          error: 'permanent discard ($code): $tableName/$id — $msg',
          stackTrace: StackTrace.empty,
          retryCount: attemptCount,
        );
        await OutboxService.instance.markSuccess(id);
      } else {
        // Retryable (including 23502 on `runs`) — increment attempt_count
        // and update next_retry_at; existing exponential backoff applies.
        if (isRetryableNotNullOnRuns) {
          debugPrint(
            '[OutboxDrainer] NOT NULL violation on runs/$id kept queued for retry: $msg',
          );
        }
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
