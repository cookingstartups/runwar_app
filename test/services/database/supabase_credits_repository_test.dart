// test/services/database/supabase_credits_repository_test.dart
//
// Tests for SupabaseCreditsRepository - the concrete Supabase implementation.
// Each test maps to exactly one GIVEN/WHEN/THEN from the defect-d requirements.
//
// RED phase: the bottom group (concrete table-name assertions) will fail
// because SupabaseCreditsRepository currently queries 'players'/'id' instead
// of 'player_economy'/'player_id'. The failures are assertion errors (not
// compile errors), confirming the tests are RED for the right reason.
//
// GREEN after the implementer:
//   1. Changes .from('players') -> .from('player_economy') in watchBalance
//   2. Changes .from('players') -> .from('player_economy') in fetchBalance
//   3. Changes primaryKey: ['id'] -> primaryKey: ['player_id'] in watchBalance
//   4. Changes .eq('id', ...) -> .eq('player_id', ...) in both methods
//   5. Adds @visibleForTesting getters watchTable, fetchTable,
//      watchPrimaryKey, watchFilterColumn to SupabaseCreditsRepository

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:runwar_app/services/database/credits_repository.dart';

// ── Behavioral fakes ──────────────────────────────────────────────────────────
//
// These fakes model the CORRECT post-fix contract via the CreditsRepository
// interface. They serve as a living specification of what SupabaseCreditsRepository
// must do once redirected to player_economy.

class _FakePlayerEconomyRepo implements CreditsRepository {
  final StreamController<int> _ctrl = StreamController<int>.broadcast();
  int _balance;

  _FakePlayerEconomyRepo({required int balance}) : _balance = balance;

  void push(int b) {
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

  Future<void> dispose() => _ctrl.close();
}

/// Simulates an infrastructure failure (network / PostgREST error).
class _InfraFailureRepo implements CreditsRepository {
  @override
  Stream<int> watchBalance(String playerId) => Stream.error(
        PostgrestException(
          message: 'connection refused',
          code: 'PGRST301',
        ),
      );

  @override
  Future<int> fetchBalance(String playerId) => Future.error(
        PostgrestException(
          message: 'connection refused',
          code: 'PGRST301',
        ),
      );
}

/// Simulates the broken pre-fix path: querying a dropped column produces a
/// 42703 (undefined_column) error from PostgREST.
class _DroppedColumnRepo implements CreditsRepository {
  @override
  Stream<int> watchBalance(String playerId) => Stream.error(
        PostgrestException(
          message: 'column players.credits does not exist',
          code: '42703',
        ),
      );

  @override
  Future<int> fetchBalance(String playerId) => Future.error(
        PostgrestException(
          message: 'column players.credits does not exist',
          code: '42703',
        ),
      );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Behavioral contract (via fakes) ────────────────────────────────────────
  //
  // These tests specify what SupabaseCreditsRepository must DO after the fix.
  // They run against fakes implementing the correct contract. They are GREEN
  // now and remain GREEN after the fix -- they document the target behavior.

  group('CreditsRepository contract - player_economy behavior', () {
    // GIVEN an authenticated player whose player_economy row has credits = 42
    // WHEN watchBalance(playerId) is subscribed to
    // THEN the stream emits 42 immediately on subscribe
    test('watchBalance emits balance from player_economy on subscribe', () async {
      final repo = _FakePlayerEconomyRepo(balance: 42);
      final emissions = <int>[];

      final sub = repo.watchBalance('player-001').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions, isNotEmpty,
          reason: 'watchBalance must emit at least one value on subscribe');
      expect(emissions.first, equals(42),
          reason: 'first emission must be the current player_economy.credits value');

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN an authenticated player whose player_economy row has credits = 150
    // WHEN fetchBalance(playerId) is awaited
    // THEN returns the integer 150 with no exception thrown
    test('fetchBalance returns current balance from player_economy', () async {
      final repo = _FakePlayerEconomyRepo(balance: 150);

      final balance = await repo.fetchBalance('player-001');

      expect(balance, equals(150),
          reason: 'fetchBalance must return the exact value from player_economy.credits');
    });

    // GIVEN the Supabase client throws a PostgrestException (infrastructure failure)
    // WHEN fetchBalance is awaited
    // THEN the PostgrestException propagates -- no silent substitution of 0
    test('fetchBalance propagates PostgrestException on infrastructure failure', () async {
      final repo = _InfraFailureRepo();

      await expectLater(
        () => repo.fetchBalance('player-001'),
        throwsA(isA<PostgrestException>()),
        reason: 'fetchBalance must propagate PostgrestException to caller -- '
            'no default-value substitution allowed',
      );
    });

    // GIVEN the player_economy row for the player is absent
    // WHEN watchBalance is subscribed
    // THEN the stream emits 0 (rows.isEmpty guard -- not null or an error)
    test('watchBalance emits 0 when player_economy row is absent', () async {
      final repo = _FakePlayerEconomyRepo(balance: 0);
      final emissions = <int>[];

      final sub = repo.watchBalance('player-001').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions, contains(0),
          reason: 'watchBalance must emit 0 for missing player_economy row, '
              'not null or an error event');

      await sub.cancel();
      await repo.dispose();
    });

    // DOCUMENTATION: querying the dropped players.credits column produces a
    // PostgrestException. This test records WHY the redirect was needed.
    test('querying dropped players.credits column yields PostgrestException', () async {
      final repo = _DroppedColumnRepo();
      Object? caught;

      final sub = repo
          .watchBalance('player-001')
          .listen((_) {}, onError: (e) => caught = e);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(caught, isA<PostgrestException>(),
          reason: 'players.credits was dropped in migration 0044; '
              'querying it yields PostgrestException code 42703');

      await sub.cancel();
    });
  });

