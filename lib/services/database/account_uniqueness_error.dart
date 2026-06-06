import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps a Postgres unique-violation on `players` to a user-facing message.
/// Returns null if the error is not a known account-uniqueness violation —
/// the caller should fall back to a generic error.
///
/// Constraint names are part of the contract — see migration 0033.
String? accountUniquenessMessage(Object? error) {
  if (error is! PostgrestException) return null;
  if (error.code != '23505') return null;
  final blob = '${error.message} ${error.details ?? ''}';
  if (blob.contains('players_phone_unique')) {
    return 'This phone number is already linked to another account.';
  }
  if (blob.contains('players_username_unique')) {
    return 'This username is already taken. Please choose another.';
  }
  return null;
}
