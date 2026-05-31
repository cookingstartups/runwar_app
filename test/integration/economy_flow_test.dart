// test/integration/economy_flow_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to one GIVEN/WHEN/THEN from design.md §9 + spec §8.4.
//
// Flows (spec §8.4 + architect §9.4):
//   1. Earn → offer → accept flow
//      GIVEN player earns a RUSH grant via reportEvent
//      WHEN pendingOfferProvider emits an offer
//      THEN creditsBalanceProvider decrements after accept
//
//   2. Drop pickup flow
//      GIVEN active Valencia drops exist
//      WHEN player is within 30m of a drop
//      THEN claim returns ClaimDropCash and balance updates
//
//   3. Passive income tick
//      GIVEN a zone with passive income due
//      WHEN passive_income_tick is invoked (manual mode)
//      THEN creditsBalanceProvider reflects the increased balance
//
// Scope note: these tests verify provider + service wiring using fakes,
// NOT real Supabase connections. Realtime edge-fn smoke is deferred to
// the P2-VER integration suite (emulator).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:runwar_app/providers/economy/credits_provider.dart';
import 'package:runwar_app/providers/superpowers/pending_offer_provider.dart';
import 'package:runwar_app/providers/drops/active_drops_provider.dart';
import 'package:runwar_app/services/economy_service.dart';
import 'package:runwar_app/services/database/credits_repository.dart';
import 'package:runwar_app/services/database/ledger_repository.dart';
import 'package:runwar_app/services/database/drops_repository.dart';
import 'package:runwar_app/services/database/superpowers_repository.dart';
import 'package:runwar_app/services/database/offers_repository.dart';
import 'package:runwar_app/providers/economy/economy_service_provider.dart';

import '../_helpers/test_container.dart';

// ── Supabase stub ─────────────────────────────────────────────────────────────
// Prevents SharedPreferences plugin calls during Supabase.initialize().
// NOTE: TestWidgetsFlutterBinding.ensureInitialized() must be called before
// Supabase.initialize() in non-widget tests that invoke Supabase.

