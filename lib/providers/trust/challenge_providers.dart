// lib/providers/trust/challenge_providers.dart
// Phase 3 trust layer — challenge repository + service providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/database/challenges_repository.dart';
import '../../services/trust/challenge_service.dart';

final challengesRepoProvider = Provider<ChallengesRepository>(
  (ref) => SupabaseChallengesRepository(),
);

final challengeServiceProvider = Provider<ChallengeService>(
  (ref) => ChallengeService(ref.read(challengesRepoProvider)),
);

/// Live open challenge for a player. Emits null when no challenge exists.
final openChallengeProvider = StreamProvider.family<Challenge?, String>(
  (ref, playerId) =>
      ref.read(challengesRepoProvider).watchOpenChallenge(playerId),
);
