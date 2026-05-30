import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/run_recorder_service.dart';
import '../services/territory_service.dart';
import '../services/supabase_service.dart';
import '../services/database_service.dart';
import 'runs_provider.dart';
import 'zones_provider.dart';

final runRecorderProvider =
    StateNotifierProvider<RunRecorderNotifier, RecorderState>(
  (ref) => RunRecorderNotifier(ref),
);

/// A monotonic counter that increments on every GPS point append.
/// MapScreen watches this so the PolylineLayer rebuilds on each new point
/// without needing to watch a mutable list.
final runRecorderTrackVersionProvider = StateProvider<int>((ref) => 0);

class RunRecorderNotifier extends StateNotifier<RecorderState> {
  RunRecorderNotifier(this._ref) : super(RecorderState.idle) {
    final svc = RunRecorderService.instance;
    svc.stateNotifier.addListener(_onServiceState);
    svc.trackVersion.addListener(_onTrackVersion);
  }

  final Ref _ref;

  void _onServiceState() {
    state = RunRecorderService.instance.stateNotifier.value;
  }

  void _onTrackVersion() {
    _ref.read(runRecorderTrackVersionProvider.notifier).state =
        RunRecorderService.instance.trackVersion.value;
  }

  List<LatLng> get track => RunRecorderService.instance.track;

  Future<void> start() => RunRecorderService.instance.startRun();

  Future<LoopResult> stop() => RunRecorderService.instance.stopRun();

  void discard() => RunRecorderService.instance.discardRun();

  void forceClose() => RunRecorderService.instance.forceClose();

  /// Evaluates a territory claim, persists the run, and resets state.
  ///
  /// Returns the [ClaimOutcome] so the caller (MapScreen) can read both
  /// [ClaimOutcome.result] and [ClaimOutcome.affectedZoneId].
  Future<ClaimOutcome> confirmClaim(String userId, String city) async {
    final svc = RunRecorderService.instance;
    // Defensive snapshot — prevents mutation during the await chain.
    final track = List<LatLng>.from(svc.track);
    final startedAt = svc.startedAt;
    final closedAt = svc.closedAt ?? DateTime.now().toUtc();

    // Try server-side claim first (anti-cheat, Realtime sync).
    // Falls back to local evaluation when offline.
    ClaimOutcome? outcome;
    if (SupabaseService.instance.isConnected) {
      outcome = await TerritoryService.instance.claimViaEdgeFunction(
        track,
        city,
      );
    }
    outcome ??=
        await TerritoryService.instance.evaluateClaim(userId, city, track);

    if (outcome.result != TerritoryResult.failed &&
        outcome.affectedZoneId != null &&
        startedAt != null) {
      await _insertRun(
        userId: userId,
        city: city,
        track: track,
        startedAt: startedAt,
        closedAt: closedAt,
        zoneId: outcome.affectedZoneId!,
      );
      if (outcome.result == TerritoryResult.disputed) {
        // Fire-and-forget — never propagates to caller.
        unawaited(_NotificationGateway.fireDispute(city));
      }
      _ref.invalidate(zonesProvider(city));
      _ref.invalidate(userRunPointsProvider((userId: userId, city: city)));
    }

    svc.discardRun();
    return outcome;
  }

  Future<void> _insertRun({
    required String userId,
    required String city,
    required List<LatLng> track,
    required DateTime startedAt,
    required DateTime closedAt,
    required String zoneId,
  }) async {
    final db = DatabaseService.instance.db;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.insert('runs', {
      'id': _uuidV4(),
      'user_id': userId,
      'city': city,
      'track_json': _encodeLineString(track),
      'started_at': startedAt.toIso8601String(),
      'closed_at': closedAt.toIso8601String(),
      'zone_id': zoneId,
      'created_at': nowIso,
    });
  }

  @override
  void dispose() {
    RunRecorderService.instance.stateNotifier.removeListener(_onServiceState);
    RunRecorderService.instance.trackVersion.removeListener(_onTrackVersion);
    super.dispose();
  }
}

/// GeoJSON LineString encoder. Coordinates in [longitude, latitude] order
/// per RFC 7946.
String _encodeLineString(List<LatLng> track) {
  final coords =
      track.map((p) => '[${p.longitude},${p.latitude}]').join(',');
  return '{"type":"LineString","coordinates":[$coords]}';
}

// UUID v4 generator. Duplicated from TerritoryService to avoid adding the
// `uuid` package (design §13 / I-12). Both copies removed at Supabase swap.
final _rng = math.Random.secure();

String _uuidV4() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
      '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

// ── Notification gateway ──────────────────────────────────────────────────────

class _NotificationGateway {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool? _permissionGranted; // null = not yet asked

  static const _channelId = 'runwar_disputes';
  static const _channelName = 'Zone Disputes';

  /// Initialise the notifications plugin. Called from main() before runApp().
  /// Never throws — failure is logged via debugPrint.
  static Future<void> init() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin
          .initialize(const InitializationSettings(android: android, iOS: ios));

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Notifications when your territory is contested',
          importance: Importance.high,
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[NotificationGateway] init failed: $e');
    }
  }

  /// Fire a dispute notification. Requests permission lazily on first call.
  /// Fire-and-forget — never throws.
  static Future<void> fireDispute(String city) async {
    if (!_initialized) return;
    try {
      if (_permissionGranted == null) {
        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final iosImpl = _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          _permissionGranted =
              await androidImpl.requestNotificationsPermission() ?? false;
        } else if (iosImpl != null) {
          _permissionGranted = await iosImpl.requestPermissions(
                  alert: true, badge: false, sound: false) ??
              false;
        } else {
          _permissionGranted = false;
        }
      }
      if (_permissionGranted != true) return;

      await _plugin.show(
        0,
        'Zone Contested!',
        'Someone is challenging your territory in $city.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Notifications when your territory is contested',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationGateway] fireDispute failed: $e');
    }
  }
}

/// Public entry point for flutter_local_notifications initialisation.
/// Called from main() before runApp(). Keeps _NotificationGateway file-private.
Future<void> initLocalNotifications() => _NotificationGateway.init();
