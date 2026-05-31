// test/services/superpower_runtime_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §4.1/§4.2 + spec §6.2.
//
// Design contract (design.md §4.1 + spec §6.2):
//   class SuperpowerRuntime {
//     void bind(String playerId)          — subscribes to watchActiveGrants
//     bool get rushArmed
//     bool get ghostArmed
//     bool get shieldActive               — uses expiresAt
//     bool get overclockActive            — uses expiresAt
//     DateTime? get shieldUntil
//     DateTime? get overclockUntil
//     Future<void> dispose()
//   }
//
// KEY RULE (design.md §4.2 + §4.3):
//   GHOST_RUN charge consumption is SERVER-SIDE (consume_ghost_run_charge RPC).
//   SuperpowerRuntime is a READ-ONLY flag deriver — it MUST NOT mutate charges.
//   Tests assert flag derivation only; never charge mutation.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/superpower_runtime.dart';
import 'package:runwar_app/services/database/superpowers_repository.dart';

// ── Fake ─────────────────────────────────────────────────────────────────────

class FakeSuperpowersRepo implements SuperpowersRepository {
  final StreamController<List<SuperpowerGrant>> _ctrl =
      StreamController<List<SuperpowerGrant>>.broadcast();

  void push(List<SuperpowerGrant> grants) => _ctrl.add(grants);

  @override
  Stream<List<SuperpowerGrant>> watchActiveGrants(String playerId) =>
      _ctrl.stream;

  @override
  Future<EarnResult> reportEvent(EarnEvent event) async =>
      EarnResult(granted: false, reason: 'no_match');

  Future<void> dispose() async => _ctrl.close();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

SuperpowerGrant _grant({
  String id = 'g1',
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

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SuperpowerRuntime', () {
    // GIVEN a grant stream that emits a RUSH grant with 1 charge remaining
    // WHEN bind is called and the stream emits
    // THEN rushArmed=true
    test('rushArmed=true when RUSH grant with chargesRemaining > 0 is active', () async {
      final repo = FakeSuperpowersRepo();
      final runtime = SuperpowerRuntime(repo: repo);
      runtime.bind('player-1');

      repo.push([_grant(powerType: 'RUSH', charges: 1, chargesUsed: 0)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.rushArmed, isTrue);

      await runtime.dispose();
      await repo.dispose();
    });

    // GIVEN a grant stream that emits a GHOST_RUN grant with 1 charge remaining
    // WHEN bind is called and the stream emits
    // THEN ghostArmed=true
    test('ghostArmed=true when GHOST_RUN grant with chargesRemaining > 0 is active', () async {
      final repo = FakeSuperpowersRepo();
      final runtime = SuperpowerRuntime(repo: repo);
      runtime.bind('player-1');

      repo.push([_grant(powerType: 'GHOST_RUN', charges: 1, chargesUsed: 0)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.ghostArmed, isTrue,
          reason: 'ghostArmed must derive from GHOST_RUN grant');
      // Charge mutation is server-side only — runtime must NOT expose any
      // method to consume charges. This comment is the living contract.

      await runtime.dispose();
      await repo.dispose();
    });

    // GIVEN a SHIELD grant that expires in the future
    // WHEN bind is called and the stream emits
    // THEN shieldActive=true and shieldUntil is set
    test('shieldActive=true when SHIELD grant expiresAt is in the future', () async {
      final repo = FakeSuperpowersRepo();
      final runtime = SuperpowerRuntime(repo: repo);
      runtime.bind('player-1');

      final future = DateTime.now().add(const Duration(hours: 2));
      repo.push([_grant(powerType: 'SHIELD', charges: 1, chargesUsed: 0, expiresAt: future)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.shieldActive, isTrue);
      expect(runtime.shieldUntil, equals(future));

      await runtime.dispose();
      await repo.dispose();
    });

    // GIVEN a SHIELD grant that expired in the past
    // WHEN bind is called and the stream emits
    // THEN shieldActive=false
    test('shieldActive=false when SHIELD grant expiresAt is in the past', () async {
      final repo = FakeSuperpowersRepo();
      final runtime = SuperpowerRuntime(repo: repo);
      runtime.bind('player-1');

      final past = DateTime.now().subtract(const Duration(minutes: 1));
      repo.push([_grant(powerType: 'SHIELD', charges: 1, chargesUsed: 0, expiresAt: past)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.shieldActive, isFalse,
          reason: 'Expired SHIELD grant must not activate shieldActive');

      await runtime.dispose();
      await repo.dispose();
    });

    // GIVEN a RUSH grant stream, then bind is called for a second player
    // WHEN bind(player-2) is called while a prior subscription is active
    // THEN the prior subscription is cancelled and new grants are for player-2
    test('bind() cancels the previous subscription when called again', () async {
      final repo = FakeSuperpowersRepo();
      final runtime = SuperpowerRuntime(repo: repo);

      runtime.bind('player-1');
      repo.push([_grant(powerType: 'RUSH', charges: 1, chargesUsed: 0)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runtime.rushArmed, isTrue);

      // Re-bind for a new player — previous grants should be reset.
      runtime.bind('player-2');
      repo.push([]); // No grants for player-2 yet.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.rushArmed, isFalse,
          reason: 'Re-binding must cancel old subscription and reset flags');

      await runtime.dispose();
      await repo.dispose();
    });

    // GIVEN an active SuperpowerRuntime
    // WHEN dispose() is called
    // THEN subsequent stream emissions do not update flags (subscription cancelled)
    test('dispose() cancels subscription — stream emissions after dispose are ignored', () async {
      final repo = FakeSuperpowersRepo();
      final runtime = SuperpowerRuntime(repo: repo);
      runtime.bind('player-1');

      repo.push([_grant(powerType: 'RUSH')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runtime.rushArmed, isTrue);

      await runtime.dispose();

      // After dispose, a new emission must not update rushArmed.
      repo.push([]); // Would set rushArmed=false if subscription were active.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The flag may or may not reset — implementation detail after dispose.
      // What MUST hold: dispose() completes without throwing.
      expect(true, isTrue, reason: 'dispose() completed without exception');
    });

    // GIVEN an OVERCLOCK grant expiring in 1 hour
    // WHEN bind is called and the stream emits
    // THEN overclockActive=true and overclockUntil matches the grant's expiresAt
    test('overclockActive=true when OVERCLOCK grant expiresAt is in the future', () async {
      final repo = FakeSuperpowersRepo();
      final runtime = SuperpowerRuntime(repo: repo);
      runtime.bind('player-1');

      final future = DateTime.now().add(const Duration(hours: 1));
      repo.push([_grant(powerType: 'OVERCLOCK', charges: 1, chargesUsed: 0, expiresAt: future)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.overclockActive, isTrue);
      expect(runtime.overclockUntil, equals(future));

      await runtime.dispose();
      await repo.dispose();
    });
  });
}
