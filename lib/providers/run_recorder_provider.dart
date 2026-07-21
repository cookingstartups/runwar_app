import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../services/database/models/zone.dart';
import '../services/run_recorder_service.dart';
import '../services/territory_service.dart';
import '../services/supabase_service.dart';
import '../services/superpower_service.dart';
import '../services/outbox_aware_writer.dart';
import '../services/error_log_service.dart';
import '../services/permission_service.dart';
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
    // Push a fresh snapshot of the runner's own owned-zone outlines into the
    // plain-Dart service on every scan call. This is the one legitimate
    // Riverpod (ref) access point in the chain - lasso.dart and
    // run_recorder_service.dart never import zonesProvider themselves.
    svc.ownedZoneEdgesProvider = () {
      final city = RunRecorderService.instance.activeCity;
      if (city.isEmpty) return const [];
      final userId = _ref.read(authProvider).user?['id'] as String?;
      if (userId == null) return const [];
      final zones = _ref.read(zonesProvider(city)).valueOrNull ?? const [];
      return zones
          .where((z) => z.status == ZoneStatus.owned && z.ownerId == userId)
          .expand((z) => z.outlines)
          .toList();
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
        unawaited(NotificationGateway.fireDispute(city));
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
    RunRecorderService.instance.ownedZoneEdgesProvider = null;
    RunRecorderService.instance.stateNotifier.removeListener(_onServiceState);
    RunRecorderService.instance.trackVersion.removeListener(_onTrackVersion);
    _autoClaimOutcomeController.close();
    _gateRejectionController.close();
    super.dispose();
  }
}

const _uuid = Uuid();

String _uuidV4() => _uuid.v4();

// ── Notification gateway ──────────────────────────────────────────────────────

/// Promoted from a file-private class to a small public surface so
/// PermissionService can reuse [requestPermission] instead of duplicating it
/// (design.md §API Contracts).
class NotificationGateway {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

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

  /// Requests local-notification permission. Extracted from fireDispute's
  /// inline request block so PermissionService can call it independently of
  /// firing a notification, from the PermissionPrimingScreen's Notifications
  /// card CTA. Never throws - returns false on any failure.
  static Future<bool> requestPermission() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final iosImpl = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        return await androidImpl.requestNotificationsPermission() ?? false;
      } else if (iosImpl != null) {
        return await iosImpl.requestPermissions(
                alert: true, badge: false, sound: false) ??
            false;
      }
      return false;
    } catch (e) {
      debugPrint('[NotificationGateway] requestPermission failed: $e');
      return false;
    }
  }

  /// Fire a dispute notification. Fire-and-forget - never throws. Permission
  /// is no longer requested here - PermissionService is the single owner of
  /// that decision, resolved during the priming flow.
  static Future<void> fireDispute(String city) async {
    if (!_initialized) return;
    try {
      if (!await PermissionService.instance.isNotificationsGranted()) return;

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
/// Called from main() before runApp().
Future<void> initLocalNotifications() => NotificationGateway.init();
