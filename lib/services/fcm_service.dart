import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// Handles FCM token registration and foreground message routing.
/// Background messages are handled by the top-level [_handleBackgroundMessage].
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _inited = false;

  Future<void> init({required String playerId}) async {
    if (_inited) return;
    _inited = true;
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[FcmService] permission=${settings.authorizationStatus}');

      final token = await messaging.getToken();
      if (token != null) {
        await _saveToken(playerId, token);
      }

      // Refresh token on rotation.
      messaging.onTokenRefresh.listen((t) => _saveToken(playerId, t));
    } catch (e) {
      debugPrint('[FcmService] init error: $e');
    }
  }

  Future<void> _saveToken(String playerId, String token) async {
    debugPrint('[FcmService] saving token for $playerId');
    try {
      await SupabaseService.instance.supabase
          .from('players')
          .update({'fcm_token': token})
          .eq('id', playerId);
    } catch (e) {
      debugPrint('[FcmService] token save error: $e');
    }
  }
}

/// Must be a top-level function for background message handling.
@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  debugPrint('[FCM background] ${message.notification?.title}');
}
