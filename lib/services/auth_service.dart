import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'database_service.dart';
import 'google_auth_service.dart';
import 'supabase_service.dart';
import '../config/constants.dart';

@visibleForTesting
String deriveEmailUsername(String id) =>
    'Runner_${id.replaceAll('-', '').substring(0, 6).toLowerCase()}';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // In-memory session map. Lost on process kill.
  Map<String, dynamic>? _currentUser;

  /// Creates a profile row in Supabase players table.
  /// Uses the Supabase-assigned UUID so `auth.uid()` matches the profile ID.
  /// Returns the new user map (id/email/created_at) or null on duplicate.
  Future<Map<String, dynamic>?> signUp(String email, String password) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Register with Supabase first to get the canonical UUID.
    final supabaseId = await SupabaseService.instance.signUpWithPassword(email, password);
    // Fall back to a local UUID when offline / Supabase unavailable.
    final id = supabaseId ?? _uuid.v4();

    // Auto-assign username and a deterministic palette color.
    final username = deriveEmailUsername(id);
    final color = kPlayerColors[id.hashCode.abs() % kPlayerColors.length];

    try {
      await DatabaseService.instance.insertProfile(
        id,
        username,
        color,
        influence: 1,
        invitedAt: null,
        isTester: 0,
        createdAt: nowIso,
      );
    } catch (e) {
      // Treat any unique-constraint equivalent as duplicate.
      debugPrint('[AuthService] signUp insert error: $e');
      return null;
    }

    _currentUser = {'id': id, 'email': email, 'created_at': nowIso};
    return _currentUser;
  }

  /// Signs in with Google via [GoogleAuthService], upserts the player into
  /// Supabase, and returns the user map. Returns null if the user cancelled.
  /// Throws [GoogleAuthException] on Google / Supabase errors.
  Future<Map<String, dynamic>?> signInWithGoogle() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Runs the native Google picker + Supabase token exchange.
    final googleUser = await GoogleAuthService.instance.signIn();
    if (googleUser == null) return null; // user cancelled

    final id = googleUser['id'] as String;
    final email = googleUser['email'] as String? ?? '$id@google.runwar';
    final displayName = googleUser['displayName'] as String?;

    // Derive a username from the display name or email prefix.
    final shortId = id.replaceAll('-', '').substring(0, 6).toUpperCase();
    final username = displayName?.toUpperCase().replaceAll(' ', '_') ?? 'RUNNER-$shortId';

    // Upsert: safe on every login — INSERT OR IGNORE preserves existing rows.
    await DatabaseService.instance.upsertProfileIgnore(
      id,
      username,
      '#FF7A00',
      influence: 1,
      invitedAt: null, // must redeem invitation code
      isTester: 0,
    );

    _currentUser = {'id': id, 'email': email, 'created_at': nowIso};
    debugPrint('[AuthService] Google sign-in complete: $username ($id)');
    return _currentUser;
  }

  /// Returns user map on credential match; null otherwise. Never throws.
  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    // Authenticate via Supabase — this is the authoritative source.
    final uid = await SupabaseService.instance.signInWithPassword(email, password);
    if (uid == null) return null;

    final supabaseUser = SupabaseService.instance.supabase.auth.currentUser;
    if (supabaseUser == null) return null;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    _currentUser = {
      'id': supabaseUser.id,
      'email': email,
      'created_at': supabaseUser.createdAt ?? nowIso,
    };
    return _currentUser;
  }

  /// Called once from main.dart after DB init.
  ///
  /// This is intentionally a no-op. `bots` has no client-writable RLS policy
  /// (server/migration-managed only — see supabase/migrations/0032_bots_table.sql)
  /// and the demo `zones` rows are owned by fixed bot IDs, which can never
  /// satisfy `zones_owner_all`'s `auth.uid() = owner_id` check for a real
  /// signed-in user. Both writes were structurally guaranteed to fail with a
  /// row-level-security error under the current access model — the bots are
  /// already seeded once via migration, and this call attempted a redundant,
  /// always-failing write on every app launch. Left as a no-op stub (rather
  /// than deleted outright) so callers/tests don't need to change.
  Future<void> seedDemoDataIfNeeded() async {}

  // Hard-coded alpha access codes — valid offline without Supabase lookup.
  static const _kAlphaCodes = {'ALPHA1'};

  /// Validates [code] and grants access.
  /// Alpha codes in [_kAlphaCodes] bypass Supabase and work offline.
  /// Other codes are validated against the Supabase `invitation_codes` table.
  /// Also updates the Supabase players profile so the route guard passes immediately.
  Future<bool> redeemInvitationCode(String code, String userId) async {
    final upper = code.trim().toUpperCase();
    if (upper.isEmpty) return false;

    final now = DateTime.now().toUtc().toIso8601String();

    if (!_kAlphaCodes.contains(upper)) {
      // Remote validation path for non-alpha codes.
      if (!SupabaseService.instance.isConnected) return false;
      final supabase = SupabaseService.instance.supabase;
      try {
        final codeRows = await supabase
            .from('invitation_codes')
            .select('code, max_redemptions')
            .eq('code', upper)
            .limit(1);

        if ((codeRows as List).isEmpty) return false;
        final codeRow = codeRows.first as Map<String, dynamic>;
        final maxRedemptions = (codeRow['max_redemptions'] as int?) ?? 1;

        final countRows = await supabase
            .from('code_redemptions')
            .select('id')
            .eq('code', upper);
        if ((countRows as List).length >= maxRedemptions) return false;

        await supabase.from('code_redemptions').insert({
          'code': upper,
          'user_id': userId,
          'redeemed_at': now,
        });
      } catch (e) {
        debugPrint('[AuthService] redeemInvitationCode error: $e');
        return false;
      }
    }

    // Update players row — triggers route guard to advance immediately.
    await DatabaseService.instance.updateInvitationStatus(userId, now, isTester: 1);
    return true;
  }

  /// Restores _currentUser from a persisted Supabase session on app restart.
  /// Called once from main() after SupabaseService.init(). No-ops if no session.
  ///
  /// Does NOT write to the players table. The route guard will read the
  /// existing profile via `profileGateProvider`; if no row exists (e.g., row
  /// was deleted server-side, or the session was restored without ever
  /// completing signInWithGoogle's upsert), the guard sends the user to
  /// JoinWarConfirmationScreen. Creating a privileged players row from a bare
  /// session would silently bypass the invitation/waitlist gates.
  Future<void> restoreSessionFromSupabase() async {
    final supabaseUid = SupabaseService.instance.currentUserId;
    if (supabaseUid == null) return;

    final supabaseUser = SupabaseService.instance.supabase.auth.currentUser;
    if (supabaseUser == null) return;

    _currentUser = {
      'id': supabaseUid,
      'email': supabaseUser.email ?? '$supabaseUid@runwar',
      'created_at': supabaseUser.createdAt,
    };
    debugPrint('[AuthService] session restored for $supabaseUid');
  }

  /// Clears in-memory session and signs out of Supabase Auth.
  Future<void> signOut() async {
    _currentUser = null;
    await SupabaseService.instance.signOut();
  }

  /// PoC no-op. Console log only. No network, no email.
  Future<void> sendPasswordReset(String email) async {
    debugPrint('[AuthService] sendPasswordReset($email) — PoC no-op');
  }

  /// Synchronous. Never hits DB or network.
  Map<String, dynamic>? getCurrentUser() => _currentUser;

  static const _uuid = Uuid();
}
