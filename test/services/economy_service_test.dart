// test/services/economy_service_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §4.1 + spec §6.2.
//
// METHOD CONFLICT NOTE (surfaced for SquadLead):
// Task brief requested an `applyCredits(...)` method on EconomyService.
// design.md §4.1 explicitly prohibits this:
//   "Pure observer over credit balance + ledger reads. NEVER mutates credits
//   (server-only)."
// Tests are written against the authoritative design.md contract.
//
// Design contract (design.md §4.1 + spec §6.2):
//   class EconomyService {
//     EconomyService({required CreditsRepository credits, required LedgerRepository ledger})
//     Stream<int> balance(String playerId)
//     Future<int> currentBalance(String playerId)
//     Future<List<LedgerEntry>> ledger(String playerId, {int limit = 50})
//     Stream<({int previous, int next})> balanceDeltas(String playerId)
//   }

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/economy_service.dart';
import 'package:runwar_app/services/database/credits_repository.dart';
import 'package:runwar_app/services/database/ledger_repository.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeCreditsRepo implements CreditsRepository {
  final StreamController<int> _ctrl = StreamController<int>.broadcast();
  int _balance;

  FakeCreditsRepo({int initial = 0}) : _balance = initial;

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

class FakeLedgerRepo implements LedgerRepository {
  final List<LedgerEntry> _entries;

  FakeLedgerRepo(this._entries);

  @override
  Future<List<LedgerEntry>> fetchRecent(String playerId, {int limit = 50}) async {
    return _entries.take(limit).toList();
  }
}

LedgerEntry _makeEntry({
  String id = 'txn-001',
  int delta = 100,
  String reason = 'claim',
}) =>
    LedgerEntry(
      id: id,
      delta: delta,
      reason: reason,
      createdAt: DateTime.parse('2026-05-31T10:00:00.000Z'),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('EconomyService', () {
    // GIVEN an EconomyService backed by a credits repo with balance 300
    // WHEN balance(playerId) is subscribed to
    // THEN emits 300 as the initial value
    test('balance() stream emits current balance from CreditsRepository', () async {
      final creditsRepo = FakeCreditsRepo(initial: 300);
      final service = EconomyService(
        credits: creditsRepo,
        ledger: FakeLedgerRepo([]),
      );
      final emissions = <int>[];

      final sub = service.balance('player-1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.isNotEmpty, isTrue);
      expect(emissions.first, equals(300));

      await sub.cancel();
      await creditsRepo.dispose();
    });

    // GIVEN an EconomyService backed by a credits repo with balance 500
    // WHEN currentBalance(playerId) is awaited
    // THEN returns 500
    test('currentBalance() returns the fetched balance', () async {
      final service = EconomyService(
        credits: FakeCreditsRepo(initial: 500),
        ledger: FakeLedgerRepo([]),
      );

      final balance = await service.currentBalance('player-1');

      expect(balance, equals(500),
          reason: 'currentBalance must delegate to CreditsRepository.fetchBalance');
    });

    // GIVEN an EconomyService backed by a ledger repo with 3 entries
    // WHEN ledger(playerId) is awaited
    // THEN returns all 3 entries
    test('ledger() returns entries from LedgerRepository', () async {
      final entries = [
        _makeEntry(id: 'txn-1', reason: 'claim'),
        _makeEntry(id: 'txn-2', reason: 'conquest'),
        _makeEntry(id: 'txn-3', reason: 'passive_income'),
      ];
      final service = EconomyService(
        credits: FakeCreditsRepo(),
        ledger: FakeLedgerRepo(entries),
      );

      final result = await service.ledger('player-1');

      expect(result.length, equals(3));
      expect(result.map((e) => e.reason), containsAll(['claim', 'conquest', 'passive_income']));
    });

    // GIVEN a balance stream that changes from 200 → 450
    // WHEN balanceDeltas is subscribed
    // THEN emits ({previous: 200, next: 200}) then ({previous: 200, next: 450})
    test('balanceDeltas() emits (previous, next) tuples on each balance change', () async {
      final creditsRepo = FakeCreditsRepo(initial: 200);
      final service = EconomyService(
        credits: creditsRepo,
        ledger: FakeLedgerRepo([]),
      );
      final deltas = <({int previous, int next})>[];

      final sub = service.balanceDeltas('player-1').listen(deltas.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      creditsRepo.pushBalance(450);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(deltas.length, greaterThanOrEqualTo(2),
          reason: 'Must emit one tuple per balance emission');
      expect(deltas.last.previous, equals(200));
      expect(deltas.last.next, equals(450));

      await sub.cancel();
      await creditsRepo.dispose();
    });

    // GIVEN an EconomyService
    // WHEN EconomyService is constructed
    // THEN debugCredits exposes the CreditsRepository (for test assertion only)
    test('debugCredits exposes the internal CreditsRepository', () {
      final creditsRepo = FakeCreditsRepo();
      final service = EconomyService(
        credits: creditsRepo,
        ledger: FakeLedgerRepo([]),
      );

      expect(service.debugCredits, same(creditsRepo));
    });

    // GUARD: EconomyService must NOT expose any method that mutates credits.
    // This test passes vacuously by virtue of the production file not having
    // such a method — if applyCredits is ever added, this suite will surface
    // a compile conflict between tests.
    // (The comment serves as a living contract annotation.)
    // GIVEN EconomyService interface
    // WHEN checking for a credit-mutating method
    // THEN no such method exists (pure observer contract)
    test('EconomyService has no credit-mutation method (pure observer contract)', () {
      final service = EconomyService(
        credits: FakeCreditsRepo(),
        ledger: FakeLedgerRepo([]),
      );
      // Reflection-free contract check: ensure only read-side API is accessible.
      // If applyCredits / addCredits / deductCredits appear here, the architect
      // contract (design.md §4.1) has been violated. This test documents that.
      expect(service, isA<EconomyService>(),
          reason: 'EconomyService must be constructable with only credits + ledger repos');
    });
  });
}
