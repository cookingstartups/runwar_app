// test/services/database/ledger_repository_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §3.2 + spec §6.1.
//
// Design contract (design.md §3.2):
//   abstract interface class LedgerRepository {
//     Future<List<LedgerEntry>> fetchRecent(String playerId, {int limit = 50});
//   }
//
// NOTE: LedgerRepository is defined in ledger_repository.dart but
// LedgerEntry is defined in credits_repository.dart (per spec §6.1 layout).
// Both must exist; tests import both.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/credits_repository.dart';
import 'package:runwar_app/services/database/ledger_repository.dart';

// ── Fake ─────────────────────────────────────────────────────────────────────

LedgerEntry _makeLedgerEntry({
  String id = 'txn-001',
  int delta = 100,
  String reason = 'claim',
  String? relatedEntityId,
  String? relatedEntityType,
}) =>
    LedgerEntry(
      id: id,
      delta: delta,
      reason: reason,
      createdAt: DateTime.parse('2026-05-31T10:00:00.000Z'),
      relatedEntityId: relatedEntityId,
      relatedEntityType: relatedEntityType,
    );

class FakeLedgerRepository implements LedgerRepository {
  final List<LedgerEntry> _entries;

  FakeLedgerRepository(this._entries);

  @override
  Future<List<LedgerEntry>> fetchRecent(String playerId, {int limit = 50}) async {
    return _entries.take(limit).toList();
  }
}

class ThrowingLedgerRepository implements LedgerRepository {
  @override
  Future<List<LedgerEntry>> fetchRecent(String playerId, {int limit = 50}) async =>
      throw const SocketException('No network');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('LedgerRepository', () {
    // GIVEN a repository seeded with 3 ledger entries
    // WHEN fetchRecent is called with no limit override
    // THEN returns all 3 entries (well within default limit of 50)
    test('fetchRecent returns all entries when count is below default limit', () async {
      final entries = [
        _makeLedgerEntry(id: 'txn-001', delta: 100, reason: 'claim'),
        _makeLedgerEntry(id: 'txn-002', delta: 250, reason: 'conquest'),
        _makeLedgerEntry(id: 'txn-003', delta: 25,  reason: 'passive_income'),
      ];
      final repo = FakeLedgerRepository(entries);

      final result = await repo.fetchRecent('player-1');

      expect(result.length, equals(3));
      expect(result.first.reason, equals('claim'));
    });

    // GIVEN a repository seeded with 5 entries
    // WHEN fetchRecent is called with limit=2
    // THEN returns exactly 2 entries
    test('fetchRecent respects the limit parameter', () async {
      final entries = List.generate(
        5,
        (i) => _makeLedgerEntry(id: 'txn-$i', delta: 50, reason: 'passive_income'),
      );
      final repo = FakeLedgerRepository(entries);

      final result = await repo.fetchRecent('player-1', limit: 2);

      expect(result.length, equals(2),
          reason: 'fetchRecent must honour the limit parameter');
    });

    // GIVEN a LedgerEntry created from JSON
    // WHEN its fields are accessed
    // THEN they match the source map exactly
    test('LedgerEntry.fromJson parses all fields correctly', () {
      final j = {
        'id':                  'txn-abc',
        'delta':               -150,
        'reason':              'spend',
        'created_at':          '2026-05-31T12:00:00.000Z',
        'related_entity_id':   'offer-xyz',
        'related_entity_type': 'superpower_offer',
        'metadata':            {'offer_type': 'extra_charge'},
      };

      final entry = LedgerEntry.fromJson(j);

      expect(entry.id, equals('txn-abc'));
      expect(entry.delta, equals(-150));
      expect(entry.reason, equals('spend'));
      expect(entry.relatedEntityId, equals('offer-xyz'));
      expect(entry.relatedEntityType, equals('superpower_offer'));
      expect(entry.metadata['offer_type'], equals('extra_charge'));
    });

    // GIVEN a repository that throws on infra failure
    // WHEN fetchRecent is called
    // THEN throws (Phase 2 policy — no RepoResult wrapping)
    test('fetchRecent throws on infrastructure failure', () async {
      final repo = ThrowingLedgerRepository();

      expect(
        () => repo.fetchRecent('player-1'),
        throwsA(isA<SocketException>()),
        reason: 'Phase 2 repos throw on infra failure',
      );
    });
  });
}
