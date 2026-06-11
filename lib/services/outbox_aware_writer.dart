import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'outbox_service.dart';
import 'outbox_drainer.dart';
import 'supabase_service.dart';

/// Facade for all Supabase write paths.
/// Every write is enqueued in the outbox BEFORE any network call so data is
/// never lost on network failure. If [canWriteRemote] is true, a drain
/// attempt follows immediately.
class OutboxAwareWriter {
  OutboxAwareWriter._();
  static final OutboxAwareWriter instance = OutboxAwareWriter._();

  static const _uuid = Uuid();

  /// Writes a run row.
  /// [run] must include an 'id' field (UUID v4) — used as the idempotency key.
  Future<void> writeRun(
    Map<String, dynamic> run, {
    required bool networkUp,
  }) async {
    final id = run['id'] as String? ?? _uuid.v4();
    final payload = {...run, 'id': id};
    await OutboxService.instance.enqueue('runs', id, payload);
    if (SupabaseService.instance.canWriteRemote(networkUp)) {
      try {
        await SupabaseService.instance.supabase
            .from('runs')
            .upsert(payload, onConflict: 'id');
        await OutboxService.instance.markSuccess(id);
      } catch (e) {
        debugPrint('[OutboxAwareWriter] writeRun failed, kept in outbox: $e');
        // Row stays in outbox; mark failed so the drainer applies backoff.
        await OutboxService.instance.markFailure(id, 0, error: e.toString());
      }
    }
  }

  /// Writes a zone row.
  /// If [edgeFunctionZoneId] matches [zone['id']], the edge function already
  /// created this row server-side — skip enqueue entirely to avoid a duplicate.
  Future<void> writeZone(
    Map<String, dynamic> zone, {
    required bool networkUp,
    String? edgeFunctionZoneId,
  }) async {
    final id = zone['id'] as String? ?? _uuid.v4();
    // Edge-function zone already created server-side — skip re-insertion.
    if (edgeFunctionZoneId != null && edgeFunctionZoneId == id) return;
    final payload = {...zone, 'id': id};
    await OutboxService.instance.enqueue('zones', id, payload);
    if (SupabaseService.instance.canWriteRemote(networkUp)) {
      try {
        await SupabaseService.instance.supabase
            .from('zones')
            .upsert(payload, onConflict: 'id');
        await OutboxService.instance.markSuccess(id);
      } catch (e) {
        debugPrint('[OutboxAwareWriter] writeZone failed, kept in outbox: $e');
        // Row stays in outbox; mark failed so the drainer applies backoff.
        await OutboxService.instance.markFailure(id, 0, error: e.toString());
      }
    }
  }

  /// Writes a batch of GPS sample rows.
  /// Enqueues as a single outbox row with all samples serialised under 'samples'.
  Future<void> writeGpsSamples(
    List<Map<String, dynamic>> samples, {
    required bool networkUp,
  }) async {
    if (samples.isEmpty) return;
    final batchId = _uuid.v4();
    // Enqueue BEFORE the network call so data survives a connection drop.
    await OutboxService.instance.enqueue(
      'gps_samples',
      batchId,
      {'samples': samples},
    );
    if (SupabaseService.instance.canWriteRemote(networkUp)) {
      try {
        await SupabaseService.instance.supabase
            .from('gps_samples')
            .upsert(samples, onConflict: 'session_id,ts,player_id');
        await OutboxService.instance.markSuccess(batchId);
      } catch (e) {
        debugPrint(
            '[OutboxAwareWriter] writeGpsSamples failed, kept in outbox: $e');
        // Row stays in outbox; mark failed so the drainer applies backoff.
        await OutboxService.instance.markFailure(batchId, 0,
            error: e.toString());
      }
    }
  }

  /// Writes a partial update to an existing `runs` row.
  ///
  /// Uses [OutboxService.mergeEnqueue] so multiple calls for the same
  /// [id] accumulate their fields instead of overwriting each other
  /// (prevents offline confirmClaim fields being lost when stopRun follows).
  ///
  /// If [networkUp] is true, an immediate upsert is attempted with
  /// `onConflict: 'id'` so only the changed columns need to be sent.
  Future<void> writeRunUpdate(
    String id,
    Map<String, dynamic> fields, {
    required bool networkUp,
  }) async {
    await OutboxService.instance.mergeEnqueue('runs', id, fields);
    if (SupabaseService.instance.canWriteRemote(networkUp)) {
      try {
        await SupabaseService.instance.supabase
            .from('runs')
            .upsert({...fields, 'id': id}, onConflict: 'id');
        await OutboxService.instance.markSuccess(id);
      } catch (e) {
        debugPrint('[OutboxAwareWriter] writeRunUpdate failed, kept in outbox: $e');
        await OutboxService.instance.markFailure(id, 0, error: e.toString());
      }
    }
  }

  /// Generic write for tables not yet migrated to a dedicated method.
  /// Enqueues and, if online, drains via [OutboxDrainer].
  Future<void> write(
    String tableName,
    Map<String, dynamic> payload, {
    required bool networkUp,
  }) async {
    final id = payload['id'] as String? ?? _uuid.v4();
    final row = {...payload, 'id': id};
    await OutboxService.instance.enqueue(tableName, id, row);
    if (SupabaseService.instance.canWriteRemote(networkUp)) {
      unawaited(OutboxDrainer.instance.drain());
    }
  }
}
