// lib/providers/economy/economy_service_provider.dart
//
// Provider for EconomyService — architect addition (design.md §5.2).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/economy_service.dart';
import '../repositories.dart';

/// EconomyService singleton for the session.
/// Pure observer — holds no mutable state; no onDispose needed.
final economyServiceProvider = Provider<EconomyService>(
  (ref) => EconomyService(
    credits: ref.read(creditsRepoProvider),
    ledger: ref.read(ledgerRepoProvider),
  ),
);
