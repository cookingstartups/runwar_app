import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import '../config/supabase_config.dart';

class SuperpowerGrant {
  const SuperpowerGrant({
    required this.powerType,
    required this.expiresAt,
    required this.creditsToActivate,
  });

  final String powerType;
  final DateTime expiresAt;
  final int creditsToActivate;
}

/// Calls earn_superpower after qualifying runs.
/// On SHIELD grant, exposes the result via [onShieldEarned] callback so
/// map_screen can show the post-earn offer.
class SuperpowerService {
  SuperpowerService._();
  static final SuperpowerService instance = SuperpowerService._();

  /// Set from map_screen to handle the post-earn offer modal.
  void Function(SuperpowerGrant)? onShieldEarned;

  /// Call after every successful zone claim.
  /// Returns the grant if SHIELD was awarded; null otherwise.
  Future<SuperpowerGrant?> checkAndEarn({required String runId}) async {
    if (!SupabaseService.instance.isConnected) return null;

    try {
      final response = await SupabaseService.instance.supabase.functions.invoke(
        SupabaseConfig.fnEarnSuperpower,
        body: {'run_id': runId},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['granted'] != true) return null;

      final grant = SuperpowerGrant(
        powerType: data['power_type'] as String? ?? 'SHIELD',
        expiresAt: DateTime.tryParse(data['expires_at'] as String? ?? '') ??
            DateTime.now().add(const Duration(minutes: 30)),
        creditsToActivate: (data['credits_to_activate'] as int?) ?? 100,
      );

      onShieldEarned?.call(grant);
      return grant;
    } catch (e) {
      debugPrint('[SuperpowerService] earn error: $e');
      return null;
    }
  }
}
