// lib/services/database/account_uniqueness_error.dart
//
// STUB — placeholder implementation for the RED phase.
// Returns null for every error so that assertion tests FAIL (RED).
// Replace with the real implementation in the GREEN phase.
//
// See design.md §4.5 for the full contract.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps a Postgres unique-violation on `players` to a user-facing message.
/// Returns null if the error is not a known account-uniqueness violation —
/// the caller should fall back to a generic error.
///
/// Constraint names are part of the contract — see migration 0033.
String? accountUniquenessMessage(Object? error) {
  // STUB: always returns null.
  // Real implementation checks:
  //   error is PostgrestException && error.code == '23505'
  // then inspects message+details for 'players_phone_unique' /
  // 'players_username_unique'.
  return null;
}
