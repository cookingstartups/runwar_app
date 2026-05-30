// Supabase project constants for RunWar PoC.
// The anon key is designed to be shipped in client code — it is restricted by RLS.
// Service-role key is NEVER in Flutter code; it lives only in Edge Functions.
class SupabaseConfig {
  SupabaseConfig._();

  // Project URL — always safe to expose.
  static const String url = 'https://glwsmxjptgmxaiyvdqzp.supabase.co';

  // Anon/public key — safe to expose; RLS prevents unauthorised writes.
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
      '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdsd3NteGpwdGdteGFpeXZkcXpwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxMzk2NzMsImV4cCI6MjA5NTcxNTY3M30'
      '.zUMK8_NSFfVzun_pnspmUxzYRtzjJsYNoptnM8RzmAw';

  // Realtime channel names.
  static const String channelZones = 'zones';
  static const String channelPresence = 'presence:global';
  static const String channelCtf = 'ctf_events';

  // Edge Function slugs.
  static const String fnClaimTerritory = 'claim_territory';
  static const String fnEarnSuperpower = 'earn_superpower';
  static const String fnAnticheatScore = 'anticheat_score';
  static const String fnCtfJoin = 'ctf_join';
  static const String fnCtfClaimWin = 'ctf_claim_win';
}