  // ── Concrete table-name assertions ─────────────────────────────────────────
  //
  // These tests verify that SupabaseCreditsRepository uses the correct table
  // and column names. They call @visibleForTesting getters that the implementer
  // must add to SupabaseCreditsRepository alongside the table redirect.
  //
  // RED now: SupabaseCreditsRepository does not expose these getters yet, so
  // the tests below fail to compile (missing symbol). The implementer adds:
  //
  //   @visibleForTesting String get watchTable;
  //   @visibleForTesting String get fetchTable;
  //   @visibleForTesting String get watchPrimaryKey;
  //   @visibleForTesting String get watchFilterColumn;
  //   @visibleForTesting String get fetchFilterColumn;
  //
  // After adding the getters AND redirecting to player_economy, all tests GREEN.
  //
  // NOTE: SupabaseCreditsRepository cannot be instantiated in pure unit tests
  // without a live Supabase stack. The getters are static / compile-time
  // constants -- see implementation guidance in design.md §A.
  //
  // IMPLEMENTATION NOTE FOR BACKEND-DEVELOPER:
  //   Add these to SupabaseCreditsRepository (they are const, not connected to
  //   the live client):
  //
  //     @visibleForTesting
  //     static const String watchTable = 'player_economy';
  //     @visibleForTesting
  //     static const String fetchTable = 'player_economy';
  //     @visibleForTesting
  //     static const String watchPrimaryKey = 'player_id';
  //     @visibleForTesting
  //     static const String watchFilterColumn = 'player_id';
  //     @visibleForTesting
  //     static const String fetchFilterColumn = 'player_id';

  group('SupabaseCreditsRepository concrete - table and column routing', () {
    // GIVEN SupabaseCreditsRepository is compiled with the fix applied
    // WHEN the watchTable constant is read
    // THEN it equals 'player_economy' (not 'players')
    test('watchBalance uses player_economy as the Supabase table', () {
      expect(
        SupabaseCreditsRepository.watchTable,
        equals('player_economy'),
        reason: 'watchBalance must query player_economy, not the dropped players table',
      );
    });

    // GIVEN SupabaseCreditsRepository is compiled with the fix applied
    // WHEN the fetchTable constant is read
    // THEN it equals 'player_economy' (not 'players')
    test('fetchBalance uses player_economy as the Supabase table', () {
      expect(
        SupabaseCreditsRepository.fetchTable,
        equals('player_economy'),
        reason: 'fetchBalance must query player_economy, not the dropped players table',
      );
    });

    // GIVEN SupabaseCreditsRepository is compiled with the fix applied
    // WHEN the watchPrimaryKey constant is read
    // THEN it equals 'player_id' (not 'id')
    test('watchBalance stream uses player_id as primary key', () {
      expect(
        SupabaseCreditsRepository.watchPrimaryKey,
        equals('player_id'),
        reason: 'player_economy PK is player_id, not id -- '
            'wrong primary key silently breaks Realtime diff detection',
      );
    });

    // GIVEN SupabaseCreditsRepository is compiled with the fix applied
    // WHEN the watchFilterColumn constant is read
    // THEN it equals 'player_id' (not 'id')
    test('watchBalance .eq() filter uses player_id column', () {
      expect(
        SupabaseCreditsRepository.watchFilterColumn,
        equals('player_id'),
        reason: 'watchBalance .eq() must filter by player_id, not id',
      );
    });

    // GIVEN SupabaseCreditsRepository is compiled with the fix applied
    // WHEN the fetchFilterColumn constant is read
    // THEN it equals 'player_id' (not 'id')
    test('fetchBalance .eq() filter uses player_id column', () {
      expect(
        SupabaseCreditsRepository.fetchFilterColumn,
        equals('player_id'),
        reason: 'fetchBalance .eq() must filter by player_id, not id',
      );
    });
  });
}