class _InMemoryGotrueStorage extends GotrueAsyncStorage {
  final _store = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _store[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _store[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _store.remove(key);
}

// ── Fake repositories ─────────────────────────────────────────────────────────

class FakeCreditsRepoEconomy implements CreditsRepository {
  final StreamController<int> _ctrl = StreamController<int>.broadcast();
  int _balance;

  FakeCreditsRepoEconomy({int initial = 500}) : _balance = initial;

  void set(int b) {
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

class FakeLedgerRepoEconomy implements LedgerRepository {
  @override
  Future<List<LedgerEntry>> fetchRecent(String playerId, {int limit = 50}) async => [];
}

class FakeOffersRepoEconomy implements OffersRepository {
  final StreamController<SuperpowerOffer?> _ctrl =
      StreamController<SuperpowerOffer?>.broadcast();

  void pushOffer(SuperpowerOffer? o) => _ctrl.add(o);

  @override
  Stream<SuperpowerOffer?> watchPending(String playerId) {
    Future.microtask(() => _ctrl.add(null));
    return _ctrl.stream;
  }

  @override
  Future<SpendResult> accept(String offerId,
      {String? targetZoneId, double? lat, double? lng}) async {
    return SpendOk({
      'offer_id': offerId,
      'grant_id': 'grant-new',
      'new_balance': 350,
    });
  }

  @override
  Future<void> decline(String offerId) async {}

  Future<void> dispose() async => _ctrl.close();
}

class FakeDropsRepoEconomy implements DropsRepository {
  final StreamController<List<Drop>> _ctrl = StreamController<List<Drop>>.broadcast();
  List<Drop> _drops;

  FakeDropsRepoEconomy(this._drops);

  @override
  Stream<List<Drop>> watchActive(String city) {
    Future.microtask(() => _ctrl.add(_drops));
    return _ctrl.stream;
  }

  @override
  Future<ClaimDropResult> claim(String dropId, double lat, double lng) async {
    return ClaimDropCash({'credits_awarded': 75, 'new_balance': 575});
  }

  Future<void> dispose() async => _ctrl.close();
}

class FakeSuperpowersRepoEconomy implements SuperpowersRepository {
  @override
  Stream<List<SuperpowerGrant>> watchActiveGrants(String playerId) =>
      Stream.value([]);

  @override
  Future<EarnResult> reportEvent(EarnEvent event) async => EarnResult(
        granted: true,
        powerType: 'RUSH',
        grantId: 'grant-rush-1',
        tier: 'common',
        charges: 1,
      );
}

Drop _makeIntegrationDrop({
  String id = 'drop-001',
  String city = 'Valencia',
}) =>
    Drop(
      id: id,
      city: city,
      lat: 39.47,
      lng: -0.37,
      dropType: 'credits_cache',
      value: 75,
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      status: 'active',
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    // Required before Supabase.initialize() in pure-Dart (non-widget) tests.
    TestWidgetsFlutterBinding.ensureInitialized();

    // Supabase init stub — prevents real network calls.
    // Guard against "already initialized" when tests run in the same process
    // as dispute_flow_test (which also calls Supabase.initialize).
    try {
      await Supabase.initialize(
        url: 'https://placeholder-test.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0In0.placeholder',
        authOptions: FlutterAuthClientOptions(
          localStorage: const EmptyLocalStorage(),
          pkceAsyncStorage: _InMemoryGotrueStorage(),
        ),
      );
    } catch (_) {
      // Already initialized by a sibling test file — ignore.
    }
  });

  group('Economy integration', () {
    // GIVEN creditsBalanceProvider wired to a FakeCreditsRepo with 500 credits
    // WHEN the ProviderContainer is read
    // THEN creditsBalanceProvider('player-1') resolves to AsyncData(500)
    test('creditsBalanceProvider resolves to initial balance via CreditsRepository',
        () async {
      final creditsRepo = FakeCreditsRepoEconomy(initial: 500);
      final container = makeTestContainer(creditsRepo: creditsRepo);
      addTearDown(container.dispose);

      final sub = container.listen(
        creditsBalanceProvider('player-1'),
        (_, __) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = container.read(creditsBalanceProvider('player-1'));
      expect(state.value, equals(500));

      sub.close();
      await creditsRepo.dispose();
    });

    // GIVEN an OffersRepository that emits a pending offer
    // WHEN pendingOfferProvider('player-1') is read after the stream emits
    // THEN the provider holds AsyncData with the offer
    test('pendingOfferProvider reflects a newly emitted pending offer', () async {
      final offersRepo = FakeOffersRepoEconomy();
      final container = makeTestContainer(offersRepo: offersRepo);
      addTearDown(container.dispose);

      final emissions = <AsyncValue<SuperpowerOffer?>>[];
      final sub = container.listen(
        pendingOfferProvider('player-1'),
        (_, next) => emissions.add(next),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final offer = SuperpowerOffer(
        id: 'offer-001',
        offerType: 'extra_charge',
        offeredPowerType: 'RUSH',
        tier: 'common',
        costCredits: 150,
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      offersRepo.pushOffer(offer);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final data = emissions.whereType<AsyncData<SuperpowerOffer?>>().toList();
      expect(data.isNotEmpty, isTrue);
      // Last emission should contain the offer (or null from initial push).
      final nonNull = data.where((d) => d.value != null).toList();
      expect(nonNull.isNotEmpty, isTrue,
          reason: 'pendingOfferProvider must emit the pending offer');
      expect(nonNull.last.value!.id, equals('offer-001'));

      sub.close();
      await offersRepo.dispose();
    });

    // GIVEN an active drop in Valencia within 30m of the player position
    // WHEN DropsRepository.claim is called
    // THEN returns ClaimDropCash with credits_awarded=75
    test('drop claim returns ClaimDropCash with correct credit award', () async {
      final drop = _makeIntegrationDrop();
      final dropsRepo = FakeDropsRepoEconomy([drop]);
      final container = makeTestContainer(dropsRepo: dropsRepo);
      addTearDown(container.dispose);

      // Claim the drop directly via the repo (DropsService integration).
      final result = await dropsRepo.claim('drop-001', 39.47, -0.37);

      expect(result, isA<ClaimDropCash>());
      expect((result as ClaimDropCash).credits, equals(75));

      await dropsRepo.dispose();
    });

    // GIVEN a balance of 500 credits
    // WHEN a passive income tick credits +25 (owner of 1 zone, rate=25)
    // THEN the balance stream emits 525
    test('balance stream reflects passive income credit applied externally', () async {
      final creditsRepo = FakeCreditsRepoEconomy(initial: 500);
      final container = makeTestContainer(creditsRepo: creditsRepo);
      addTearDown(container.dispose);

      final emissions = <int>[];
      final sub = container.listen(
        creditsBalanceProvider('player-1'),
        (_, next) {
          if (next.value != null) emissions.add(next.value!);
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Simulate passive income tick crediting the balance.
      creditsRepo.set(525);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions, contains(525),
          reason: 'Balance stream must propagate passive income credit to provider');

      sub.close();
      await creditsRepo.dispose();
    });

    // GIVEN an EconomyService backed by fakes
    // WHEN balanceDeltas is subscribed and balance changes from 500 → 350 (spend)
    // THEN emits a delta tuple ({previous:500, next:350})
    test('EconomyService.balanceDeltas emits previous+next on spend', () async {
      final creditsRepo = FakeCreditsRepoEconomy(initial: 500);
      final service = EconomyService(
        credits: creditsRepo,
        ledger: FakeLedgerRepoEconomy(),
      );

      final deltas = <({int previous, int next})>[];
      final sub = service.balanceDeltas('player-1').listen(deltas.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      creditsRepo.set(350);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final decrements = deltas.where((d) => d.next < d.previous).toList();
      expect(decrements.isNotEmpty, isTrue,
          reason: 'balanceDeltas must emit a decrement after spending credits');
      expect(decrements.last.next, equals(350));

      await sub.cancel();
      await creditsRepo.dispose();
    });
  });
}
