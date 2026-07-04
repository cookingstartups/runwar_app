import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/run_recorder_service.dart';
import '../services/territory_service.dart';
import '../services/supabase_service.dart';
import '../services/superpower_service.dart';
import '../services/outbox_aware_writer.dart';
import '../services/error_log_service.dart';
import '../utils/string_utils.dart';
import 'auth_provider.dart';
import 'cities_provider.dart';
import 'connectivity_provider.dart';
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
    // Register the auto-claim callback.
    svc.onAutoClaim = _handleAutoClaim;
    // Register the gate-rejection callback (R1) — mirrors onAutoClaim's pattern.
    svc.onGateRejected = (reason, details) async {
      if (!_gateRejectionController.isClosed) {
        _gateRejectionController.add((reason: reason, details: details));
      }
    };
    // Wire real-time GPS streaming: each spacing-filtered fix goes to gps_samples.
    svc.onGpsFix = (sample) async {
      final up =
          _ref.read(connectivityProvider).whenData((v) => v).valueOrNull ??
              false;
      await OutboxAwareWriter.instance.writeGpsSamples(
        [sample],
        networkUp: up,
      );
    };
    // Wire runs row updates (stub/stop/cancel/lasso-link).
    svc.onRunUpdate = (sid, fields) async {
      final up =
          _ref.read(connectivityProvider).whenData((v) => v).valueOrNull ??
              false;
      await OutboxAwareWriter.instance.writeRunUpdate(
        sid,
        fields,
        networkUp: up,
      );
    };
  }

  final Ref _ref;

  final _autoClaimOutcomeController =
      StreamController<({ClaimOutcome outcome, List<LatLng> polygon})>.broadcast();

  /// Stream of auto-claim outcomes. MapScreen listens on this for E&U overlay
  /// triggering and mission hook invocation.
  Stream<({ClaimOutcome outcome, List<LatLng> polygon})> get autoClaimOutcomes =>
      _autoClaimOutcomeController.stream;

  final _gateRejectionController =
      StreamController<({GateRejectionReason reason, Map<String, dynamic> details})>.broadcast();

  /// Stream of silent auto-claim gate rejections (area floor / session
  /// elapsed). MapScreen listens on this to surface a distinct toast per
  /// gate (R1).
  Stream<({GateRejectionReason reason, Map<String, dynamic> details})> get gateRejections =>
      _gateRejectionController.stream;

  void _onServiceState() {
    state = RunRecorderService.instance.stateNotifier.value;
  }

  void _onTrackVersion() {
    _ref.read(runRecorderTrackVersionProvider.notifier).state =
        RunRecorderService.instance.trackVersion.value;
  }

  List<LatLng> get track => RunRecorderService.instance.track;

  Future<void> start() async {
    final auth = _ref.read(authProvider);
    final userId = auth.user?['id'] as String?;
    if (userId != null) {
      final slugs =
          _ref.read(joinedCitySlugsProvider(userId)).valueOrNull;
      RunRecorderService.instance.activeCity =
          (slugs != null && slugs.isNotEmpty) ? slugs.first : '';
    }
    await RunRecorderService.instance.startRun();
  }

  Future<void> stop() => RunRecorderService.instance.stopRun();

  Future<void> cancel() => RunRecorderService.instance.cancelRun();

  /// Resumes a run from orphaned run_scratch rows.
  /// Delegates to [RunRecorderService.resumeFromScratch].
  Future<void> resume(String userId) {
    final slugs =
        _ref.read(joinedCitySlugsProvider(userId)).valueOrNull;
    RunRecorderService.instance.activeCity =
        (slugs != null && slugs.isNotEmpty) ? slugs.first : '';
    return RunRecorderService.instance.resumeFromScratch(userId);
  }

  /// Handles an auto-claim callback fired by RunRecorderService when
  /// a valid self-intersection is detected.
  Future<void> _handleAutoClaim(List<LatLng> capturedPolygon) async {
    final auth = _ref.read(authProvider);
    final userId = auth.user?['id'] as String?;
    if (userId == null) {
      ErrorLogService.logClientError(
        provider: '_handleAutoClaim',
        error: 'userId null - auto-claim dropped',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      if (!_autoClaimOutcomeController.isClosed) {
        _autoClaimOutcomeController.add(
          (outcome: const ClaimOutcome(TerritoryResult.failed, null, reason: 'no_user_id'), polygon: capturedPolygon),
        );
      }
      return;
    }
    // City is resolved from joinedCitySlugsProvider - first slug, capitalised.
    final slugs = _ref.read(joinedCitySlugsProvider(userId)).valueOrNull;
    if (slugs == null || slugs.isEmpty) {
      ErrorLogService.logClientError(
        provider: '_handleAutoClaim',
        error: 'joinedCitySlugs null/empty - auto-claim dropped',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      if (!_autoClaimOutcomeController.isClosed) {
        _autoClaimOutcomeController.add(
          (outcome: const ClaimOutcome(TerritoryResult.failed, null, reason: 'no_joined_city'), polygon: capturedPolygon),
        );
      }
      return;
    }
    final city = capitalize(slugs.first);
    try {
      final outcome = await confirmClaim(userId, city, capturedPolygon);
      // Push outcome to the stream MapScreen listens on for the E&U overlay.
      if (!_autoClaimOutcomeController.isClosed) {
        _autoClaimOutcomeController
            .add((outcome: outcome, polygon: capturedPolygon));
      }
    } catch (e, st) {
      if (!_autoClaimOutcomeController.isClosed) {
        _autoClaimOutcomeController.add((
          outcome: ClaimOutcome(TerritoryResult.failed, null, reason: e.toString()),
          polygon: capturedPolygon,
        ));
      }
      ErrorLogService.logClientError(
        provider: '_handleAutoClaim',
        error: e,
        stackTrace: st,
        retryCount: 0,
      );
    }
  }

  /// Evaluates a territory claim using the captured polygon, persists the run,
  /// and returns the [ClaimOutcome]. The recorder stays in `recording` state.
  ///
  /// Pre: capturedPolygon.length >= 3; recorder state == recording.
  /// Post: claim attempted; provider invalidations fired; outcome surfaced
  ///       to MapScreen via _autoClaimOutcomeController.
  Future<ClaimOutcome> confirmClaim(
    String userId,
    String city,
    List<LatLng> capturedPolygon,
  ) async {
    final svc = RunRecorderService.instance;
    // The captured polygon is what gets sent to the edge function for
    // territory evaluation.
    final track = List<LatLng>.from(capturedPolygon);
    final startedAt = svc.startedAt;

    // Resolve connectivity once for this entire claim flow.
    final networkUp =
        _ref.read(connectivityProvider).whenData((v) => v).valueOrNull ?? false;
    final canWrite = SupabaseService.instance.canWriteRemote(networkUp);

    // Try server-side claim first (anti-cheat, Realtime sync).
    // Falls back to local evaluation when offline.
    ClaimOutcome? outcome;
    if (canWrite) {
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
      final sessionId = svc.currentSessionId;
      // Link this claim's lasso and zone to the in-flight runs row.
      // GPS samples are already streaming in real-time; no batch upload needed.
      if (sessionId != null) {
        final lassoId = _uuidV4();
        unawaited(OutboxAwareWriter.instance.writeRunUpdate(
          sessionId,
          {
            'lasso_id': lassoId,
            'zone_id': outcome.affectedZoneId!,
            'user_id': userId,
          },
          networkUp: networkUp,
        ));
      }
      // Fire-and-forget: check if this run earned a SHIELD superpower.
      final runId = sessionId ?? _uuidV4();
      unawaited(SuperpowerService.instance.checkAndEarn(runId: runId));
      if (outcome.result == TerritoryResult.disputed) {
        // Fire-and-forget - never propagates to caller.
        unawaited(_NotificationGateway.fireDispute(city));
      }
      _ref.invalidate(zonesProvider(city));
      _ref.invalidate(userRunPointsProvider((userId: userId, city: city)));
    }

    // Do NOT call svc.cancelRun() here.
    // The recorder stays in `recording` state so the next loop can form.
    return outcome;
  }

  @override
  void dispose() {
    RunRecorderService.instance.onAutoClaim = null;
    RunRecorderService.instance.onGateRejected = null;
    RunRecorderService.instance.stateNotifier.removeListener(_onServiceState);
    RunRecorderService.instance.trackVersion.removeListener(_onTrackVersion);
    _autoClaimOutcomeController.close();
    _gateRejectionController.close();
    super.dispose();
  }
}

// UUID v4 generator. Duplicated from TerritoryService to avoid adding the
// `uuid` package. Both copies removed at Supabase swap.
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
  /// Never throws - failure is logged via debugPrint.
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
  /// Fire-and-forget - never throws.
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
