// lib/services/trust/challenge_service.dart
//
// ChallengeService — thin service layer over ChallengesRepository.
// Phase 3 trust layer. P3-FL-06.
//
// CONTRACT:
//   - No supabase_flutter import — depends on ChallengesRepository only.
//   - getOpenChallenge() returns null on error (safe for UI consumers).
//   - submitOutcome()    completes on success; throws ChallengeException on failure.
//   - watchOpenChallenge() delegates the stream directly to the repository.

import '../database/challenges_repository.dart';
import '../database/repository.dart';

/// Thin service over [ChallengesRepository].
///
/// Converts [RepoResult] values into typed returns or thrown [ChallengeException]s
/// so that Riverpod providers and UI layers can use standard AsyncValue error
/// handling without importing or switching on RepoResult themselves.
class ChallengeService {
  ChallengeService(this._repo);
  final ChallengesRepository _repo;

  /// Fetch the current open challenge for [playerId].
  ///
  /// Returns null when the player has no open challenge **or** on any
  /// infrastructure error (safe-return pattern — UI degrades gracefully).
  Future<Challenge?> getOpenChallenge(String playerId) async {
    final result = await _repo.getOpenChallenge(playerId);
    return switch (result) {
      Ok<Challenge?> r => r.value,
      Err<Challenge?> _ => null,
    };
  }

  /// Submit [outcome] ('resolve' | 'fail') for [challengeId].
  ///
  /// Completes normally on success.
  /// Throws [ChallengeException] on infrastructure or business failure.
  Future<void> submitOutcome(String challengeId, String outcome) async {
    final result = await _repo.submitChallengeOutcome(challengeId, outcome);
    if (result is Err<void>) {
      throw ChallengeException(
          'Failed to submit challenge outcome: ${result.detail ?? result.error.name}');
    }
  }

  /// Live stream of the open challenge for [playerId].
  ///
  /// Emits null when the player has no open challenge.
  /// Delegates directly to the repository — no buffering at this layer.
  Stream<Challenge?> watchOpenChallenge(String playerId) =>
      _repo.watchOpenChallenge(playerId);
}

/// Thrown by [ChallengeService] when a challenge operation fails.
class ChallengeException implements Exception {
  const ChallengeException(this.message);
  final String message;

  @override
  String toString() => 'ChallengeException: $message';
}
