// lib/services/drops_service.dart
//
// DropsService — 10 s poll loop + proximity claim while MapScreen is mounted.
// Phase 2 design.md §4.1 + §4.2.
//
// CONTRACT:
//   - DropsService does NOT import supabase_flutter.
//   - start(city) must be called after MapScreen mounts.
//   - stop() / dispose() are idempotent; both are called by ref.onDispose.
//   - GpsStream is an abstract adapter; the provider wires in the concrete GPS source.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'database/drops_repository.dart';

/// Minimal GPS adapter interface consumed by [DropsService].
/// The Riverpod provider supplies a concrete implementation backed by the
/// existing run_recorder_service GPS stream (P2-FL-03).
abstract class GpsStream {
  /// Most recent GPS position, or null if unavailable.
  LatLng? get last;
}

/// 10 s proximity-poll loop that claims nearby drops automatically.
///
/// Lifecycle:
///   1. Provider creates instance via [dropsServiceProvider].
///   2. MapScreen calls [start(city)] in initState.
///   3. MapScreen calls [stop()] in dispose.
///   4. Riverpod calls [stop()] again via ref.onDispose (idempotent).
class DropsService {
  DropsService({
    required DropsRepository repo,
    required GpsStream gps,
    Duration pollInterval = const Duration(seconds: 10),
    double pickupRadiusM = 30,
  })  : _repo = repo,
        _gps = gps,
        _pollInterval = pollInterval,
        _pickupRadiusM = pickupRadiusM;

  final DropsRepository _repo;
  final GpsStream _gps;
  final Duration _pollInterval;
  final double _pickupRadiusM;

  StreamSubscription<List<Drop>>? _sub;
  Timer? _timer;
  List<Drop> _active = const [];
  bool _busy = false;

  /// Called on claim success. UI subscribes to display a toast/animation.
  void Function(ClaimDropResult)? onClaimed;

  /// Called on business-level claim failure (not infra failure).
  void Function(String reason)? onClaimError;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Start watching drops for [city] and polling for proximity claims.
  /// Safe to call multiple times — cancels the previous subscription first.
  void start(String city) {
    _sub?.cancel();
    _sub = _repo.watchActive(city).listen(
      (drops) => _active = drops,
      onError: (Object e) {
        debugPrint('[DropsService] watch error: $e');
      },
    );
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _tick());
  }

  /// Stop the polling loop and cancel the Realtime subscription.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    _active = const [];
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<void> _tick() async {
    if (_busy) return;
    final pos = _gps.last;
    if (pos == null || _active.isEmpty) return;

    Drop? nearest;
    double nearestM = double.infinity;
    for (final d in _active) {
      final m =
          _haversineM(pos.latitude, pos.longitude, d.lat, d.lng);
      if (m < nearestM) {
        nearestM = m;
        nearest = d;
      }
    }
    if (nearest == null || nearestM > _pickupRadiusM) return;

    _busy = true;
    try {
      final result =
          await _repo.claim(nearest.id, pos.latitude, pos.longitude);
      if (result is ClaimDropFailure) {
        onClaimError?.call(result.reason);
      } else {
        onClaimed?.call(result);
      }
    } catch (e) {
      debugPrint('[DropsService] claim error: $e');
      onClaimError?.call('error');
    } finally {
      _busy = false;
    }
  }

  static double _haversineM(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.asin(math.sqrt(a));
  }
}
