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
    this.startsAt,
    this.isActive = false,
    this.preAnnounced = false,
    this.isJoined = false,
  });

  final String id;
  final String city;
  final LatLng position;
  final DateTime expiresAt;
  final DateTime? startsAt;
  final bool isActive;
  final bool preAnnounced;

  /// Set externally by CtfService based on _joinedEventIds — not from DB.
  final bool isJoined;

  factory CtfEvent.fromMap(Map<String, dynamic> m, {bool isJoined = false}) =>
      CtfEvent(
        id: m['id'] as String,
        city: m['city'] as String? ?? 'Valencia',
        position: LatLng(
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
        ),
        expiresAt: DateTime.tryParse(m['expires_at'] as String? ?? '') ??
            DateTime.now().add(const Duration(minutes: 30)),
        startsAt: m['starts_at'] != null
            ? DateTime.tryParse(m['starts_at'] as String)
            : null,
        isActive: m['is_active'] as bool? ?? false,
        preAnnounced: m['pre_announced'] as bool? ?? false,
        isJoined: isJoined,
      );
}

/// Listens to ctf_events Realtime channel (INSERT + UPDATE).
///
/// Two-stage notification lifecycle:
///   Stage 1 — pre_announced flip (false→true): "flag drops in ~60 min" warning.
///   Stage 2 — is_active flip (false→true): "FLAG DROPPED" alert.
///
/// Legacy events (starts_at IS NULL, is_active=true on INSERT) skip Stage 1.
/// Notification radius gated by app_config.ctf_notification_radius_km (default 100 km).
///
/// Join mechanic:
///   - Players can JOIN a pre-announced event via joinEvent(eventId).
///   - Only joined players see the active flag pin on the map (activeEvents stream).
///   - pendingEvents stream emits pre-announced events the player has NOT yet joined.
///   - Auto-capture: checkCaptureProximity(lat, lng) auto-calls claimWin when within threshold.
class CtfService {
  CtfService._();
  static final CtfService instance = CtfService._();

  RealtimeChannel? _channel;
  final _controller = StreamController<List<CtfEvent>>.broadcast();
  final _pendingController = StreamController<List<CtfEvent>>.broadcast();
  final _notifications = FlutterLocalNotificationsPlugin();

  bool _serviceInited = false;
  bool _notifInit = false;
  double _notifRadiusKm = 100;
  double _captureThresholdM = 50.0;
  String? _playerId;

  final _joinedEventIds = <String>{};
  final _captureAttemptedIds = <String>{};

  /// Track last emitted active events for proximity checks.
  List<CtfEvent> _lastActiveEvents = [];

  static const _channelId = 'runwar_ctf';
  static const _channelName = 'CTF Events';

  Stream<List<CtfEvent>> get activeEvents => _controller.stream;

  /// Pre-announced events (is_active=false, pre_announced=true) not yet joined.
  Stream<List<CtfEvent>> get pendingEvents => _pendingController.stream;

  Future<void> init({String? playerId}) async {
    if (_serviceInited) return;
    _serviceInited = true;
    _playerId = playerId;
    debugPrint('[CtfService] init called — isConnected=${SupabaseService.instance.isConnected} playerId=$playerId');
    if (!SupabaseService.instance.isConnected) return;
    await _loadConfig();
    await _initNotifications();
    await _loadJoinedEvents();
    _subscribe();
    await _fetchAndEmit();
    await _fetchAndEmitPending();
    debugPrint('[CtfService] init complete — radius=${_notifRadiusKm}km captureThreshold=${_captureThresholdM}m notifInit=$_notifInit');
  }

  Future<void> _loadConfig() async {
    try {
      final rows = await SupabaseService.instance.supabase
          .from('app_config')
          .select('key, value')
          .inFilter('key', ['ctf_notification_radius_km', 'ctf_capture_threshold_m']);
      for (final row in (rows as List<dynamic>)) {
        final key = row['key'] as String?;
        final raw = row['value'] as String?;
        if (raw == null) continue;
        if (key == 'ctf_notification_radius_km') {
          _notifRadiusKm = double.tryParse(raw) ?? 100;
        } else if (key == 'ctf_capture_threshold_m') {
          _captureThresholdM = double.tryParse(raw) ?? 50.0;
        }
      }
    } catch (e) {
      debugPrint('[CtfService] config load error: $e');
    }
  }

