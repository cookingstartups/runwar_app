// lib/providers/dispute_countdown_provider.dart
//
// disputeCountdownProvider — ticking countdown stream for an open dispute.
//
// Declared as Provider.family<Stream<Duration>, String> (NOT StreamProvider)
// so that container.read(disputeCountdownProvider('id')) returns Stream<Duration>.
// This matches the test assertions: .listen, .take, .first on the raw stream.
//
// Uses a broadcast StreamController with onListen callback so that:
//   1. Multiple concurrent listeners are supported.
//   2. onDone propagates correctly to every listener (test 2 requirement).
//   3. The async* driver starts only when the first listener subscribes.
//
// Behaviour:
//   - Fetches the open dispute ONCE at first subscription (onListen callback).
//   - Yields Duration.zero immediately if no open dispute or already expired.
//   - Ticks every 1 second while active.
//   - Closes the StreamController (and fires onDone) after yielding Duration.zero.
//
// NOTE: Does NOT use autoDispose — the Provider is disposed by the container.
// ref.onDispose closes the controller if the provider is torn down early.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database/repository.dart';
import '../services/database/disputes_repository.dart';
import '../services/database/models/dispute.dart';
import 'disputes_repository_provider.dart';

/// Returns a broadcast [Stream<Duration>] that emits the remaining countdown
/// once per second, terminating at (and including) [Duration.zero].
final disputeCountdownProvider =
    Provider.family<Stream<Duration>, String>(
  (ref, zoneId) {
    final repo = ref.watch(disputesRepositoryProvider);

    late StreamController<Duration> controller;
    controller = StreamController<Duration>.broadcast(
      onListen: () {
        // Drive the countdown asynchronously so onListen returns immediately.
        Future.microtask(() => _driveCountdown(repo, zoneId, controller));
      },
    );

    ref.onDispose(() {
      if (!controller.isClosed) controller.close();
    });

    return controller.stream;
  },
);

Future<void> _driveCountdown(
  DisputesRepository repo,
  String zoneId,
  StreamController<Duration> controller,
) async {
  if (controller.isClosed) return;

  final res = await repo.fetchOpenForZone(zoneId);

  if (controller.isClosed) return;

  if (res is! Ok<Dispute?> || res.value == null) {
    controller.add(Duration.zero);
    await controller.close();
    return;
  }

  final expires = res.value!.expiresAt;

  while (!controller.isClosed) {
    final left = expires.difference(DateTime.now());
    if (left <= Duration.zero) {
      controller.add(Duration.zero);
      await controller.close();
      return;
    }
    controller.add(left);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}
