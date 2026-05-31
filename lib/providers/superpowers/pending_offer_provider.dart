// lib/providers/superpowers/pending_offer_provider.dart
//
// StreamProvider.family for the player's current pending offer.
// Phase 2 design.md §5.1. Key: playerId (String).
//
// MapScreen listens with ref.listen to push the contextual offer modal
// per the dismiss-and-push supersession contract (design.md §6.4).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/database/offers_repository.dart';
import '../repositories.dart';

/// Current pending offer for [playerId], or null if none.
/// Emits a new value whenever a second earn event supersedes the active offer
/// (server calls create_offer_with_supersede — modal dismisses and re-opens).
final pendingOfferProvider = StreamProvider.family<SuperpowerOffer?, String>(
  (ref, playerId) => ref.read(offersRepoProvider).watchPending(playerId),
);
