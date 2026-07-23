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

  // Web Client ID from Google Cloud Console (OAuth 2.0 → Web client).
  // Required for Supabase to verify the Google ID token.
  // Steps: Firebase Console → Authentication → Google → enable → download updated google-services.json
  //        Google Cloud Console → APIs & Services → Credentials → Web client → copy Client ID here
  // Also set in: Supabase Dashboard → Authentication → Providers → Google
  static const String googleWebClientId =
      '646002557080-se7o2t8pkp987bsjdabokcrkl55euh11.apps.googleusercontent.com';

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
  static const String fnSavePhone = 'save_phone';
  static const String fnJoinCityWaitlists = 'join_city_waitlists';
  static const String fnResolveDecayMerges = 'resolve_decay_merges';
}
