// lib/providers/superpowers/offer_service_provider.dart
//
// Provider for OfferService — architect addition (design.md §5.2).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/offer_service.dart';
import '../repositories.dart';

/// OfferService for the session.
/// Pure wrapper — no timer/subscription lifecycle; no onDispose needed.
final offerServiceProvider = Provider<OfferService>(
  (ref) => OfferService(repo: ref.read(offersRepoProvider)),
);
