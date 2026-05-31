// lib/services/offer_service.dart
//
// OfferService — wraps OffersRepository with countdown helper.
// Phase 2 design.md §4.1.
//
// CONTRACT:
//   - No supabase_flutter import — depends on OffersRepository only.
//   - accept() / decline() delegate to the repo.
//   - countdown() emits remaining seconds each second; closes at 0.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'database/offers_repository.dart';

/// Thin wrapper around [OffersRepository] adding a countdown helper stream.
///
/// Instantiated once per session via [offerServiceProvider].
class OfferService {
  OfferService({required OffersRepository repo}) : _repo = repo;

  final OffersRepository _repo;

  /// Live stream of the player's current pending offer, or null.
  Stream<SuperpowerOffer?> watch(String playerId) =>
      _repo.watchPending(playerId);

  /// Accept [offer], optionally providing GPS context for BLITZ/FORTIFY.
  Future<SpendResult> accept(
    SuperpowerOffer offer, {
    String? targetZoneId,
    double? lat,
    double? lng,
  }) async {
    debugPrint(
        '[OfferService] accept ${offer.id} (${offer.offeredPowerType})');
    return _repo.accept(
      offer.id,
      targetZoneId: targetZoneId,
      lat: lat,
      lng: lng,
    );
  }

  /// Mark [offer] as declined.
  Future<void> decline(SuperpowerOffer offer) async {
    debugPrint(
        '[OfferService] decline ${offer.id} (${offer.offeredPowerType})');
    return _repo.decline(offer.id);
  }

  /// Returns a stream of remaining seconds (counting down to 0) for [offer].
  /// Closes the stream at 0. Each tick fires once per second.
  Stream<int> countdown(SuperpowerOffer offer) {
    final controller = StreamController<int>();
    Timer.periodic(const Duration(seconds: 1), (t) {
      final remaining =
          offer.expiresAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        controller.add(0);
        controller.close();
        t.cancel();
      } else {
        controller.add(remaining);
      }
    });
    return controller.stream;
  }
}
