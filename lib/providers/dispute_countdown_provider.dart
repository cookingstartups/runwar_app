// lib/providers/dispute_countdown_provider.dart
//
// disputeCountdownProvider — ticking countdown stream for an open dispute.
//
// Re-pointed at the zone's own status/dispute_at fields (via ZonesRepository)
// instead of the retired disputes table and its repository (spec R11-AC1).
// The Duration-computation/streaming contract is UNCHANGED - only the data
// source moved.
//
// Declared as Provider.family<Stream<Duration>, String> (NOT StreamProvider)
// so that container.read(disputeCountdownProvider('id')) returns Stream<Duration>.
// This matches the test assertions: .listen, .take, .first on the raw stream.
//
// Uses a broadcast StreamController with onListen callback so that:
//   1. Multiple concurrent listeners are supported.
//   2. onDone propagates correctly to every listener.
//   3. The async* driver starts only when the first listener subscribes.
//
// Behaviour:
//   - Fetches the zone ONCE at first subscription (onListen callback).
//   - Yields Duration.zero immediately if the zone is not disputed (or has
//     no dispute_at) or is already past its deadline.
//   - Ticks every 1 second while active.
//   - Closes the StreamController (and fires onDone) after yielding Duration.zero.
//
// NOTE: Does NOT use autoDispose — the Provider is disposed by the container.
// ref.onDispose closes the controller if the provider is torn down early.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database/repository.dart';
import '../services/database/zones_repository.dart';
import '../services/database/models/zone.dart';
import 'zones_repository_provider.dart';

/// Returns a broadcast [Stream<Duration>] that emits the remaining countdown
/// once per second, terminating at (and including) [Duration.zero].
///
/// Uses [Timer.periodic] (cancellable) instead of [Future.delayed]
/// (non-cancellable) so that test teardown finds no pending timers when
/// [ref.onDispose] fires before the countdown reaches zero.
final disputeCountdownProvider =
    Provider.family<Stream<Duration>, String>(
  (ref, zoneId) {
    final repo = ref.watch(zonesRepositoryProvider);

    // ticker is set by _driveCountdown after the fetch completes.
    // ref.onDispose cancels it directly so no pending timer is left
    // when the provider is torn down (e.g. during test teardown).
    Timer? ticker;

    late StreamController<Duration> controller;
    controller = StreamController<Duration>.broadcast(
      onListen: () {
        // Drive the countdown asynchronously so onListen returns immediately.
        Future.microtask(
          () => _driveCountdown(repo, zoneId, controller, (t) => ticker = t),
        );
      },
      onCancel: () {
        // Cancel the ticker when the last listener unsubscribes.
        // This handles the case where the widget unmounts before the countdown
        // reaches zero — e.g. during test teardown or navigation away.
        ticker?.cancel();
        ticker = null;
      },
    );

    ref.onDispose(() {
      ticker?.cancel();
      ticker = null;
      if (!controller.isClosed) controller.close();
    });

    return controller.stream;
  },
);

Future<void> _driveCountdown(
  ZonesRepository repo,
  String zoneId,
  StreamController<Duration> controller,
  void Function(Timer?) onTickerCreated,
) async {
  if (controller.isClosed) return;

  final res = await repo.fetchById(zoneId);

  if (controller.isClosed) return;

  if (res is! Ok<Zone> ||
      res.value.status != ZoneStatus.disputed ||
      res.value.disputeAt == null) {
    controller.add(Duration.zero);
    if (!controller.isClosed) controller.close();
    return;
  }

  final expires = res.value.disputeAt!;
  Timer? ticker;

  void tick() {
    if (controller.isClosed) {
      ticker?.cancel();
      onTickerCreated(null);
      return;
    }
    final left = expires.difference(DateTime.now().toUtc());
    if (left <= Duration.zero) {
      controller.add(Duration.zero);
      ticker?.cancel();
      onTickerCreated(null);
      if (!controller.isClosed) controller.close();
    } else {
      controller.add(left);
    }
  }

  // Emit immediately, then every 1 s via a cancellable Timer.periodic.
  tick();
  ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  // Publish the ticker reference so ref.onDispose can cancel it directly.
  onTickerCreated(ticker);
}
