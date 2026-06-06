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

  SupabaseClient get supabase {
    if (!_initialized) {
      throw StateError(
        '[SupabaseService] Supabase is not initialized. '
        'Call SupabaseService.instance.init() before accessing supabase.',
      );
    }
    return Supabase.instance.client;
  }

  /// True once init + anon auth completed successfully.
  bool get isConnected {
    if (!_initialized) return false;
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  /// Current Supabase user ID, or null if not yet authed.
  String? get currentUserId {
    if (!_initialized) return null;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

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

  /// Restores the existing Supabase session if one is persisted on device.
  /// Returns the current user ID, or null if not authenticated.
  /// A null return means the route guard will redirect to LoginScreen.
  Future<String?> signIn() async {
    if (!_initialized) return null;
    final existing = supabase.auth.currentSession;
    return existing?.user.id;
  }

  /// Registers a new user with Supabase Auth (email + password).
  /// Returns the Supabase-assigned UUID on success, null on error (offline / duplicate).
  Future<String?> signUpWithPassword(String email, String password) async {
    if (!_initialized) return null;
    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );
      return response.user?.id;
    } catch (e) {
      debugPrint('[SupabaseService] signUpWithPassword error: $e');
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
