// lib/providers/repositories.dart
//
// Single binding point for Phase 2 repository providers.
// Phase 2 design.md §5.1. Tests override providers here.
//
// Phase 1 repo providers (zonesRepositoryProvider, disputesRepositoryProvider,
// appConfigRepositoryProvider) remain in their own files for backward compat.
//
// supabase_flutter is imported here because the supabaseClientProvider exposes
// the SupabaseClient. This file is NOT under lib/services/ but Riverpod
// providers that instantiate Supabase-backed repos necessarily reference the
// client type. The constraint (design.md §3) is that supabase_flutter is
// hidden behind repo implementations — UI layers never import it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../services/database/credits_repository.dart';
import '../services/database/ledger_repository.dart';
import '../services/database/drops_repository.dart';
import '../services/database/superpowers_repository.dart';
import '../services/database/offers_repository.dart';

/// Exposes the Supabase client to repository providers.
/// Override in tests with a mock SupabaseClient if needed.
final supabaseClientProvider = Provider<SupabaseClient>(
  (_) => SupabaseService.instance.supabase,
);

/// Credits balance + watch (read-only).
final creditsRepoProvider = Provider<CreditsRepository>(
  (ref) => SupabaseCreditsRepository(ref.read(supabaseClientProvider)),
);

/// Credit transaction ledger (debug/wallet surface).
final ledgerRepoProvider = Provider<LedgerRepository>(
  (ref) => SupabaseLedgerRepository(ref.read(supabaseClientProvider)),
);

/// Active drops by city.
final dropsRepoProvider = Provider<DropsRepository>(
  (ref) => SupabaseDropsRepository(ref.read(supabaseClientProvider)),
);

/// Active superpower grants + earn-event reporting.
final superpowersRepoProvider = Provider<SuperpowersRepository>(
  (ref) => SupabaseSuperpowersRepository(ref.read(supabaseClientProvider)),
);

/// Pending offer stream + accept/decline.
final offersRepoProvider = Provider<OffersRepository>(
  (ref) => SupabaseOffersRepository(ref.read(supabaseClientProvider)),
);
