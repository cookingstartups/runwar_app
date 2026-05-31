// test/providers/dispute_countdown_provider_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Each test maps to one GIVEN/WHEN/THEN from design.md §5 + phase spec §8.
//
// Design contract (design.md §5):
//   disputeCountdownProvider = StreamProvider.family.autoDispose<Duration, String>
//   - Fetches open dispute via fetchOpenForZone(zoneId) once at init
//   - Ticks with 1-second resolution: yields remaining duration each second
//   - When remaining <= Duration.zero: yields Duration.zero and stream terminates
//   - If no open dispute found (Ok(null) or Err): yields Duration.zero immediately

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:runwar_app/providers/dispute_countdown_provider.dart';
import 'package:runwar_app/providers/disputes_repository_provider.dart';
import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/disputes_repository.dart';
import 'package:runwar_app/services/database/models/dispute.dart';

// ── Mock ──────────────────────────────────────────────────────────────────────

class MockDisputesRepository extends Mock implements DisputesRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Creates a Dispute with expiresAt set [secsFromNow] seconds in the future.
Dispute _disputeExpiringIn(int secsFromNow, {String zoneId = 'zone-001'}) =>
    Dispute.fromRow({
      'id': 'dispute-001',
      'zone_id': zoneId,
      'attacker_id': 'attacker-abc',
      'defender_id': 'defender-xyz',
      'expires_at': DateTime.now()
          .toUtc()
          .add(Duration(seconds: secsFromNow))
          .toIso8601String(),
      'resolved_at': null,
      'winner_id': null,
      'created_at': '2026-05-31T10:00:00.000Z',
    });

/// Creates a Dispute that expired [secsAgo] seconds ago.
Dispute _disputeExpiredAgo(int secsAgo, {String zoneId = 'zone-001'}) =>
    Dispute.fromRow({
      'id': 'dispute-expired',
      'zone_id': zoneId,
      'attacker_id': 'attacker-abc',
      'defender_id': 'defender-xyz',
      'expires_at': DateTime.now()
          .toUtc()
          .subtract(Duration(seconds: secsAgo))
          .toIso8601String(),
      'resolved_at': null,
      'winner_id': null,
      'created_at': '2026-05-31T09:00:00.000Z',
    });

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // No custom fallback types needed for Dispute in Phase 1.
  });

  group('disputeCountdownProvider', () {
    // GIVEN a zone with an open dispute expiring in 5 seconds
    // WHEN the provider is watched
    // THEN emits decreasing Duration values each second
    test('emits decreasing Duration values each second', () async {
      final mockRepo = MockDisputesRepository();
      when(() => mockRepo.fetchOpenForZone('zone-001')).thenAnswer(
        (_) async => RepoResult.ok(_disputeExpiringIn(5)),
      );

      final container = ProviderContainer(overrides: [
        disputesRepositoryProvider.overrideWithValue(mockRepo),
      ]);
      addTearDown(container.dispose);

      final emissions = <Duration>[];
      final sub = container
          .read(disputeCountdownProvider('zone-001'))
          .listen(null);

      // Collect emissions over ~3 seconds.
      final completer = Completer<void>();
      container
          .read(disputeCountdownProvider('zone-001'))
          .take(3)
          .toList()
          .then((list) {
        emissions.addAll(list);
        completer.complete();
      });

      await completer.future.timeout(const Duration(seconds: 5));

      expect(emissions.length, equals(3),
          reason: 'Provider should emit once per second');
      // Each emission should be shorter than the previous.
      for (var i = 1; i < emissions.length; i++) {
        expect(emissions[i], lessThan(emissions[i - 1]),
            reason:
                'Countdown should decrease: ${emissions[i]} should be < ${emissions[i - 1]}');
      }

      await sub.cancel();
    });

    // GIVEN the countdown reaches zero
    // WHEN Duration.zero is yielded
    // THEN the stream terminates (no further emissions)
    test('stream terminates at Duration.zero', () async {
      final mockRepo = MockDisputesRepository();
      // Expiring in 2 seconds so the stream closes quickly in the test.
      when(() => mockRepo.fetchOpenForZone('zone-term')).thenAnswer(
        (_) async => RepoResult.ok(_disputeExpiringIn(2)),
      );

      final container = ProviderContainer(overrides: [
        disputesRepositoryProvider.overrideWithValue(mockRepo),
      ]);
      addTearDown(container.dispose);

      final allEmissions = <Duration>[];
      bool streamDone = false;

      // Use a Completer so that the onDone callback fires correctly.
      // StreamSubscription.asFuture() replaces the onDone handler set in
      // listen(), so the two cannot be combined — the Completer pattern
      // keeps them independent.
      final doneCompleter = Completer<void>();

      container
          .read(disputeCountdownProvider('zone-term'))
          .listen(
            allEmissions.add,
            onDone: () {
              streamDone = true;
              doneCompleter.complete();
            },
          );

      await doneCompleter.future.timeout(const Duration(seconds: 5));

      // The final emission must be Duration.zero.
      expect(allEmissions.last, equals(Duration.zero),
          reason: 'Stream must emit Duration.zero as its final value');
      expect(streamDone, isTrue,
          reason: 'Stream must complete (close) after emitting Duration.zero');
    });

    // GIVEN a zone whose dispute expires_at is already in the past
    // WHEN the provider is watched
    // THEN emits Duration.zero immediately (no countdown needed)
    test('emits Duration.zero immediately when expires_at is in the past', () async {
      final mockRepo = MockDisputesRepository();
      when(() => mockRepo.fetchOpenForZone('zone-past')).thenAnswer(
        (_) async => RepoResult.ok(_disputeExpiredAgo(30)),
      );

      final container = ProviderContainer(overrides: [
        disputesRepositoryProvider.overrideWithValue(mockRepo),
      ]);
      addTearDown(container.dispose);

      final firstEmission = await container
          .read(disputeCountdownProvider('zone-past'))
          .first
          .timeout(const Duration(seconds: 2));

      expect(firstEmission, equals(Duration.zero),
          reason:
              'When expires_at is in the past, Duration.zero must be emitted immediately');
    });
  });
}
