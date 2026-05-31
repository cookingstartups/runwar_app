// lib/providers/dispute_countdown_provider.dart
//
// disputeCountdownProvider — ticking countdown stream for an open dispute.
//
// Declared as Provider.family<Stream<Duration>, String> (NOT StreamProvider)
// so that container.read(disputeCountdownProvider('id')) returns Stream<Duration>.
// This matches the test assertions: .listen, .take, .first on the raw stream.
//
// The stream is a broadcast stream (.asBroadcastStream()) so multiple
// concurrent listeners are supported without "already listened to" errors.
//
// Behaviour:
//   - Fetches the open dispute ONCE at first subscription.
//   - Yields Duration.zero immediately if no open dispute or already expired.
//   - Ticks every 1 second while active.
//   - Closes after yielding Duration.zero.
//
// NOTE: Does NOT use autoDispose here — the stream itself is stateless
// (async* generator), so there is no resource to clean up. Riverpod disposes
// the Provider when the container disposes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database/repository.dart';
import '../services/database/models/dispute.dart';
import 'disputes_repository_provider.dart';

/// Returns a broadcast [Stream<Duration>] that emits the remaining countdown
/// once per second, terminating at (and including) [Duration.zero].
final disputeCountdownProvider =
    Provider.family<Stream<Duration>, String>(
  (ref, zoneId) {
    final repo = ref.watch(disputesRepositoryProvider);
    return _countdownStream(repo, zoneId).asBroadcastStream();
  },
);

Stream<Duration> _countdownStream(dynamic repo, String zoneId) async* {
  final res = await repo.fetchOpenForZone(zoneId);

  if (res is! Ok || res.value == null) {
    yield Duration.zero;
    return;
  }

  final expires = (res.value as Dispute).expiresAt;

  while (true) {
    final left = expires.difference(DateTime.now());
    if (left <= Duration.zero) {
      yield Duration.zero;
      return;
    }
    yield left;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}
