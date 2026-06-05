// DEPRECATED (Phase 1): superseded by LocalZonesRepository.
// All functionality moved to lib/services/database/zones_repository_local.dart.
// This file is retained for the Phase 1 transition; remove in Phase 2 (task RW-P2-01).
import 'dart:async';
import 'database_service.dart';

/// @Deprecated Use LocalZonesRepository via zonesRepositoryProvider instead.
class ZonesService {
  ZonesService._();
  static final ZonesService instance = ZonesService._();

  /// AC-1. Returns all rows where city = [city]. Empty list on no match
  /// (including empty string). Never throws on empty / no-match.
  Future<List<Map<String, dynamic>>> fetchZonesByCity(String city) async {
    return DatabaseService.instance.getZonesByCity(city);
  }

  /// AC-2. Emits the current zone list immediately, then every 5 seconds.
  /// Each emission is an independent full query (no diffing). The 5s timer
  /// is cancelled when the stream loses its last listener (StreamController
  /// onCancel callback) — this is what makes AC-17 work end-to-end.
  Stream<List<Map<String, dynamic>>> watchZonesByCity(String city) {
    late StreamController<List<Map<String, dynamic>>> controller;
    Timer? timer;
    var cancelled = false;

    Future<void> emit() async {
      if (cancelled || controller.isClosed) return;
      try {
        final rows = await fetchZonesByCity(city);
        if (cancelled || controller.isClosed) return;
        controller.add(rows);
      } catch (e, st) {
        if (cancelled || controller.isClosed) return;
        controller.addError(e, st); // AC-18 surfaces this via AsyncValue.error
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        // Immediate first emit (microtask so subscribe completes first).
        scheduleMicrotask(emit);
        // Then every 5s for the lifetime of the listener.
        timer = Timer.periodic(const Duration(seconds: 5), (_) => emit());
      },
      onCancel: () async {
        cancelled = true;
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }

  /// AC-3. Count of zones owned by [userId] with status='owned'.
  /// Returns 0 if none. Disputed zones not counted.
  Future<int> countOwnedByUser(String userId) async {
    final zones = await DatabaseService.instance.getZonesByOwner(userId);
    return zones.where((z) => z['status'] == 'owned').length;
  }
}
