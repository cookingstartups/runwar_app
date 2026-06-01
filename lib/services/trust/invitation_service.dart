// lib/services/trust/invitation_service.dart
//
// InvitationService — thin service wrapping InvitationsRepository.
// Phase 3 trust layer. P3-FL-02.
//
// CONTRACT:
//   - No supabase_flutter import — depends on InvitationsRepository only.
//   - generateCode() returns the code string on success; throws on failure.
//   - redeemCode()   completes on success; throws on failure.
//   - myInvites()    returns the raw list from the repository.
//   - Callers handle exceptions (e.g. via AsyncValue.error in providers).

import '../database/invitations_repository.dart';
import '../database/repository.dart';

/// Thin service over [InvitationsRepository].
///
/// Converts [RepoResult] values into typed returns or thrown [InvitationException]s
/// so that Riverpod providers and UI layers can use standard AsyncValue error handling
/// without needing to import or switch on RepoResult themselves.
class InvitationService {
  InvitationService(this._repo);
  final InvitationsRepository _repo;

  /// Generate a new invitation code for the current user.
  ///
  /// Returns the raw invitation code string (e.g. "RUNWAR-XK9Y2").
  /// Throws [InvitationException] on infrastructure or business failure.
  Future<String> generateCode({
    String? label,
    int maxRedemptions = 1,
    DateTime? expiresAt,
  }) async {
    final result = await _repo.generate(
      label: label,
      maxRedemptions: maxRedemptions,
      expiresAt: expiresAt,
    );
    return switch (result) {
      Ok<Map<String, dynamic>> r =>
        r.value['code'] as String? ??
            (throw const InvitationException(
                'generate_invite_code returned no code field')),
      Err<Map<String, dynamic>> e =>
        throw InvitationException(
            'Failed to generate invite code: ${e.detail ?? e.error.name}'),
    };
  }

  /// Redeem the invitation code [code] for the current user.
  ///
  /// Completes normally on success.
  /// Throws [InvitationException] if the code is invalid, expired, or exhausted.
  Future<void> redeemCode(String code) async {
    final result = await _repo.redeem(code);
    if (result is Err<Map<String, dynamic>>) {
      throw InvitationException(
          'Failed to redeem invite code: ${result.detail ?? result.error.name}');
    }
  }

  /// List all invitation codes created by the current user.
  ///
  /// Returns the raw row list. Throws [InvitationException] on failure.
  Future<List<Map<String, dynamic>>> myInvites() async {
    final result = await _repo.listMine();
    return switch (result) {
      Ok<List<Map<String, dynamic>>> r => r.value,
      Err<List<Map<String, dynamic>>> e =>
        throw InvitationException(
            'Failed to load invites: ${e.detail ?? e.error.name}'),
    };
  }
}

/// Thrown by [InvitationService] when an invitation operation fails.
class InvitationException implements Exception {
  const InvitationException(this.message);
  final String message;

  @override
  String toString() => 'InvitationException: $message';
}
