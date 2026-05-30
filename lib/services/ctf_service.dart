import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'realtime_presence_service.dart';
import '../config/supabase_config.dart';

class CtfEvent {
  const CtfEvent({
    required this.id,
    required this.city,
    required this.position,
    required this.expiresAt,
  });

  final String id;
  final String city;
  final LatLng position;
  final DateTime expiresAt;

  factory CtfEvent.fromMap(Map<String, dynamic> m) => CtfEvent(
        id: m['id'] as String,
        city: m['city'] as String? ?? 'Valencia',
        position: LatLng(
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
        ),
        expiresAt: DateTime.tryParse(m['expires_at'] as String? ?? '') ??
            DateTime.now().add(const Duration(minutes: 30)),
      );
}

/// Listens to ctf_events Realtime channel.
/// Fires a local notification when a new flag spawns within the configured
/// radius (app_config.ctf_notification_radius_km, default 100 km).
/// Exposes [activeEvents] stream for the map to render CTF pins.
class CtfService {
  CtfService._();
  static final CtfService instance = CtfService._();

  RealtimeChannel? _channel;
  final _controller = StreamController<List<CtfEvent>>.broadcast();
  final _notifications = FlutterLocalNotificationsPlugin();

  bool _notifInit = false;
  double _notifRadiusKm = 100; // default, overridden by app_config on init

  static const _channelId = 'runwar_ctf';
  static const _channelName = 'CTF Events';

  Stream<List<CtfEvent>> get activeEvents => _controller.stream;

  Future<void> init() async {
    debugPrint('[CtfService] init called — isConnected=${SupabaseService.instance.isConnected}');
    if (!SupabaseService.instance.isConnected) return;
    await _loadConfig();
    await _initNotifications();
    _subscribe();
    // Load any currently active events.
    await _fetchAndEmit();
    debugPrint('[CtfService] init complete — radius=${_notifRadiusKm}km notifInit=$_notifInit');
  }

  Future<void> _loadConfig() async {
    try {
      final rows = await SupabaseService.instance.supabase
          .from('app_config')
          .select('value')
          .eq('key', 'ctf_notification_radius_km')
          .maybeSingle();
      if (rows != null) {
        final raw = rows['value'] as String?;
        if (raw != null) _notifRadiusKm = double.tryParse(raw) ?? 100;
      }
    } catch (e) {
      debugPrint('[CtfService] config load error: $e (using default $_notifRadiusKm km)');
    }
  }

  Future<void> _initNotifications() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _notifications.initialize(
        const InitializationSettings(android: android),
      );
      final androidImpl = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      debugPrint('[CtfService] notification permission granted=$granted');
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Capture The Flag event alerts',
          importance: Importance.max,
        ),
      );
      _notifInit = true;
    } catch (e) {
      debugPrint('[CtfService] notification init error: $e');
    }
  }

  void _subscribe() {
    _channel = SupabaseService.instance.supabase
        .channel(SupabaseConfig.channelCtf)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ctf_events',
          callback: (payload) async {
            debugPrint('[CtfService] INSERT received: ${payload.newRecord}');
            final row = payload.newRecord;
            if (row['is_active'] == true) {
              final event = CtfEvent.fromMap(row);
              await _maybeFireNotification(event);
            }
            await _fetchAndEmit();
          },
        )
        .subscribe((status, error) {
          debugPrint('[CtfService] channel status=$status error=$error');
        });
  }

  /// Fires the notification only if the player is within [_notifRadiusKm].
  Future<void> _maybeFireNotification(CtfEvent event) async {
    final playerPos = RealtimePresenceService.instance.currentPosition;
    if (playerPos != null) {
      final distKm = _haversineKm(
        playerPos.latitude, playerPos.longitude,
        event.position.latitude, event.position.longitude,
      );
      debugPrint('[CtfService] CTF event ${event.id} — player is ${distKm.toStringAsFixed(1)} km away (radius: ${_notifRadiusKm} km)');
      if (distKm > _notifRadiusKm) return;
    }
    // No GPS fix yet → fire anyway (fail-open so first-launch testers aren't silenced).
    await _fireNotification(event);
  }

  Future<void> _fetchAndEmit() async {
    try {
      final rows = await SupabaseService.instance.supabase
          .from('ctf_events')
          .select()
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String());

      final events = (rows as List<dynamic>)
          .map((r) => CtfEvent.fromMap(r as Map<String, dynamic>))
          .toList();
      _controller.add(events);
    } catch (e) {
      debugPrint('[CtfService] fetch error: $e');
    }
  }

  Future<void> _fireNotification(CtfEvent event) async {
    debugPrint('[CtfService] _fireNotification called — notifInit=$_notifInit event=${event.id}');
    if (!_notifInit) return;
    try {
      await _notifications.show(
        event.hashCode,
        '🚩 FLAG DROPPED in ${event.city}!',
        'Race to the pin — capture it within ${event.expiresAt.difference(DateTime.now()).inMinutes} min. Reward: 500 credits + SHIELD.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Capture The Flag event alerts',
            importance: Importance.max,
            priority: Priority.max,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[CtfService] notification error: $e');
    }
  }

  /// Call when user taps "Join" on the CTF map pin.
  Future<bool> joinEvent(String eventId) async {
    if (!SupabaseService.instance.isConnected) return false;
    try {
      final response = await SupabaseService.instance.supabase.functions
          .invoke(SupabaseConfig.fnCtfJoin, body: {'event_id': eventId});
      return response.data?['joined'] == true;
    } catch (e) {
      debugPrint('[CtfService] joinEvent error: $e');
      return false;
    }
  }

  /// Call when user physically reaches the pin (≤50 m).
  Future<bool> claimWin(String eventId, LatLng playerPosition) async {
    if (!SupabaseService.instance.isConnected) return false;
    try {
      final response = await SupabaseService.instance.supabase.functions.invoke(
        SupabaseConfig.fnCtfClaimWin,
        body: {
          'event_id': eventId,
          'lat': playerPosition.latitude,
          'lng': playerPosition.longitude,
        },
      );
      return response.data?['won'] == true;
    } catch (e) {
      debugPrint('[CtfService] claimWin error: $e');
      return false;
    }
  }

  Future<void> dispose() async {
    await _channel?.unsubscribe();
    await _controller.close();
  }
}

// Haversine distance in km.
double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.pow(math.sin(dLng / 2), 2);
  return R * 2 * math.asin(math.sqrt(a));
}
