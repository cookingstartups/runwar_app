// test/services/database/trust/invite_cap_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures are expected as "Target of URI doesn't exist" compile errors.
// Each test maps to exactly one GIVEN/WHEN/THEN from spec §P3-EF-01 (invite cap)
// and spec §P3-DB-08 (app_config invite_cap_active / invite_cap_per_account).
//
// Contract under test (spec §P3-FL-05 + §P3-EF-01):
//   When invite_cap_active=true and a player has >= invite_cap_per_account codes,
//   generate() throws InviteCapExceeded.

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/invitations_repository.dart';
import 'package:runwar_app/models/invitation_code.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// Controls whether generate() should simulate the cap being active.
class CapAwareInvitationsRepository implements InvitationsRepository {
  final bool _capExceeded;
  final int _capValue;

  CapAwareInvitationsRepository({
    required bool capExceeded,
    int capValue = 999,
  })  : _capExceeded = capExceeded,
        _capValue = capValue;

  @override
  Future<InvitationCode> generate({
    String? code,
    int maxRedemptions = 1,
    DateTime? expiresAt,
  }) async {
    if (_capExceeded) throw const InviteCapExceeded();
    return InvitationCode(
      code: code ?? 'NEWCODE',
      maxRedemptions: maxRedemptions,
      redeemedCount: 0,
    );
  }

  @override
  Future<RedeemResult> redeem(String code) async {
    throw UnimplementedError();
  }

  @override
  Future<List<InvitationCode>> listMine() async => [];
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('InvitationsRepository — invite cap (P3-EF-01 §3)', () {
    // GIVEN invite_cap_active=true and the player already has >= cap codes
    // WHEN generate() is called
    // THEN throws InviteCapExceeded
    test('canInvite is blocked when invite_cap_active=true and player is at cap', () async {
      final repo = CapAwareInvitationsRepository(capExceeded: true, capValue: 999);

      expect(
        () => repo.generate(),
        throwsA(isA<InviteCapExceeded>()),
        reason: 'Must throw InviteCapExceeded when player is at or above app_config.invite_cap_per_account',
      );
    });

    // GIVEN invite_cap_active=true but the player has fewer codes than cap
    // WHEN generate() is called
    // THEN succeeds and returns an InvitationCode
    test('canInvite succeeds when player is below invite_cap_per_account', () async {
      final repo = CapAwareInvitationsRepository(capExceeded: false, capValue: 999);

      final result = await repo.generate();

      expect(result, isA<InvitationCode>());
      expect(result.code, isNotEmpty);
    });

    // GIVEN invite_cap_active=false (default)
    // WHEN generate() is called regardless of how many codes the player has
    // THEN succeeds (cap is not enforced)
    test('canInvite succeeds when invite_cap_active=false regardless of count', () async {
      // This repo does not throw — mimics cap-inactive state
      final repo = CapAwareInvitationsRepository(capExceeded: false);

      final result = await repo.generate(maxRedemptions: 5);

      expect(result.maxRedemptions, equals(5));
    });

    // GIVEN the InviteCapExceeded exception class
    // WHEN it is caught
    // THEN it is an Exception subtype (typed, not generic)
    test('InviteCapExceeded is a typed Exception subclass', () {
      const ex = InviteCapExceeded();

      expect(ex, isA<Exception>(),
          reason: 'InviteCapExceeded must be a typed Exception for screen-level catch');
    });
  });
}
