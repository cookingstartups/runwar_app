import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'outbox_service.dart';
import 'outbox_drainer.dart';
import 'supabase_service.dart';

/// Facade for all Supabase write paths.
/// Every write is enqueued in the outbox BEFORE any network call (AC-10).
/// If [canWriteRemote] is true, a drain attempt follows immediately.
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
        // Row stays in outbox for drainer to retry.
      }
    }
  }

  /// Writes a zone row.
  /// If [edgeFunctionZoneId] matches [zone['id']], the edge function already
  /// created this row server-side — skip enqueue entirely (AC-14).
  Future<void> writeZone(
    Map<String, dynamic> zone, {
    required bool networkUp,
    String? edgeFunctionZoneId,
  }) async {
    final id = zone['id'] as String? ?? _uuid.v4();
    // AC-14: edge-function zone idempotency — do not re-insert.
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
    // Enqueue BEFORE network call (AC-10).
    await OutboxService.instance.enqueue(
      'gps_samples',
      batchId,
      {'samples': samples},
    );
    if (SupabaseService.instance.canWriteRemote(networkUp)) {
      try {
        await SupabaseService.instance.supabase
            .from('gps_samples')
            .insert(samples);
        await OutboxService.instance.markSuccess(batchId);
      } catch (e) {
        debugPrint(
            '[OutboxAwareWriter] writeGpsSamples failed, kept in outbox: $e');
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
