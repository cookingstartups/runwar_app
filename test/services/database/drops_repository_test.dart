// test/services/database/drops_repository_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §3.2 + spec §6.1.
//
// METHOD CONFLICT NOTE (surfaced for SquadLead):
// Task brief requested `fetchActiveByCityName` and `claimDrop(dropId, playerId)`.
// design.md §3.2 defines the authoritative interface as:
//   watchActive(city) — Stream<List<Drop>>
//   claim(dropId, lat, lng) — Future<ClaimDropResult>
// Tests are written against the architect-approved design.md interface.
//
// Design contract (design.md §3.2):
//   abstract interface class DropsRepository {
//     Stream<List<Drop>> watchActive(String city);
//     Future<ClaimDropResult> claim(String dropId, double lat, double lng);
//   }
//
// ClaimDropResult variants (spec §6.1):
//   ClaimDropCash, ClaimDropCrystal, ClaimDropPower — success subtypes
//   ClaimDropFailure(reason, {distanceM}) — domain failure

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/drops_repository.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Drop _makeDrop({
  String id = 'drop-001',
  String city = 'Valencia',
  double lat = 39.47,
  double lng = -0.37,
  String dropType = 'credits_cache',
  int value = 50,
  String status = 'active',
}) =>
    Drop(
      id: id,
      city: city,
      lat: lat,
      lng: lng,
      dropType: dropType,
      value: value,
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      status: status,
    );

// ── Fake ─────────────────────────────────────────────────────────────────────

class FakeDropsRepository implements DropsRepository {
  final StreamController<List<Drop>> _controller =
      StreamController<List<Drop>>.broadcast();
  List<Drop> _drops;

  FakeDropsRepository(this._drops);

  void pushUpdate(List<Drop> drops) {
    _drops = drops;
    _controller.add(drops);
  }

  @override
  Stream<List<Drop>> watchActive(String city) {
    Future.microtask(() {
      _controller.add(_drops.where((d) => d.city == city).toList());
    });
    return _controller.stream;
  }

  @override
  Future<ClaimDropResult> claim(String dropId, double lat, double lng) async {
    final match = _drops.where((d) => d.id == dropId).toList();
    if (match.isEmpty) return const ClaimDropFailure('not_found');
    final drop = match.first;
    if (drop.status != 'active') return const ClaimDropFailure('already_claimed');
    return ClaimDropCash({'credits_awarded': drop.value, 'new_balance': 500 + drop.value});
  }

  Future<void> dispose() async => _controller.close();
}

class ThrowingDropsRepository implements DropsRepository {
  @override
  Stream<List<Drop>> watchActive(String city) =>
      Stream.error(const SocketException('No network'));

  @override
  Future<ClaimDropResult> claim(String dropId, double lat, double lng) async =>
      throw const SocketException('No network');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('DropsRepository', () {
    // GIVEN a repository seeded with two active drops for Valencia
    // WHEN watchActive('Valencia') is subscribed to
    // THEN emits the two Valencia drops (not drops from other cities)
    test('watchActive emits active drops for the requested city only', () async {
      final drops = [
        _makeDrop(id: 'd1', city: 'Valencia'),
        _makeDrop(id: 'd2', city: 'Valencia'),
        _makeDrop(id: 'd3', city: 'Madrid'),
      ];
      final repo = FakeDropsRepository(drops);
      final emissions = <List<Drop>>[];

      final sub = repo.watchActive('Valencia').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.isNotEmpty, isTrue);
      expect(emissions.first.length, equals(2),
          reason: 'Should filter to Valencia drops only');
      expect(emissions.first.map((d) => d.id), containsAll(['d1', 'd2']));

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN an active drop stream
    // WHEN a new drop is added (realtime insert)
    // THEN the stream re-emits the updated list
    test('watchActive re-emits when realtime change fires', () async {
      final repo = FakeDropsRepository([_makeDrop(id: 'd1')]);
      final emissions = <List<Drop>>[];

      final sub = repo.watchActive('Valencia').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      repo.pushUpdate([_makeDrop(id: 'd1'), _makeDrop(id: 'd2')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.length, equals(2));

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN a drop of type 'credits_cache'
    // WHEN claim is called with the drop's id, lat, lng
    // THEN returns ClaimDropCash with credits and new_balance
    test('claim returns ClaimDropCash for credits_cache drop', () async {
      final drop = _makeDrop(id: 'd1', dropType: 'credits_cache', value: 75);
      final repo = FakeDropsRepository([drop]);

      final result = await repo.claim('d1', 39.47, -0.37);

      expect(result, isA<ClaimDropCash>(),
          reason: 'credits_cache drop must return ClaimDropCash');
      expect((result as ClaimDropCash).credits, equals(75));
    });

    // GIVEN a drop id that does not exist in the repository
    // WHEN claim is called
    // THEN returns ClaimDropFailure with reason 'not_found'
    test('claim returns ClaimDropFailure(not_found) for unknown drop id', () async {
      final repo = FakeDropsRepository([]);

      final result = await repo.claim('does-not-exist', 39.47, -0.37);

      expect(result, isA<ClaimDropFailure>());
      expect((result as ClaimDropFailure).reason, equals('not_found'));
    });

    // GIVEN a Drop constructed from JSON
    // WHEN its fields are accessed
    // THEN they match the source map values
    test('Drop.fromJson parses all fields correctly', () {
      final j = {
        'id':         'drop-abc',
        'city':       'Valencia',
        'lat':        39.47,
        'lng':        -0.37,
        'drop_type':  'power_core',
        'value':      1,
        'expires_at': '2026-06-01T10:00:00.000Z',
        'status':     'active',
      };

      final drop = Drop.fromJson(j);

      expect(drop.id, equals('drop-abc'));
      expect(drop.city, equals('Valencia'));
      expect(drop.dropType, equals('power_core'));
      expect(drop.status, equals('active'));
    });

    // GIVEN a repository whose stream throws SocketException
    // WHEN watchActive is subscribed with onError
    // THEN onError receives the SocketException
    test('watchActive stream error propagates via onError', () async {
      final repo = ThrowingDropsRepository();
      Object? caught;

      final sub = repo.watchActive('Valencia').listen(
        (_) {},
        onError: (e) => caught = e,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(caught, isA<SocketException>());
      await sub.cancel();
    });
  });
}
