import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Handles native Google Sign-In and exchanges the ID token with Supabase Auth.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: SupabaseConfig.googleWebClientId.isEmpty
        ? null
        : SupabaseConfig.googleWebClientId,
    scopes: ['email', 'profile'],
  );

  /// Launches the Google Sign-In flow and signs in to Supabase via ID token.
  ///
  /// Returns a map with {id, email, displayName, photoUrl} on success,
  /// or null if the user cancelled.
  ///
  /// Throws a [GoogleAuthException] with a human-readable message on error.
  Future<Map<String, dynamic>?> signIn() async {
    if (SupabaseConfig.googleWebClientId.isEmpty) {
      throw const GoogleAuthException(
        'Google Sign-In is not configured yet. '
        'Please complete the Google Cloud Console setup and add the Web Client ID '
        'to SupabaseConfig.googleWebClientId.',
      );
    }

    // Try silent re-login first (no UI if already authenticated).
    GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signInSilently();
    } catch (_) {
      account = null;
    }

    // Fall back to interactive picker.
    if (account == null) {
      try {
        account = await _googleSignIn.signIn();
      } catch (e) {
        debugPrint('[GoogleAuthService] signIn error: $e');
        throw GoogleAuthException('Google Sign-In failed: $e');
      }
    }

    // User cancelled the picker.
    if (account == null) return null;

    final GoogleSignInAuthentication auth;
    try {
      auth = await account.authentication;
    } catch (e) {
      debugPrint('[GoogleAuthService] authentication error: $e');
      throw GoogleAuthException('Failed to retrieve Google authentication tokens: $e');
    }

    final idToken = auth.idToken;
    if (idToken == null) {
      throw const GoogleAuthException(
        'Google did not return an ID token. '
        'Ensure the Web Client ID is correctly configured.',
      );
    }

    try {
      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken,
      );

      final user = response.user;
      if (user == null) {
        throw const GoogleAuthException('Supabase did not return a user after Google sign-in.');
      }

      return {
        'id': user.id,
        'email': user.email ?? account.email,
        'displayName': account.displayName,
        'photoUrl': account.photoUrl,
      };
    } catch (e) {
      if (e is GoogleAuthException) rethrow;
      debugPrint('[GoogleAuthService] Supabase signInWithIdToken error: $e');
      throw GoogleAuthException('Supabase Google sign-in failed: $e');
    }
  }

  /// Signs out from Google (revokes the local Google session).
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('[GoogleAuthService] signOut error: $e');
    }
  }
}

/// Thrown by [GoogleAuthService] when sign-in fails with a known reason.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
