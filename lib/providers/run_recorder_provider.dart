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

/// Mirrors [RunRecorderService.lastSimRawPosition] into Riverpod state so
/// MapScreen can rebuild on every SIM raw tick (rw_app-T0598), not only on
/// the 50m-gated [runRecorderTrackVersionProvider] ticks that
/// [runRecorderTrackVersionProvider] carries. Real-GPS position updates
/// still flow through MapScreen's own setState on _currentPosition - this
/// provider exists only for the SIM path.
final runRecorderSimRawPositionProvider = StateProvider<LatLng?>((ref) => null);

class RunRecorderNotifier extends StateNotifier<RecorderState> {
  RunRecorderNotifier(this._ref) : super(RecorderState.idle) {
    final svc = RunRecorderService.instance;
    svc.stateNotifier.addListener(_onServiceState);
    svc.trackVersion.addListener(_onTrackVersion);
    svc.lastSimRawPosition.addListener(_onSimRawPosition);
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
    // Wire the proximity-fast-path batch callback: writeGpsSamples already
    // accepts a list, so a buffered batch of fixes reaches gps_samples via a
    // single upsert instead of one upsert per fix.
    svc.onGpsFixBatch = (samples) async {
      final up =
          _ref.read(connectivityProvider).whenData((v) => v).valueOrNull ??
              false;
      await OutboxAwareWriter.instance.writeGpsSamples(
        samples,
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
    //
    // zonesProvider(city) is a StreamProvider.autoDispose. Riverpod's
    // invalidate() only schedules a resubscription - it keeps serving the
    // previous cached value (asyncTransition always calls copyWithPrevious)
    // until the resubscribed stream actually emits, which happens
    // asynchronously. A synchronous read taken right after a claim can
    // therefore still miss the zone that claim just produced. To make the
    // scan correct by construction instead of racing that emission, every
    // successful claim also writes its outline straight into
    // _pendingOwnedZoneEdges below, and this closure merges both sources.
    svc.ownedZoneEdgesProvider = () {
      final city = RunRecorderService.instance.activeCity;
      if (city.isEmpty) return const [];
      final userId = _ref.read(authProvider).user?['id'] as String?;
      if (userId == null) return const [];
      final zones = _ref.read(zonesProvider(city)).valueOrNull ?? const [];
      final freshOwned = zones.where(
        (z) => z.status == ZoneStatus.owned && z.ownerId == userId,
      );
      // Drop any pending entry the fresh snapshot has now caught up with, so
      // the map never serves a shape the server has since moved on from and
      // never grows without bound across a long run.
      for (final z in freshOwned) {
        _pendingOwnedZoneEdges.remove(z.id);
      }
      return [
        ...freshOwned.expand((z) => z.outlines),
        ..._pendingOwnedZoneEdges.values.expand((edges) => edges),
      ];
    };
  }

  final Ref _ref;

  /// Outlines for zones claimed this session whose ownership has not yet
  /// been confirmed by a fresh [zonesProvider] emission. Keyed by zone id so
  /// a stale entry is pruned the moment the real snapshot catches up (see
  /// [ownedZoneEdgesProvider] above).
  final Map<String, List<List<LatLng>>> _pendingOwnedZoneEdges = {};

  /// Registers the outline just produced by a successful claim so the very
  /// next scan can already treat it as an owned-zone wall, without waiting
  /// on the invalidated [zonesProvider] stream to re-emit.
  void _registerPendingOwnedZoneEdge(String zoneId, List<LatLng> outline) {
    _pendingOwnedZoneEdges[zoneId] = [List<LatLng>.from(outline)];
  }

  /// Test-only hook mirroring what [confirmClaim] does internally right
  /// after a successful claim, so tests can exercise the merge behaviour of
  /// [ownedZoneEdgesProvider] without driving a full network claim.
  @visibleForTesting
  void debugRegisterPendingOwnedZoneEdge(String zoneId, List<LatLng> outline) =>
      _registerPendingOwnedZoneEdge(zoneId, outline);

  /// Test-only window into how many claims are still waiting on a fresh
  /// [zonesProvider] emission, so a test can assert the pruning behaviour
  /// documented on [ownedZoneEdgesProvider] without reaching into private
  /// state directly.
  @visibleForTesting
  int get debugPendingOwnedZoneEdgeCount => _pendingOwnedZoneEdges.length;

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

  void _onSimRawPosition() {
    _ref.read(runRecorderSimRawPositionProvider.notifier).state =
        RunRecorderService.instance.lastSimRawPosition.value;
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

  /// Handles an auto-claim callback fired by RunRecorderService when a valid
  /// self-intersection is detected. [capturedPolygons] carries one-or-more
  /// sibling loops from the SAME run that RunRecorderService has already
  /// grouped by the 25 m seal-merge proximity radius - a group of 2+ is
  /// submitted as ONE claim so the server can union them into one
  /// contiguous shape, instead of dispatching one claim per loop.
  Future<void> _handleAutoClaim(List<List<LatLng>> capturedPolygons) async {
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
        _autoClaimOutcomeController.add((
          outcome: const ClaimOutcome(TerritoryResult.failed, null, reason: 'no_user_id'),
          polygon: capturedPolygons.first,
        ));
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
        _autoClaimOutcomeController.add((
          outcome: const ClaimOutcome(TerritoryResult.failed, null, reason: 'no_joined_city'),
          polygon: capturedPolygons.first,
        ));
      }
      return;
    }
    final city = capitalize(slugs.first);
    try {
      final outcome = await confirmClaim(userId, city, capturedPolygons);
      // Push outcome to the stream MapScreen listens on for the E&U overlay.
      // The overlay is drawn from the first member polygon - the server's
      // returned zone_geom_json (already invalidated into zonesProvider
      // below) is the source of truth for the actual unioned shape.
      if (!_autoClaimOutcomeController.isClosed) {
        _autoClaimOutcomeController
            .add((outcome: outcome, polygon: capturedPolygons.first));
      }
    } catch (e, st) {
      if (!_autoClaimOutcomeController.isClosed) {
        _autoClaimOutcomeController.add((
          outcome: ClaimOutcome(TerritoryResult.failed, null, reason: e.toString()),
          polygon: capturedPolygons.first,
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

  /// Evaluates a territory claim using the captured polygon(s), persists the
  /// run, and returns the [ClaimOutcome]. The recorder stays in `recording`
  /// state.
  ///
  /// [capturedPolygons] is one-or-more sibling loops already grouped by
  /// RunRecorderService's proximity check - a single-loop closure is a list
  /// of exactly one, unchanged from the prior single-polygon behaviour.
  ///
  /// Pre: every member of capturedPolygons has length >= 3; recorder state
  ///      == recording.
  /// Post: claim attempted; provider invalidations fired; outcome surfaced
  ///       to MapScreen via _autoClaimOutcomeController.
  Future<ClaimOutcome> confirmClaim(
    String userId,
    String city,
    List<List<LatLng>> capturedPolygons,
  ) async {
    final svc = RunRecorderService.instance;
    // The captured polygon(s) are what get sent to the edge function for
    // territory evaluation.
    final tracks = capturedPolygons
        .map((p) => List<LatLng>.from(p))
        .toList(growable: false);
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
        tracks,
        city,
      );
    }
    if (outcome == null) {
      // Offline fallback: TerritoryService.evaluateClaim only ever computes
      // a single ring locally (its own zone-union logic was already
      // evaluated and rejected for this exact reason - see
      // TerritoryService._mergeAdjacentZones's doc comment). Each sibling
      // loop is evaluated sequentially and AWAITED, so no two of them race
      // each other locally; a later ONLINE claim's server-side merge scan
      // (claim_territory) still reconciles any siblings this offline path
      // could not union, same as the pre-existing single-loop offline path
      // already relies on for pre-existing adjacent territory.
      for (final t in tracks) {
        outcome = await TerritoryService.instance.evaluateClaim(userId, city, t);
      }
    }
    // tracks is always non-empty (RunRecorderService never groups an empty
    // batch), so the branches above always assign outcome at least once.
    final resolvedOutcome = outcome!;
    final track = tracks.first;

    if (resolvedOutcome.result != TerritoryResult.failed &&
        resolvedOutcome.affectedZoneId != null &&
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
            'zone_id': resolvedOutcome.affectedZoneId!,
            'user_id': userId,
          },
          networkUp: networkUp,
        ));
      }
      // Fire-and-forget: check if this run earned a SHIELD superpower.
      final runId = sessionId ?? _uuidV4();
      unawaited(SuperpowerService.instance.checkAndEarn(runId: runId));
      if (resolvedOutcome.result == TerritoryResult.disputed) {
        // Fire-and-forget - never propagates to caller.
        unawaited(NotificationGateway.fireDispute(city));
      }
      // Make the claimed outline visible to the very next scan immediately -
      // invalidating zonesProvider below does not do this synchronously
      // (see the comment on ownedZoneEdgesProvider in the constructor).
      _registerPendingOwnedZoneEdge(resolvedOutcome.affectedZoneId!, track);
      _ref.invalidate(zonesProvider(city));
      _ref.invalidate(userRunPointsProvider((userId: userId, city: city)));
    }

    // Do NOT call svc.cancelRun() here.
    // The recorder stays in `recording` state so the next loop can form.
    return resolvedOutcome;
  }

  @override
  void dispose() {
    RunRecorderService.instance.onAutoClaim = null;
    RunRecorderService.instance.onGateRejected = null;
    RunRecorderService.instance.ownedZoneEdgesProvider = null;
    RunRecorderService.instance.stateNotifier.removeListener(_onServiceState);
    RunRecorderService.instance.trackVersion.removeListener(_onTrackVersion);
    RunRecorderService.instance.lastSimRawPosition.removeListener(_onSimRawPosition);
    _pendingOwnedZoneEdges.clear();
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
