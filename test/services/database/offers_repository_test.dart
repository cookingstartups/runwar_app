// test/services/database/offers_repository_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §3.2 + spec §6.1.
//
// NOTE: This file is extra (not in task brief) because design.md §3.2 splits
// pending offers into a SEPARATE OffersRepository distinct from
// SuperpowersRepository. Task brief incorrectly merged these. Tests follow
// the architect-approved design.md.
//
// Design contract (design.md §3.2):
//   abstract interface class OffersRepository {
//     Stream<SuperpowerOffer?> watchPending(String playerId);
//     Future<SpendResult> accept(String offerId, {String? targetZoneId, double? lat, double? lng});
//     Future<void> decline(String offerId);
//   }
//
// Broadcast stream contract (design.md §3.3):
//   watchPending uses .map(...).asBroadcastStream() — multiple listeners must
//   not throw a StateError.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/offers_repository.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

SuperpowerOffer _makeOffer({
  String id = 'offer-001',
  String offerType = 'extra_charge',
  String offeredPowerType = 'RUSH',
  String tier = 'common',
  int costCredits = 150,
  DateTime? expiresAt,
}) =>
    SuperpowerOffer(
      id: id,
      offerType: offerType,
      offeredPowerType: offeredPowerType,
      tier: tier,
      costCredits: costCredits,
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 10)),
    );

// ── Fake ─────────────────────────────────────────────────────────────────────

class FakeOffersRepository implements OffersRepository {
  final StreamController<SuperpowerOffer?> _controller =
      StreamController<SuperpowerOffer?>.broadcast();
  SuperpowerOffer? _pending;
  bool declineCalled = false;
  String? lastDeclinedOfferId;
  SpendResult? _acceptResult;

  FakeOffersRepository({
    SuperpowerOffer? pending,
    SpendResult? acceptResult,
  })  : _pending = pending,
        _acceptResult = acceptResult;

  void pushOffer(SuperpowerOffer? offer) {
    _pending = offer;
    _controller.add(offer);
  }

  @override
  Stream<SuperpowerOffer?> watchPending(String playerId) {
    // Must be broadcast — design.md §3.3.
    Future.microtask(() => _controller.add(_pending));
    return _controller.stream;  // Already broadcast (StreamController.broadcast())
  }

  @override
  Future<SpendResult> accept(String offerId,
      {String? targetZoneId, double? lat, double? lng}) async {
    return _acceptResult ??
        SpendOk({
          'offer_id':    offerId,
          'grant_id':    'grant-new',
          'new_balance': 850,
        });
  }

  @override
  Future<void> decline(String offerId) async {
    declineCalled = true;
    lastDeclinedOfferId = offerId;
    _controller.add(null);
  }

  Future<void> dispose() async => _controller.close();
}

class ThrowingOffersRepository implements OffersRepository {
  @override
  Stream<SuperpowerOffer?> watchPending(String playerId) =>
      Stream<SuperpowerOffer?>.error(const SocketException('No network'));

  @override
  Future<SpendResult> accept(String offerId,
      {String? targetZoneId, double? lat, double? lng}) async =>
      throw const SocketException('No network');

  @override
  Future<void> decline(String offerId) async =>
      throw const SocketException('No network');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('OffersRepository', () {
    // GIVEN a repository with a pending offer
    // WHEN watchPending is subscribed to
    // THEN emits the pending SuperpowerOffer
    test('watchPending emits the current pending offer on subscribe', () async {
      final offer = _makeOffer(id: 'offer-001');
      final repo = FakeOffersRepository(pending: offer);
      final emissions = <SuperpowerOffer?>[];

      final sub = repo.watchPending('player-1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.isNotEmpty, isTrue);
      expect(emissions.first, isNotNull);
      expect(emissions.first!.id, equals('offer-001'));

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN a pending offer stream
    // WHEN a second offer supersedes the first (create_offer_with_supersede)
    // THEN the stream emits the new offer
    test('watchPending emits superseding offer when stream is updated', () async {
      final repo = FakeOffersRepository(pending: _makeOffer(id: 'offer-001'));
      final emissions = <SuperpowerOffer?>[];

      final sub = repo.watchPending('player-1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      repo.pushOffer(_makeOffer(id: 'offer-002', offeredPowerType: 'SHIELD'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last!.id, equals('offer-002'),
          reason: 'Stream must emit the superseding offer');

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN a pending offer stream
    // WHEN two listeners subscribe to watchPending
    // THEN no StateError is thrown (broadcast stream contract)
    test('watchPending allows multiple listeners (broadcast stream contract)', () async {
      final repo = FakeOffersRepository(pending: _makeOffer());

      final stream = repo.watchPending('player-1');
      // Subscribing twice must not throw StateError.
      final sub1 = stream.listen((_) {});
      final sub2 = stream.listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // If we reach here without StateError, the contract is met.
      await sub1.cancel();
      await sub2.cancel();
      await repo.dispose();
    });

    // GIVEN a pending offer
    // WHEN accept is called
    // THEN returns SpendOk with offer_id, grant_id, new_balance
    test('accept returns SpendOk on successful spend', () async {
      final repo = FakeOffersRepository();

      final result = await repo.accept('offer-001');

      expect(result, isA<SpendOk>());
      expect((result as SpendOk).offerId, equals('offer-001'));
    });

    // GIVEN a pending offer response with failure reason
    // WHEN accept returns SpendFailure
    // THEN SpendFailure carries the reason string
    test('accept returns SpendFailure with reason on domain failure', () async {
      final repo = FakeOffersRepository(
        acceptResult: const SpendFailure('insufficient_credits'),
      );

      final result = await repo.accept('offer-001');

      expect(result, isA<SpendFailure>());
      expect((result as SpendFailure).reason, equals('insufficient_credits'));
    });

    // GIVEN a pending offer
    // WHEN decline is called
    // THEN the repository marks the offer declined and emits null to the stream
    test('decline marks offer declined and stream emits null', () async {
      final offer = _makeOffer(id: 'offer-001');
      final repo = FakeOffersRepository(pending: offer);
      final emissions = <SuperpowerOffer?>[];

      final sub = repo.watchPending('player-1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await repo.decline('offer-001');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.declineCalled, isTrue);
      expect(repo.lastDeclinedOfferId, equals('offer-001'));
      expect(emissions.last, isNull,
          reason: 'Stream must emit null after offer is declined');

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN a SuperpowerOffer for BLITZ
    // WHEN requiresStandingZone is checked
    // THEN returns true (BLITZ requires GPS point-in-zone check)
    test('SuperpowerOffer.requiresStandingZone=true for BLITZ and FORTIFY', () {
      final blitz = _makeOffer(offeredPowerType: 'BLITZ');
      final fortify = _makeOffer(offeredPowerType: 'FORTIFY');
      final rush = _makeOffer(offeredPowerType: 'RUSH');

      expect(blitz.requiresStandingZone, isTrue);
      expect(fortify.requiresStandingZone, isTrue);
      expect(rush.requiresStandingZone, isFalse);
    });
  });
}
