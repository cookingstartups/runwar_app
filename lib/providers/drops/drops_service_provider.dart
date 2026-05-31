// lib/providers/drops/drops_service_provider.dart
//
// Provider for DropsService — architect addition (design.md §5.2).
//
// DEPENDENCY NOTE: DropsService requires a GpsStream. At Phase 2 ship time the
// concrete GPS adapter (backed by RunRecorderService) is wired here as a
// _NoOpGpsStream placeholder. Wire the real GPS source in P2-FL-03 once the
// run_recorder GPS observable is extracted into a Riverpod-visible stream.
// Track as: TODO(P2-FL-03) — replace _NoOpGpsStream with real GPS provider.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../services/drops_service.dart';
import '../repositories.dart';

/// Minimal no-op GPS adapter used until P2-FL-03 wires the real GPS stream.
class _NoOpGpsStream implements GpsStream {
  @override
  LatLng? get last => null;
}

/// DropsService for the session.
/// ref.onDispose calls stop() so the polling timer is cancelled when the
/// provider scope is disposed (e.g. on sign-out).
final dropsServiceProvider = Provider<DropsService>((ref) {
  final service = DropsService(
    repo: ref.read(dropsRepoProvider),
    gps: _NoOpGpsStream(), // TODO(P2-FL-03): replace with real GPS provider
  );
  ref.onDispose(service.stop);
  return service;
});
