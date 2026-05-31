// lib/providers/drops/active_drops_provider.dart
//
// StreamProvider.family for active drops by city.
// Phase 2 design.md §5.1. Key: city (String).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/database/drops_repository.dart';
import '../repositories.dart';

/// Live list of active drops for [city].
/// Drives the DropMarker layer on MapScreen.
final activeDropsProvider = StreamProvider.family<List<Drop>, String>(
  (ref, city) => ref.read(dropsRepoProvider).watchActive(city),
);
