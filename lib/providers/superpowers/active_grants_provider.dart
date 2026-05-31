// lib/providers/superpowers/active_grants_provider.dart
//
// StreamProvider.family for active superpower grants by playerId.
// Phase 2 design.md §5.1. Key: playerId (String).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/database/superpowers_repository.dart';
import '../repositories.dart';

/// Live list of active superpower grants for [playerId].
/// Drives SuperpowerInventoryStrip and SuperpowerRuntime.
final activeGrantsProvider =
    StreamProvider.family<List<SuperpowerGrant>, String>(
  (ref, playerId) =>
      ref.read(superpowersRepoProvider).watchActiveGrants(playerId),
);
