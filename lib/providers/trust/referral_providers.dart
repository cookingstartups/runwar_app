// lib/providers/trust/referral_providers.dart
// Phase 3 trust layer — referral repository + service providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/database/referrals_repository.dart';
import '../../services/trust/referral_service.dart';

final referralsRepoProvider = Provider<ReferralsRepository>(
  (ref) => SupabaseReferralsRepository(),
);

final referralServiceProvider = Provider<ReferralService>(
  (ref) => ReferralService(ref.read(referralsRepoProvider)),
);

/// Total kickback earned by the current player (live stream).
final totalKickbackProvider = StreamProvider.family<int, String>(
  (ref, playerId) => ref.read(referralsRepoProvider).watchTotalKickback(playerId),
);

/// Kickback history for a player (one-shot, newest-first, up to 50 entries).
final kickbackHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, inviterId) =>
      ref.watch(referralServiceProvider).getKickbackHistory(inviterId),
);
