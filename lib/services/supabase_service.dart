import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Singleton wrapper around Supabase.
/// Call [init] once in main(), then [signIn] to get/create an anon session.
/// All other services read [supabase] and [isConnected] from this instance.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  bool _initialized = false;

  SupabaseClient get supabase => Supabase.instance.client;

  /// True once init + anon auth completed successfully.
  bool get isConnected =>
      _initialized && supabase.auth.currentSession != null;

  /// Current Supabase user ID, or null if not yet authed.
  String? get currentUserId => supabase.auth.currentUser?.id;

  Future<void> init() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        autoRefreshToken: true,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
    _initialized = true;
  }

  /// Returns the Supabase user ID for this device session.
  /// Creates a new anonymous session on first launch; restores on subsequent.
  Future<String?> signIn() async {
    if (!_initialized) return null;

    // Restore existing session if present.
    final existing = supabase.auth.currentSession;
    if (existing != null) return existing.user.id;

    try {
      final response = await supabase.auth.signInAnonymously();
      return response.user?.id;
    } catch (e) {
      // Network unavailable — offline mode, returns null.
      return null;
    }
  }

  /// Signs in with email + password via Supabase Auth.
  /// Returns the Supabase user ID on success, null on failure.
  /// Safe to call even if a session already exists (returns existing ID).
  Future<String?> signInWithPassword(String email, String password) async {
    if (!_initialized) return null;

    // Reuse existing session if already authenticated with same email.
    final existing = supabase.auth.currentSession;
    if (existing != null && existing.user.email == email) {
      return existing.user.id;
    }

    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user?.id;
    } catch (e) {
      debugPrint('[SupabaseService] signInWithPassword error: $e');
      return null;
    }
  }

  /// Signs out of Supabase Auth. Safe to call even if not signed in.
  Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint('[SupabaseService] signOut error: $e');
    }
  }
}
