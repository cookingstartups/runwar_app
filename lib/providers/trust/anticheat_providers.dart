// lib/providers/trust/anticheat_providers.dart
// Phase 3 trust layer — anticheat repository + orientation service providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/database/anticheat_repository.dart';
import '../../services/trust/anticheat_orientation_service.dart';

final antiCheatRepoProvider = Provider<AntiCheatRepository>(
  (ref) => SupabaseAntiCheatRepository(),
);

final antiCheatOrientationServiceProvider = Provider<AntiCheatOrientationService>(
  (ref) => AntiCheatOrientationService(ref.read(antiCheatRepoProvider)),
);

/// Live suspicion score for a player.
final suspicionScoreProvider = StreamProvider.family<SuspicionScore, String>(
  (ref, playerId) => ref.read(antiCheatRepoProvider).watchScore(playerId),
);
