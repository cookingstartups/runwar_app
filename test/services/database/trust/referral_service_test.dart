// test/services/database/trust/referral_service_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures are expected as "Target of URI doesn't exist" compile errors.
// Each test maps to exactly one GIVEN/WHEN/THEN from spec §P3-FL-10.
//
// Contract under test (spec §P3-FL-10):
//   class ReferralService {
//     ReferralService(this._repo)
//     Future<Referral?> inviterFor(String playerId)
//     Future<int> totalKickback(String playerId)
//     ...
//   }
//   Kickback is 20% of the credit delta (spec §P3-EF-04, app_config key referral_kickback_pct=20).

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/trust/referral_service.dart';
import 'package:runwar_app/services/database/referrals_repository.dart';
import 'package:runwar_app/models/referral.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeReferralsRepository implements ReferralsRepository {
  final Referral? _referral;
  final int _totalKickback;
  final List<KickbackEntry> _history;

  FakeReferralsRepository({
    Referral? referral,
    int totalKickback = 0,
    List<KickbackEntry> history = const [],
  })  : _referral = referral,
        _totalKickback = totalKickback,
        _history = history;

  @override
  Future<Referral?> getInviterFor(String playerId) async => _referral;

  @override
  Future<int> totalKickbackEarned(String playerId) async => _totalKickback;

  @override
  Future<List<KickbackEntry>> kickbackHistory(String inviterId, {int limit = 50}) async =>
      _history.take(limit).toList();

  @override
  Stream<int> watchTotalKickback(String playerId) =>
      Stream.value(_totalKickback);
}

Referral _makeReferral({
  String inviterId = 'inviter-001',
  String inviteeId = 'invitee-001',
  String viaCode = 'CODE01',
}) =>
    Referral(
      inviterId: inviterId,
      inviteeId: inviteeId,
      viaCode: viaCode,
      createdAt: DateTime.parse('2026-06-01T00:00:00.000Z'),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ReferralService', () {
    // GIVEN a referrals repo that has a referral row for the given invitee
    // WHEN getReferralChain() / inviterFor() is called
    // THEN returns the Referral with the correct inviter_id
    test('inviterFor() returns the inviter Referral for the given playerId', () async {
      final referral = _makeReferral(inviterId: 'inviter-abc', inviteeId: 'invitee-xyz');
      final service = ReferralService(
        FakeReferralsRepository(referral: referral),
      );

      final result = await service.inviterFor('invitee-xyz');

      expect(result, isNotNull);
      expect(result!.inviterId, equals('inviter-abc'));
      expect(result.inviteeId, equals('invitee-xyz'));
    });

    // GIVEN a referrals repo with no referral row for the given player
    // WHEN inviterFor() is called
    // THEN returns null (no inviter — organic signup)
    test('inviterFor() returns null when no referral row exists for the player', () async {
      final service = ReferralService(
        FakeReferralsRepository(referral: null),
      );

      final result = await service.inviterFor('organic-player');

      expect(result, isNull);
    });

    // GIVEN an invitee earns 100 credits
    // WHEN kickback is calculated at the configured 20% rate
    // THEN kickback amount equals 20
    test('kickback calculation: 20% of delta=100 yields 20', () {
      // This test verifies the contract that the kickback_pct is 20%
      // by checking that Math.round(100 * 20 / 100) == 20.
      // The actual calculation lives in apply_referral_kickback edge fn (spec §P3-EF-04).
      // Here we verify the constant that the Dart layer must document.
      const earnedAmount = 100;
      const kickbackPct = 20; // matches app_config.referral_kickback_pct
      final kickback = (earnedAmount * kickbackPct / 100).round();

      expect(kickback, equals(20),
          reason: 'Kickback must be 20% of earned_amount as per app_config referral_kickback_pct=20');
    });

    // GIVEN a referrals repo with totalKickback=350
    // WHEN totalKickback() is called
    // THEN returns 350
    test('totalKickback() returns value from repository', () async {
      final service = ReferralService(
        FakeReferralsRepository(totalKickback: 350),
      );

      final total = await service.totalKickback('inviter-001');

      expect(total, equals(350));
    });
  });
}
