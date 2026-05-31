// test/services/database/superpowers_repository_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §3.2 + spec §6.1.
//
// METHOD CONFLICT NOTE (surfaced for SquadLead):
// Task brief requested `fetchGrantsForPlayer` and `fetchPendingOffer` on
// SuperpowersRepository. design.md §3.2 defines the authoritative interface as:
//   watchActiveGrants(playerId) — Stream<List<SuperpowerGrant>>
//   reportEvent(EarnEvent)     — Future<EarnResult>
// Pending offers belong to the separate OffersRepository (see offers_repository_test.dart).
// Tests are written against the architect-approved design.md interface.
//
// Design contract (design.md §3.2):
//   abstract interface class SuperpowersRepository {
//     Stream<List<SuperpowerGrant>> watchActiveGrants(String playerId);
//     Future<EarnResult> reportEvent(EarnEvent event);
//   }

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/superpowers_repository.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

SuperpowerGrant _makeGrant({
  String id = 'grant-001',
  String playerId = 'player-1',
  String powerType = 'RUSH',
  int charges = 1,
  int chargesUsed = 0,
  String source = 'run_end',
  DateTime? expiresAt,
  DateTime? consumedAt,
}) =>
    SuperpowerGrant(
      id: id,
      playerId: playerId,
      powerType: powerType,
      charges: charges,
      chargesUsed: chargesUsed,
      source: source,
      expiresAt: expiresAt,
      consumedAt: consumedAt,
    );

// ── Fake ─────────────────────────────────────────────────────────────────────

class FakeSuperpowersRepository implements SuperpowersRepository {
  final StreamController<List<SuperpowerGrant>> _controller =
      StreamController<List<SuperpowerGrant>>.broadcast();
  List<SuperpowerGrant> _grants;
  EarnResult? _nextReportResult;

  FakeSuperpowersRepository(this._grants,
      {EarnResult? reportResult})
      : _nextReportResult = reportResult;

  void pushUpdate(List<SuperpowerGrant> grants) {
    _grants = grants;
    _controller.add(grants);
  }

  @override
  Stream<List<SuperpowerGrant>> watchActiveGrants(String playerId) {
    Future.microtask(() {
      _controller.add(_grants.where((g) => g.playerId == playerId).toList());
    });
    return _controller.stream;
  }

  @override
  Future<EarnResult> reportEvent(EarnEvent event) async {
    return _nextReportResult ??
        EarnResult(granted: false, reason: 'no_match');
  }

  Future<void> dispose() async => _controller.close();
}

class ThrowingSuperpowersRepository implements SuperpowersRepository {
  @override
  Stream<List<SuperpowerGrant>> watchActiveGrants(String playerId) =>
      Stream.error(const SocketException('No network'));

  @override
  Future<EarnResult> reportEvent(EarnEvent event) async =>
      throw const SocketException('No network');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SuperpowersRepository', () {
    // GIVEN a repository with one active RUSH grant for player-1
    // WHEN watchActiveGrants('player-1') is subscribed to
    // THEN emits a list containing the RUSH grant
    test('watchActiveGrants emits active grants for the requested player', () async {
      final repo = FakeSuperpowersRepository([
        _makeGrant(id: 'g1', playerId: 'player-1', powerType: 'RUSH'),
        _makeGrant(id: 'g2', playerId: 'player-2', powerType: 'SHIELD'),
      ]);
      final emissions = <List<SuperpowerGrant>>[];

      final sub = repo.watchActiveGrants('player-1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.isNotEmpty, isTrue);
      expect(emissions.first.length, equals(1));
      expect(emissions.first.first.powerType, equals('RUSH'));

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN an active grants stream
    // WHEN a new grant is pushed (realtime insert from DB)
    // THEN the stream re-emits the updated list
    test('watchActiveGrants re-emits when realtime change fires', () async {
      final repo = FakeSuperpowersRepository([
        _makeGrant(id: 'g1', powerType: 'RUSH'),
      ]);
      final emissions = <List<SuperpowerGrant>>[];

      final sub = repo.watchActiveGrants('player-1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      repo.pushUpdate([
        _makeGrant(id: 'g1', powerType: 'RUSH'),
        _makeGrant(id: 'g2', powerType: 'GHOST_RUN'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.length, equals(2));

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN a repo configured to return EarnResult with granted=true
    // WHEN reportEvent is called with a run_end EarnEvent
    // THEN returns the EarnResult with granted=true
    test('reportEvent returns EarnResult from the edge function response', () async {
      final expected = EarnResult(
        granted: true,
        powerType: 'RUSH',
        grantId: 'grant-abc',
        tier: 'common',
        charges: 1,
      );
      final repo = FakeSuperpowersRepository([], reportResult: expected);

      final result = await repo.reportEvent(EarnEvent.runEnd('run-xyz'));

      expect(result.granted, isTrue);
      expect(result.powerType, equals('RUSH'));
    });

    // GIVEN a SuperpowerGrant with 1 charge and 0 chargesUsed
    // WHEN chargesRemaining and isActive are checked
    // THEN chargesRemaining=1 and isActive=true
    test('SuperpowerGrant.chargesRemaining and isActive derived correctly', () {
      final grant = _makeGrant(charges: 1, chargesUsed: 0);

      expect(grant.chargesRemaining, equals(1));
      expect(grant.isActive, isTrue);
    });

    // GIVEN a SuperpowerGrant with all charges used
    // WHEN isActive is checked
    // THEN isActive=false
    test('SuperpowerGrant.isActive=false when all charges used', () {
      final grant = _makeGrant(charges: 2, chargesUsed: 2);

      expect(grant.chargesRemaining, equals(0));
      expect(grant.isActive, isFalse,
          reason: 'Grant with no remaining charges must not be active');
    });

    // GIVEN a SuperpowerGrant.fromJson with all fields populated
    // WHEN fields are accessed
    // THEN they match the source map
    test('SuperpowerGrant.fromJson parses all fields correctly', () {
      final j = {
        'id':           'grant-xyz',
        'player_id':    'player-abc',
        'power_type':   'SHIELD',
        'charges':      3,
        'charges_used': 1,
        'source':       'defence',
        'expires_at':   '2026-06-01T12:00:00.000Z',
        'consumed_at':  null,
      };

      final grant = SuperpowerGrant.fromJson(j);

      expect(grant.id, equals('grant-xyz'));
      expect(grant.powerType, equals('SHIELD'));
      expect(grant.chargesRemaining, equals(2));
      expect(grant.consumedAt, isNull);
    });

    // GIVEN a repository whose stream throws SocketException
    // WHEN watchActiveGrants is subscribed with onError
    // THEN onError receives the SocketException
    test('watchActiveGrants stream error propagates via onError', () async {
      final repo = ThrowingSuperpowersRepository();
      Object? caught;

      final sub = repo.watchActiveGrants('player-1').listen(
        (_) {},
        onError: (e) => caught = e,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(caught, isA<SocketException>());
      await sub.cancel();
    });
  });
}
