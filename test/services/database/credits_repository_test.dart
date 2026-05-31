// test/services/database/credits_repository_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §3 + phase
// spec §6.1.
//
// Design contract (design.md §3.2):
//   abstract interface class CreditsRepository {
//     Stream<int> watchBalance(String playerId);
//     Future<int> fetchBalance(String playerId);
//   }
//
// Phase 2 result-type policy (design.md §3.1):
//   Repos throw on infrastructure failure (no RepoResult<T>).
//   Streams emit raw data; subscribers handle onError.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/credits_repository.dart';

// ── Fake ─────────────────────────────────────────────────────────────────────

class FakeCreditsRepository implements CreditsRepository {
  final StreamController<int> _controller = StreamController<int>.broadcast();
  int _balance;
  bool disposeCalled = false;

  FakeCreditsRepository({int initialBalance = 0}) : _balance = initialBalance;

  void pushBalance(int b) {
    _balance = b;
    _controller.add(b);
  }

  @override
  Stream<int> watchBalance(String playerId) {
    // Emit immediately with current balance.
    Future.microtask(() => _controller.add(_balance));
    return _controller.stream;
  }

  @override
  Future<int> fetchBalance(String playerId) async => _balance;

  Future<void> dispose() async {
    disposeCalled = true;
    await _controller.close();
  }
}

class ThrowingCreditsRepository implements CreditsRepository {
  @override
  Stream<int> watchBalance(String playerId) =>
      Stream.error(const SocketException('No network'));

  @override
  Future<int> fetchBalance(String playerId) async =>
      throw const SocketException('No network');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('CreditsRepository', () {
    // GIVEN a repository with initial balance of 500
    // WHEN fetchBalance is called
    // THEN returns 500
    test('fetchBalance returns current balance', () async {
      final repo = FakeCreditsRepository(initialBalance: 500);

      final balance = await repo.fetchBalance('player-1');

      expect(balance, equals(500));
    });

    // GIVEN a repository seeded with balance 100
    // WHEN watchBalance is subscribed to
    // THEN emits the initial balance immediately
    test('watchBalance emits initial balance on subscribe', () async {
      final repo = FakeCreditsRepository(initialBalance: 100);
      final emissions = <int>[];

      final sub = repo.watchBalance('player-1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions, isNotEmpty, reason: 'Should emit at least one value');
      expect(emissions.first, equals(100));

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN a subscribed balance stream
    // WHEN a new balance is pushed (e.g. server credit award arrives via Realtime)
    // THEN the stream re-emits the updated balance
    test('watchBalance re-emits when balance changes', () async {
      final repo = FakeCreditsRepository(initialBalance: 200);
      final emissions = <int>[];

      final sub = repo.watchBalance('player-1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      repo.pushBalance(450);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last, equals(450),
          reason: 'Balance stream must emit updated value after server push');

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN a repository that throws SocketException on fetchBalance
    // WHEN fetchBalance is called
    // THEN throws (not returns RepoResult.err) — Phase 2 policy
    test('fetchBalance throws on infrastructure failure', () async {
      final repo = ThrowingCreditsRepository();

      expect(
        () => repo.fetchBalance('player-1'),
        throwsA(isA<SocketException>()),
        reason: 'Phase 2 repos throw on infra failure — no RepoResult wrapping',
      );
    });

    // GIVEN a repository that emits a SocketException on its stream
    // WHEN watchBalance is subscribed with an onError handler
    // THEN onError receives the SocketException
    test('watchBalance stream error propagates via onError', () async {
      final repo = ThrowingCreditsRepository();
      Object? caught;

      final sub = repo.watchBalance('player-1').listen(
        (_) {},
        onError: (e) => caught = e,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(caught, isA<SocketException>(),
          reason: 'Stream infra failure must propagate via onError, not throw');

      await sub.cancel();
    });
  });
}