  Future<void> _loadJoinedEvents() async {
    if (_playerId == null) return;
    try {
      final rows = await SupabaseService.instance.supabase
          .from('ctf_participants')
          .select('event_id')
          .eq('player_id', _playerId!);
      for (final row in (rows as List<dynamic>)) {
        final id = (row as Map<String, dynamic>)['event_id'] as String?;
        if (id != null) _joinedEventIds.add(id);
      }
      debugPrint('[CtfService] loaded ${_joinedEventIds.length} joined events');
    } catch (e) {
      debugPrint('[CtfService] _loadJoinedEvents error: $e');
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
        // ── INSERT: legacy immediate-drop events (starts_at IS NULL) ──────────
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ctf_events',
          callback: (payload) async {
            debugPrint('[CtfService] INSERT received: ${payload.newRecord}');
            final row = payload.newRecord;
            // Only notify if the flag is already active (no scheduled delay).
            if (row['is_active'] == true && row['starts_at'] == null) {
              final event = CtfEvent.fromMap(row);
              await _maybeFireDroppedNotification(event);
            }
            await _fetchAndEmit();
            await _fetchAndEmitPending();
          },
        )
        // ── UPDATE: pg_cron flips pre_announced or is_active ─────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ctf_events',
          callback: (payload) async {
            debugPrint('[CtfService] UPDATE received: ${payload.newRecord}');
            final old = payload.oldRecord;
            final row = payload.newRecord;
            final event = CtfEvent.fromMap(row);

            // Stage 1: pre_announced just flipped → fire 1-hour warning.
            if (old['pre_announced'] == false &&
                row['pre_announced'] == true &&
                row['is_active'] == false) {
              await _maybeFirePreAnnouncementNotification(event);
            }

            // Stage 2: is_active just flipped → fire "FLAG DROPPED".
            if (old['is_active'] == false && row['is_active'] == true) {
              await _maybeFireDroppedNotification(event);
            }

            // Stage 3: winner_id just set → broadcast capture to all participants.
            if (old['winner_id'] == null && row['winner_id'] != null) {
              await _maybeFireCapturedNotification(
                event,
                row['winner_id'] as String,
              );
            }

            await _fetchAndEmit();
            await _fetchAndEmitPending();
          },
        )
        .subscribe((status, error) {
          debugPrint('[CtfService] channel status=$status error=$error');
        });
  }

  Future<void> _fetchAndEmit() async {
    try {
      final rows = await SupabaseService.instance.supabase
          .from('ctf_events')
          .select()
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String());

      final events = (rows as List<dynamic>)
          .map((r) {
            final m = r as Map<String, dynamic>;
            final joined = _joinedEventIds.contains(m['id'] as String?);
            return CtfEvent.fromMap(m, isJoined: joined);
          })
          .where((e) => _joinedEventIds.contains(e.id))
          .toList();

      _lastActiveEvents = events;
      _controller.add(events);
    } catch (e) {
      debugPrint('[CtfService] fetch error: $e');
    }
  }

  /// Fetches pre-announced events the player has not yet joined.
  Future<void> _fetchAndEmitPending() async {
    try {
      final rows = await SupabaseService.instance.supabase
          .from('ctf_events')
          .select()
          .eq('is_active', false)
          .eq('pre_announced', true)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String());

      final events = (rows as List<dynamic>)
          .map((r) => CtfEvent.fromMap(r as Map<String, dynamic>))
          .where((e) => !_joinedEventIds.contains(e.id))
          .toList();

      _pendingController.add(events);
    } catch (e) {
      debugPrint('[CtfService] pending fetch error: $e');
    }
  }

  // ── Notification helpers ────────────────────────────────────────────────────

  bool _withinRadius(CtfEvent event) {
    final playerPos = RealtimePresenceService.instance.currentPosition;
    if (playerPos == null) return true; // fail-open: no GPS fix yet
    final distKm = _haversineKm(
      playerPos.latitude, playerPos.longitude,
      event.position.latitude, event.position.longitude,
    );
    debugPrint('[CtfService] ${event.id} — player ${distKm.toStringAsFixed(1)} km (radius ${_notifRadiusKm} km)');
    return distKm <= _notifRadiusKm;
  }

  Future<void> _maybeFirePreAnnouncementNotification(CtfEvent event) async {
    if (!_withinRadius(event)) return;
    await _showNotification(
      id: event.hashCode ^ 1,
      title: '🔔 FLAG DROPS SOON in ${event.city}!',
      body: 'A flag drops in ${event.city} in ~60 min — get your running shoes on.',
    );
  }

  Future<void> _maybeFireDroppedNotification(CtfEvent event) async {
    if (!_withinRadius(event)) return;
    final minsLeft = event.expiresAt.difference(DateTime.now()).inMinutes;
    await _showNotification(
      id: event.hashCode,
      title: '🚩 FLAG DROPPED in ${event.city}!',
      body: 'Race to the pin — capture it within $minsLeft min. Reward: 500 credits + SHIELD.',
    );
  }

  /// Fires to every participant who has this event in _joinedEventIds.
  /// Fetches the winner's username from the players table.
  Future<void> _maybeFireCapturedNotification(
    CtfEvent event,
    String winnerId,
  ) async {
    if (!_joinedEventIds.contains(event.id)) return;
    String winnerName = 'A WARLORD';
    try {
      final rows = await SupabaseService.instance.supabase
          .from('players')
          .select('username')
          .eq('id', winnerId)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isNotEmpty) {
        winnerName = (list.first as Map<String, dynamic>)['username'] as String? ?? winnerName;
      }
    } catch (e) {
      debugPrint('[CtfService] winner lookup error: $e');
    }
    await _showNotification(
      id: event.hashCode ^ 2,
      title: '🏆 FLAG CAPTURED in ${event.city}!',
      body: '$winnerName snatched the flag. Better luck next time.',
    );
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    debugPrint('[CtfService] _showNotification id=$id title=$title');
    if (!_notifInit) return;
    try {
      await _notifications.show(
        id,
        title,
        body,
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

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    await _fetchAndEmit();
    await _fetchAndEmitPending();
  }

  Future<bool> joinEvent(String eventId) async {
    if (!SupabaseService.instance.isConnected) return false;
    try {
      final response = await SupabaseService.instance.supabase.functions
          .invoke(SupabaseConfig.fnCtfJoin, body: {'event_id': eventId});
      final joined = response.data?['joined'] == true;
      if (joined) {
        _joinedEventIds.add(eventId);
        // Refresh both streams: active may now include this event, pending removes it.
        await _fetchAndEmit();
        await _fetchAndEmitPending();
      }
      return joined;
    } catch (e) {
      debugPrint('[CtfService] joinEvent error: $e');
      return false;
    }
  }

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

  /// Auto-capture: called on every GPS update from MapScreen.
  /// For each active joined event, if the player is within [_captureThresholdM],
  /// calls claimWin automatically. Guard prevents duplicate calls per session.
  Future<void> checkCaptureProximity(double lat, double lng) async {
    final events = _lastActiveEvents;
    for (final event in events) {
      if (!event.isJoined) continue;
      if (_captureAttemptedIds.contains(event.id)) continue;
      final distM =
          _haversineKm(lat, lng, event.position.latitude, event.position.longitude) *
              1000;
      if (distM <= _captureThresholdM) {
        _captureAttemptedIds.add(event.id); // add BEFORE await to prevent races
        debugPrint('[CtfService] Auto-capture attempt for ${event.id} at ${distM.toStringAsFixed(1)}m');
        await claimWin(event.id, LatLng(lat, lng));
      }
    }
  }

  double get captureThresholdM => _captureThresholdM;

  Future<void> dispose() async {
    await _channel?.unsubscribe();
    await _controller.close();
    await _pendingController.close();
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
