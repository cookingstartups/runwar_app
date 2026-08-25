// lib/providers/zone_claim_history_provider.dart
//
// Read path for "zones the current user has EVER held ownership of"
// (migration 0071's zone_claim_history table, backed by the
// trg_record_zone_claim trigger on zones.owner_id). Sibling to
// userRunPointsProvider (runs_provider.dart) - both feed map_screen.dart's
// fog-of-war reveal gate, this one for the permanent-once-revealed-per-zone
// contract (independent of current ownership, unlike the fog-circle/
// proximity source).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';

/// Set of zone ids [userId] has ever claimed/conquered, at any point in
/// time - including zones since lost, expired, or merged away. A zone in
/// this set must always render regardless of current ownership or fog
/// proximity (map_screen.dart's visibleZones).
final everClaimedZoneIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, userId) async {
  if (userId.isEmpty) return const {};
  final ids = await DatabaseService.instance.getEverClaimedZoneIds(userId);
  return ids.toSet();
});
