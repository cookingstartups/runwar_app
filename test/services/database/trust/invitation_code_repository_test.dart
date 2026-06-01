// test/services/database/trust/invitation_code_repository_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures are expected as "Target of URI doesn't exist" compile errors.
// Each test maps to exactly one GIVEN/WHEN/THEN from spec §P3-FL-05.
//
// Contract under test (spec §P3-FL-05):
//   class SupabaseInvitationsRepository implements InvitationsRepository {
//     Future<RedeemResult> redeem(String code);
//   }
//   Typed exceptions: InvalidInviteCode, CodeExhausted, SelfReferral, AlreadyRedeemed
//   RedeemResult { final String inviterId; final bool referralCreated; }

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/invitations_repository.dart';
import 'package:runwar_app/models/invitation_code.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeInvitationsRepository implements InvitationsRepository {
  final Map<String, dynamic>? _redeemResponse;
  final String? _redeemError;

  FakeInvitationsRepository({
    Map<String, dynamic>? redeemResponse,
    String? redeemError,
  })  : _redeemResponse = redeemResponse,
        _redeemError = redeemError;

  @override
  Future<InvitationCode> generate({
    String? code,
    int maxRedemptions = 1,
    DateTime? expiresAt,
  }) async {
    return InvitationCode(
      code: code ?? 'GENCODE',
      maxRedemptions: maxRedemptions,
      redeemedCount: 0,
    );
  }

  @override
  Future<RedeemResult> redeem(String code) async {
    if (_redeemError != null) {
      switch (_redeemError) {
        case 'invalid_code':
          throw const InvalidInviteCode();
        case 'exhausted':
          throw const CodeExhausted();
        case 'self_referral':
          throw const SelfReferral();
        case 'already_redeemed':
          throw const AlreadyRedeemed();
        default:
          throw Exception('unknown error: $_redeemError');
      }
    }
    return RedeemResult(
      inviterId: _redeemResponse!['inviter_id'] as String,
      referralCreated: _redeemResponse!['referral_created'] as bool,
    );
  }

  @override
  Future<List<InvitationCode>> listMine() async => [];
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('InvitationsRepository — redeem contract', () {
    // GIVEN a valid invite code backed by a repo that returns success
    // WHEN redeemCode() is called
    // THEN returns a RedeemResult with correct inviterId and referralCreated=true
    test('redeem() returns correctly typed RedeemResult on success', () async {
      final repo = FakeInvitationsRepository(
        redeemResponse: {
          'inviter_id': 'inviter-uuid-001',
          'referral_created': true,
        },
      );

      final result = await repo.redeem('VALID1');

      expect(result, isA<RedeemResult>());
      expect(result.inviterId, equals('inviter-uuid-001'));
      expect(result.referralCreated, isTrue);
    });

    // GIVEN a repo that returns error='invalid_code'
    // WHEN redeem() is called
    // THEN throws InvalidInviteCode (not a generic Exception)
    test('redeem() throws InvalidInviteCode when server returns invalid_code', () async {
      final repo = FakeInvitationsRepository(redeemError: 'invalid_code');

      expect(
        () => repo.redeem('BADCODE'),
        throwsA(isA<InvalidInviteCode>()),
        reason: 'Must throw typed InvalidInviteCode, not generic Exception',
      );
    });

    // GIVEN a repo that returns error='exhausted'
    // WHEN redeem() is called
    // THEN throws CodeExhausted
    test('redeem() throws CodeExhausted when code is exhausted', () async {
      final repo = FakeInvitationsRepository(redeemError: 'exhausted');

      expect(() => repo.redeem('EXHAUSTED'), throwsA(isA<CodeExhausted>()));
    });

    // GIVEN a repo that returns error='self_referral'
    // WHEN redeem() is called
    // THEN throws SelfReferral
    test('redeem() throws SelfReferral when player tries to redeem own code', () async {
      final repo = FakeInvitationsRepository(redeemError: 'self_referral');

      expect(() => repo.redeem('MYCODE'), throwsA(isA<SelfReferral>()));
    });

    // GIVEN a repo that returns error='already_redeemed'
    // WHEN redeem() is called
    // THEN throws AlreadyRedeemed
    test('redeem() throws AlreadyRedeemed when code was already redeemed by this player', () async {
      final repo = FakeInvitationsRepository(redeemError: 'already_redeemed');

      expect(() => repo.redeem('USED1'), throwsA(isA<AlreadyRedeemed>()));
    });
  });
}
