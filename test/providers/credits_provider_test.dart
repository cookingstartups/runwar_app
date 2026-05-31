// test/providers/credits_provider_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §5.1 + spec §6.3.
//
// METHOD CONFLICT NOTE (surfaced for SquadLead):
// Task brief referred to this provider as `creditsProvider`.
// design.md §5.1 names it `creditsBalanceProvider` (StreamProvider.family<int, String>).
// Tests use the authoritative name from design.md.
//
// Design contract (design.md §5.1):
//   final creditsBalanceProvider = StreamProvider.family<int, String>(
//     (r, playerId) => r.read(creditsRepoProvider).watchBalance(playerId));

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/providers/economy/credits_provider.dart';
import 'package:runwar_app/services/database/credits_repository.dart';

import '../_helpers/test_container.dart';

// ── Fake ─────────────────────────────────────────────────────────────────────

class FakeCreditsRepoForProvider implements CreditsRepository {
  final StreamController<int> _ctrl = StreamController<int>.broadcast();
  int _balance;

  FakeCreditsRepoForProvider({int initial = 0}) : _balance = initial;

  void pushBalance(int b) {
    _balance = b;
    _ctrl.add(b);
  }

  @override
  Stream<int> watchBalance(String playerId) {
    Future.microtask(() => _ctrl.add(_balance));
    return _ctrl.stream;
  }

  @override
  Future<int> fetchBalance(String playerId) async => _balance;

  Future<void> dispose() async => _ctrl.close();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('creditsBalanceProvider', () {
    // GIVEN a creditsRepoProvider overridden with a FakeCreditsRepo(initial=250)
    // WHEN creditsBalanceProvider('player-1') is read
    // THEN resolves to AsyncData(250)
    test('resolves to AsyncData with the balance from CreditsRepository', () async {
      final fakeRepo = FakeCreditsRepoForProvider(initial: 250);
      final container = makeTestContainer(creditsRepo: fakeRepo);
      addTearDown(container.dispose);

      final sub = container.listen(
        creditsBalanceProvider('player-1'),
        (_, __) {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final state = container.read(creditsBalanceProvider('player-1'));

      expect(state, isA<AsyncData<int>>(),
          reason: 'creditsBalanceProvider must expose AsyncData when repo emits');
      expect(state.value, equals(250));

      sub.close();
      await fakeRepo.dispose();
    });

    // GIVEN a balance stream that changes from 100 → 600
    // WHEN the stream pushes 600
    // THEN creditsBalanceProvider updates to AsyncData(600)
    test('creditsBalanceProvider updates when the balance stream emits a new value', () async {
      final fakeRepo = FakeCreditsRepoForProvider(initial: 100);
      final container = makeTestContainer(creditsRepo: fakeRepo);
      addTearDown(container.dispose);

      final emissions = <AsyncValue<int>>[];
      final sub = container.listen(
        creditsBalanceProvider('player-1'),
        (_, next) => emissions.add(next),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      fakeRepo.pushBalance(600);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final data = emissions.whereType<AsyncData<int>>().toList();
      expect(data.isNotEmpty, isTrue);
      expect(data.last.value, equals(600),
          reason: 'Provider must track balance stream updates');

      sub.close();
      await fakeRepo.dispose();
    });

    // GIVEN different playerIds as the family key
    // WHEN creditsBalanceProvider('player-A') and creditsBalanceProvider('player-B') are read
    // THEN they are separate provider instances (family isolation)
    test('creditsBalanceProvider.family creates separate instances per playerId', () async {
      final fakeRepo = FakeCreditsRepoForProvider(initial: 0);
      final container = makeTestContainer(creditsRepo: fakeRepo);
      addTearDown(container.dispose);

      // Just verify the family discriminates — two different keys are distinct providers.
      final provA = creditsBalanceProvider('player-A');
      final provB = creditsBalanceProvider('player-B');

      expect(provA == provB, isFalse,
          reason: 'Different playerIds must produce different provider instances');
    });
  });
}
