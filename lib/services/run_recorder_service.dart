import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'error_log_service.dart';
import 'realtime_presence_service.dart';
import 'run_scratch_store.dart';
import 'telemetry_service.dart';
import '../geo/lasso.dart'
    show
        detectSelfIntersection,
        computeCapture,
        polygonArea,
        polygonBboxDiagonalM,
        trackDistanceM;
import '../utils/runwar_constants.dart';

enum RecorderState { idle, recording }

/// Reason an auto-claim scan silently rejected a detected loop closure.
/// Surfaced via [RunRecorderService.onGateRejected] so the UI layer can
/// give the operator distinct, non-blocking feedback per gate (R1).
enum GateRejectionReason {
  areaFloor,
  diagonalFloor,
  compactness,
  pathLength,
  sessionElapsed,
}

/// One entry from a run replay fixture, as parsed from its `events` array.
/// `type` is one of `run_start`, `gps_fix`, `claim_rejected`, or
/// `user_stop_pressed`; see [RunRecorderService.runSimulationSequence] for
/// how each type is handled.
class SimulationFixEvent {
  const SimulationFixEvent({required this.t, required this.type, required this.data});

  final DateTime t;
  final String type;
  final Map<String, dynamic> data;
}

class RunRecorderService {
  RunRecorderService._();
  static final RunRecorderService instance = RunRecorderService._();

  static const _uuid = Uuid();

  final ValueNotifier<RecorderState> stateNotifier =
      ValueNotifier(RecorderState.idle);

  // trackVersion increments on every track mutation (append / clear).
  // Used by RunRecorderNotifier to rebuild MapScreen for live polyline
  // without exposing the mutable list directly.
  final ValueNotifier<int> trackVersion = ValueNotifier(0);

  final List<LatLng> _track = <LatLng>[];
  DateTime? _startedAt;
  DateTime? _closedAt;
  StreamSubscription<Position>? _posSub;
  String? _activeUserId;
  Timer? _notifTimer;

  // Owns the scheduling of the NEXT synthetic fix during a simulation. This
  // is a distinct handle from _posSub on purpose: cancelling one can never
  // be confused with cancelling the other, and "is a simulation active" can
  // be queried independent of stateNotifier (which both real and simulated
  // recording share as `recording`).
  Timer? _simTimer;

  // Durable session identity minted at startRun and recovered on crash/resume.
  String? _currentSessionId;

  // True while a tester-only simulated replay is driving _onPosition instead
  // of the real device GPS stream. This is the single switch that decides
  // which source is live; see beginSimulation() for the isolation guarantee.
  bool _simActive = false;

  /// Whether a simulated replay is currently driving the recorder instead of
  /// the real device GPS stream.
  bool get isSimulationActive => _simActive;

  @visibleForTesting
  bool get hasRealGpsSubscriptionForTesting => _posSub != null;

  // Expose session ID so the provider layer can wire lasso_id + zone_id writes.
  String? get currentSessionId => _currentSessionId;

  // Lower bound for the self-intersection scan. Set to 0 at startRun,
  // advanced to _track.length after each claim that is actually dispatched
  // (accepted or failed downstream). A below-floor area rejection does NOT
  // advance it, since the trail history is still needed for a later,
  // genuinely large loop to close.
  int _loopStartTrailIndex = 0;

  // Wall-clock moment of the FAB Start tap. Used for the 60-second gate.
  // Persists across multiple auto-claims within the same session.
  DateTime? _sessionStartTime;

  // Callback invoked when an auto-claim should fire. Set by the provider
  // during construction; the service does not import the provider layer.
  Future<void> Function(List<LatLng> capturedPolygon)? onAutoClaim;

  // Callback invoked when an auto-claim scan silently rejects a detected loop
  // closure at the area-floor or session-elapsed gate. Set by the provider
  // during construction, same pattern as onAutoClaim.
  Future<void> Function(GateRejectionReason reason, Map<String, dynamic> details)?
      onGateRejected;

  // Callback invoked for each spacing-filtered GPS fix so the provider layer
  // can stream it to gps_samples via OutboxAwareWriter without this service
  // importing connectivity or Riverpod.
  Future<void> Function(Map<String, dynamic> sample)? onGpsFix;

  // Callback invoked when the runs row needs a partial update (stop/cancel/
  // confirmClaim lasso link). Arguments: sessionId, field map.
  Future<void> Function(String sessionId, Map<String, dynamic> fields)? onRunUpdate;

  // Area floor for auto-claim. Below this, a captured loop is silently
  // discarded (no claim dispatched, onGateRejected fires with areaFloor).
  //
  // Must stay numerically equal to the server-side floor in
  // supabase/functions/claim_territory/index.ts (minCapturedAreaSqm) - the
  // two are enforced independently (client gates before dispatch, server
  // gates again on receipt) and a mismatch lets a claim pass one side and
  // fail the other. If this value changes, change the server value too.
  //
  // 1500 sqm is a jitter/real-loop separation floor derived from a single
  // observed live run (n=1): the one genuine loop closure measured about
  // 24 972 sqm, while every spurious/jitter closure logged in that same run
  // measured between 0.4 and 40.8 sqm - a separation factor over 600x.
  //
  // The value is set above the accuracy gate's own worst case rather than
  // just above observed noise. At the 20 m accuracy gate below, a stationary
  // phone pinned at that boundary can in theory enclose roughly pi * 20^2,
  // about 1257 sqm, through jitter alone. A floor below that figure would sit
  // inside the envelope it is meant to backstop, so 1500 is chosen to clear
  // it. Against measured jitter it carries about a 37x margin.
  //
  // In player terms 1500 sqm is roughly a 39 m square, about 155 m of
  // perimeter, realistically 200 to 250 m of movement once real streets and
  // corners are involved. That keeps the area floor, rather than the 60 s
  // session gate, as the binding constraint on effort.
  static const double _minCapturedAreaSqm = 1500.0;

  // Minimum bounding-box diagonal (metres) a captured auto-claim polygon
  // must span, checked alongside the area floor above. Rejects thin slivers
  // that clear the area floor only because they are long and narrow, not
  // because they enclose a real block-scale loop. See
  // kMinCapturedAreaDiagonalM in runwar_constants.dart, which generalises
  // the same reasoning already used for kMinProximityClosureDiagonalM on the
  // vertex-proximity closure path.
  static const double _minCapturedAreaDiagonalM = kMinCapturedAreaDiagonalM;

  // GPS accuracy gate (metres). A position fix reporting accuracy worse than
  // this is rejected before it ever reaches _track, before the proximity
  // fast path, and before the spacing filter. This is the primary
  // anti-jitter defence - see the honesty note on _minCapturedAreaSqm above:
  // the area floor alone cannot rule out a stationary phone enclosing a
  // spurious loop through jitter, but a stationary phone reporting under
  // 20 m accuracy cannot enclose enough area through jitter to matter.
  static const double _gpsAccuracyMaxM = 20.0;

  /// Minimum distance in metres between consecutive stored track points.
  /// A new GPS fix within this distance of _track.last is dropped before
  /// _track.add and before the scratch table write. Strictly greater than
  /// the OS distanceFilter of 25 m so the app filter actually fires; large
  /// enough (5x the vertex-proximity tolerance) to guarantee stored
  /// vertices are never within the vertex-proximity envelope of each other.
  static const double _minTrackPointSpacingM = kTrackPointSpacingM;

  // No auto-claim may fire before this many seconds have elapsed since
  // the FAB Start tap. Applies once per session, not per loop.
  static const int _minSessionElapsedSec = 60;

  @visibleForTesting
  static const String kNotificationTitle = 'RunWar - Active Session';
  @visibleForTesting
  static const Duration kForegroundTaskInterval = Duration(seconds: 15);
  @visibleForTesting
  static const String kNotificationChannelImportance = 'default';

  void setActiveUser(String? userId) => _activeUserId = userId;

  List<LatLng> get track => List.unmodifiable(_track);
  List<LatLng> get trackSnapshot => List.unmodifiable(_track);
  DateTime? get startedAt => _startedAt;
  DateTime? get closedAt => _closedAt;

  /// City slug for the active run. Set by the provider before calling startRun()
  /// so the NOT NULL runs.city column is satisfied on the Postgres upsert.
  String activeCity = '';

  Future<void> startRun() async {
    if (stateNotifier.value == RecorderState.recording) return;
    _clearTrackInternal();
    _startedAt = DateTime.now().toUtc();
    _closedAt = null;
    _loopStartTrailIndex = 0;
    _sessionStartTime = DateTime.now();
    trackVersion.value++;
    // Mint a stable session identity for this run.
    _currentSessionId = _uuid.v4();
    // Clear any leftover scratch points from a previous run.
    final uid = _activeUserId;
    if (uid != null) {
      try {
        await RunScratchStore.instance.deleteForUser(uid);
      } catch (_) {}
    }
    // Write the runs stub row before the GPS stream opens so gps_samples
    // rows always have a parent runs row on the server.
    final sid = _currentSessionId!;
    final cb = onRunUpdate;
    if (cb != null && uid != null) {
      cb(sid, {
        'id': sid,
        'user_id': uid,
        'city': activeCity,
        'started_at': _startedAt!.toIso8601String(),
        'status': 'active',
      }).catchError((_) {});
    }
    await _startForegroundTask();
    _openGpsStream();
    RealtimePresenceService.instance.setRecording(true);
    stateNotifier.value = RecorderState.recording;
    TelemetryService.instance.logEvent('start_run').catchError((_) {});
  }

  void _onPosition(Position pos) {
    if (stateNotifier.value != RecorderState.recording) return;
    // Defensive guard: discard non-finite coordinates.
    if (pos.latitude.isNaN || pos.longitude.isNaN) return;
    if (pos.latitude.isInfinite || pos.longitude.isInfinite) return;
    // Accuracy gate: reject any fix reporting worse than _gpsAccuracyMaxM
    // before it enters _track, before the proximity fast path, and before
    // the spacing filter. This is the primary anti-jitter defence (see the
    // honesty note on _minCapturedAreaSqm above). Every synthetic fix a
    // simulation feeds through this same pipeline is stamped with a fixed,
    // good accuracy value in _applySimulationEvent, so this gate never
    // blocks a simulated replay.
    if (pos.accuracy > _gpsAccuracyMaxM) return;
    final newLatLng = LatLng(pos.latitude, pos.longitude);
    // Always update presence so rival comets stay live regardless of spacing
    // filter - except during a simulation, where the position is synthetic
    // and must never be broadcast to other players as if it were a real
    // runner moving through the city.
    if (!_simActive) {
      RealtimePresenceService.instance.updatePosition(newLatLng);
    }
    // Proximity pre-check: if raw fix is within kProximityTriggerM of any prior
    // stored vertex (from _loopStartTrailIndex onward), bypass the spacing filter
    // so the closing fix is stored and _scanForAutoClaim can detect the closure.
    if (_track.length > 1) {
      final scanFrom = math.max(0, _loopStartTrailIndex);
      for (int i = scanFrom; i < _track.length; i++) {
        if (_equirectangularDistanceM(_track[i], newLatLng) < kProximityTriggerM) {
          _track.add(newLatLng);
          trackVersion.value++;
          final scratchUid = _scratchUserId();
          if (scratchUid != null) {
            // Intentional: closing fix may be closer than kTrackPointSpacingM; invariant relaxed only at loop closure
            RunScratchStore.instance.insertPoint(
              scratchUid, pos.latitude, pos.longitude,
              accuracy: pos.accuracy,
              ts: pos.timestamp.toIso8601String(),
            ).catchError((e) {
              debugPrint('[RunRecorderService] scratch insert error on closure fix: $e');
            });
          }
          _scanForAutoClaim();
          return;
        }
      }
    }
    // Track-point spacing filter: discard fixes < 50 m from the last stored point.
    if (_track.isNotEmpty &&
        _equirectangularDistanceM(_track.last, newLatLng) < _minTrackPointSpacingM) {
      return;
    }
    _track.add(newLatLng);
    trackVersion.value++;
    // Persist point to scratch table for crash/process-kill recovery. A
    // simulation writes under a namespaced scratch key (see _scratchUserId)
    // so a killed app never resumes a simulated track as if it were a real
    // interrupted run.
    final scratchUid = _scratchUserId();
    if (scratchUid != null) {
      RunScratchStore.instance.insertPoint(
        scratchUid,
        pos.latitude,
        pos.longitude,
        accuracy: pos.accuracy,
        ts: pos.timestamp.toIso8601String(),
        sessionId: _currentSessionId,
        isMocked: _simActive ? true : pos.isMocked,
      ).catchError((_) {});
    }

    // Stream this fix to gps_samples in real-time via the provider callback.
    // Fire-and-forget: a write failure must never terminate the GPS loop.
    final uid = _activeUserId;
    if (uid != null) {
      final sid = _currentSessionId;
      final gpsCb = onGpsFix;
      if (gpsCb != null && sid != null) {
        gpsCb({
          'run_id': sid,
          'session_id': sid,
          'user_id': uid,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'ts': pos.timestamp.toIso8601String(),
          'speed_ms': pos.speed,
          // Every row written during a simulation is forced true regardless
          // of the fixture's own recorded value - this is the write-time
          // guarantee, independent of whatever Position the replay driver
          // happened to construct.
          'is_mocked': _simActive ? true : pos.isMocked,
        }).catchError((e, st) {
          // Fire-and-forget stays non-blocking - the GPS loop must never
          // stall on a write failure - but the failure is now observable
          // instead of silently disappearing.
          ErrorLogService.logClientError(
            provider: 'run_recorder_service.onGpsFix',
            error: e,
            stackTrace: st,
            retryCount: 0,
          );
        });
      }
    }

    // Auto-claim scan on every new fix.
    _scanForAutoClaim();
  }

  Future<void> _startForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'runwar_run_tracking',
        channelName: 'Run Tracking',
        channelDescription: 'RunWar is recording your route.',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
    // Android 13+ requires POST_NOTIFICATIONS to be granted at runtime.
    // Manifest declaration alone is insufficient. FCM also triggers this dialog
    // from main_shell, but we request defensively here so the run notification
    // is guaranteed regardless of FCM init order or the user denying FCM.
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    await FlutterForegroundTask.startService(
      serviceId: 100,
      notificationTitle: kNotificationTitle,
      notificationText: '00:00',
    );
    // Update the notification body with elapsed time every 15 s.
    // The timer runs on the main isolate so it can read _startedAt directly.
    _notifTimer?.cancel();
    _notifTimer = Timer.periodic(kForegroundTaskInterval, (_) {
      final started = _startedAt;
      if (started == null || stateNotifier.value != RecorderState.recording) {
        return;
      }
      final elapsed = DateTime.now().toUtc().difference(started);
      final mm = elapsed.inMinutes.toString().padLeft(2, '0');
      final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      unawaited(FlutterForegroundTask.updateService(
        notificationTitle: kNotificationTitle,
        notificationText: '$mm:$ss',
      ));
    });
  }

  /// Ends the recording session without evaluating any loop validity gates.
  /// The recorder transitions directly to idle. Any in-flight onAutoClaim
  /// futures continue to completion independently.
  Future<void> stopRun() async {
    if (stateNotifier.value != RecorderState.recording) return;
    final wasSimulation = _simActive;
    final scratchUid = _scratchUserId();
    _simActive = false;
    _simTimer?.cancel();
    _simTimer = null;
    _notifTimer?.cancel();
    _notifTimer = null;
    await _posSub?.cancel();
    _posSub = null;
    if (!wasSimulation) {
      RealtimePresenceService.instance.setRecording(false);
      unawaited(FlutterForegroundTask.stopService());
    }
    _closedAt = DateTime.now().toUtc();
    // Total distance from the recorded track, computed before the track is
    // cleared. ended_at and finalized_at both use the same moment as
    // closed_at: this call is the only place a completed run's terminal
    // state and metrics are written, so there is no separate later step
    // that "finalizes" the row.
    final distanceM = trackDistanceM(_track);
    // Write the completed status BEFORE clearing scratch so the outbox row
    // is enqueued even if scratch deletion fails.
    final sid = _currentSessionId;
    final runCb = onRunUpdate;
    final uid = _activeUserId;
    if (runCb != null && sid != null && uid != null) {
      runCb(sid, {
        'status': 'completed',
        'closed_at': _closedAt!.toIso8601String(),
        'ended_at': _closedAt!.toIso8601String(),
        'distance_m': distanceM,
        'finalized_at': _closedAt!.toIso8601String(),
        'user_id': uid,
      }).catchError((_) {});
    }
    _currentSessionId = null;
    // Track is retained in memory in case an in-flight onAutoClaim future
    // is still using it. _clearTrackInternal runs on the NEXT startRun().
    // Scratch is cleared here so a future resumeFromScratch on a
    // killed-app path does not re-hydrate this finished session.
    if (scratchUid != null) {
      try {
        await RunScratchStore.instance.deleteForUser(scratchUid);
      } catch (_) {}
    }
    _loopStartTrailIndex = 0;
    _sessionStartTime = null;
    stateNotifier.value = RecorderState.idle;
    if (!wasSimulation) {
      TelemetryService.instance.logEvent('stop_run').catchError((_) {});
    }
  }

  /// Discards the current track and idles the recorder WITHOUT claiming.
  /// Triggered by FAB long-press while recording.
  ///
  /// Pre: state == recording (no-op otherwise).
  /// Post: state == idle; track cleared; presence untracked; GPS stream closed;
  ///       scratch table cleared.
  Future<void> cancelRun() async {
    if (stateNotifier.value != RecorderState.recording) return;
    final wasSimulation = _simActive;
    final scratchUid = _scratchUserId();
    _simActive = false;
    _simTimer?.cancel();
    _simTimer = null;
    _notifTimer?.cancel();
    _notifTimer = null;
    await _posSub?.cancel();
    _posSub = null;
    if (!wasSimulation) {
      RealtimePresenceService.instance.setRecording(false);
      unawaited(FlutterForegroundTask.stopService());
    }
    // A cancelled run still has a real end moment and real distance
    // travelled up to that point - it is just not claimed as territory.
    // Recording ended_at/distance_m/finalized_at for cancelled runs too
    // keeps the runs table meaningful for every terminal status instead of
    // leaving cancelled rows permanently blank.
    final cancelledAt = DateTime.now().toUtc();
    final distanceM = trackDistanceM(_track);
    // Write the cancelled status BEFORE clearing scratch.
    final sid = _currentSessionId;
    final runCb = onRunUpdate;
    final uid = _activeUserId;
    if (runCb != null && sid != null && uid != null) {
      runCb(sid, {
        'status': 'cancelled',
        'closed_at': cancelledAt.toIso8601String(),
        'ended_at': cancelledAt.toIso8601String(),
        'distance_m': distanceM,
        'finalized_at': cancelledAt.toIso8601String(),
        'user_id': uid,
      }).catchError((_) {});
    }
    _currentSessionId = null;
    if (scratchUid != null) {
      try {
        await RunScratchStore.instance.deleteForUser(scratchUid);
      } catch (_) {}
    }
    _clearTrackInternal();
    _loopStartTrailIndex = 0;
    _sessionStartTime = null;
    stateNotifier.value = RecorderState.idle;
    if (!wasSimulation) {
      TelemetryService.instance.logEvent('cancel_run').catchError((_) {});
    }
  }

  /// Runs detectSelfIntersection on the newest segment and dispatches an
  /// auto-claim if the captured polygon clears the 200 m^2 floor and the
  /// 60-second post-start window has elapsed.
  ///
  /// Pre: state == recording; _track.length >= 1; _sessionStartTime != null.
  /// Post: at most one onAutoClaim future is dispatched per call.
  void _scanForAutoClaim() {
    // detectSelfIntersection requires loopStartTrailIndex >= 1.
    // When _loopStartTrailIndex is 0 (initial state), clamp to 1 so the
    // first segment of the track is included in the scan.
    final scanStart = math.max(1, _loopStartTrailIndex);
    final hit = detectSelfIntersection(_track, scanStart);
    if (hit == null) return;

    final k = _track.length - 1;
    final polygon = computeCapture(
      _track,
      scanStart,
      hit.intersectingSegmentIdx,
      hit.intersectionPoint,
      k,
      isProximityClosure: hit.isProximityClosure,
    );

    // Area floor (m^2). polygonArea returns km^2 -> convert.
    final areaSqm = polygonArea(polygon) * 1e6;
    if (areaSqm < _minCapturedAreaSqm) {
      // Do NOT advance _loopStartTrailIndex here. A below-floor result only
      // means the newest edge did not close a big-enough loop yet - it does
      // not mean the trail history is invalid. Truncating it would permanently
      // discard the segments a later, genuinely large loop needs in order to
      // be detected, so a real enclosing loop could never be claimed once a
      // small spurious closure had been rejected first.
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.area_floor_gate',
        error: 'rejected: area=${areaSqm.toStringAsFixed(1)}sqm floor=$_minCapturedAreaSqm',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      onGateRejected?.call(GateRejectionReason.areaFloor, {'area_sqm': areaSqm});
      return;
    }

    // Bounding-box diagonal floor. Rejects a thin sliver that clears the
    // area floor only because it is long and narrow, not because it
    // encloses a real block-scale loop. Same non-advancement reasoning as
    // the area-floor branch above: the trail history is still needed for a
    // later, genuinely large loop to close.
    final diagonalM = polygonBboxDiagonalM(polygon);
    if (diagonalM < _minCapturedAreaDiagonalM) {
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.diagonal_floor_gate',
        error: 'rejected: diagonal=${diagonalM.toStringAsFixed(1)}m floor=$_minCapturedAreaDiagonalM',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      onGateRejected?.call(GateRejectionReason.diagonalFloor, {'diagonal_m': diagonalM});
      return;
    }

    // Compactness floor. The diagonal check above does not catch a long thin
    // sliver that clears both the area and diagonal floors on its own - for
    // example a 1500 sqm shape stretched over a 200 m diagonal. Dividing area
    // by diagonal squared separates them: a square scores 0.5, a 1:4
    // rectangle about 0.19, a needle near zero. Same non-advancement
    // reasoning as the branches above.
    final compactness = diagonalM > 0 ? areaSqm / (diagonalM * diagonalM) : 0.0;
    if (compactness < kMinCapturedAreaCompactness) {
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.compactness_gate',
        error: 'rejected: compactness=${compactness.toStringAsFixed(3)} '
            'floor=$kMinCapturedAreaCompactness',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      onGateRejected?.call(
          GateRejectionReason.compactness, {'compactness': compactness});
      return;
    }

    // Path-length floor, measured along the captured loop's own vertices.
    // Unlike area, diagonal and compactness, this one cannot be satisfied by
    // shape alone - it requires the phone to have physically travelled that
    // far, which is what makes it the anti-farming check rather than an
    // anti-jitter one.
    final loopPathM = trackDistanceM(polygon);
    if (loopPathM < kMinCapturedPathLengthM) {
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.path_length_gate',
        error: 'rejected: path=${loopPathM.toStringAsFixed(1)}m '
            'floor=$kMinCapturedPathLengthM',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      onGateRejected?.call(
          GateRejectionReason.pathLength, {'path_m': loopPathM});
      return;
    }

    // 60-second gate (per session, not per loop). Note this is no longer the
    // binding constraint on effort: a loop clearing the area and path floors
    // above already implies well over a minute of movement.
    final start = _sessionStartTime;
    if (start == null ||
        DateTime.now().difference(start).inSeconds < _minSessionElapsedSec) {
      // Leave _loopStartTrailIndex unchanged so this crossing re-evaluates
      // on the next fix once the 60-second wall-clock threshold passes.
      final elapsedSec =
          start == null ? -1 : DateTime.now().difference(start).inSeconds;
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.session_elapsed_gate',
        error: 'rejected: elapsed=${elapsedSec}s floor=$_minSessionElapsedSec',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      onGateRejected?.call(GateRejectionReason.sessionElapsed, {'elapsed_sec': elapsedSec});
      return;
    }

    // Advance index BEFORE dispatching the claim so a fast second fix
    // does not re-fire the same crossing.
    _loopStartTrailIndex = _track.length;

    final cb = onAutoClaim;
    if (cb != null) {
      // Fire-and-forget; exceptions are swallowed here so a failed claim
      // does not crash the GPS recording loop. The provider layer catches
      // errors and surfaces them via _autoClaimOutcomeController.
      cb(polygon).catchError((_) {});
    }
  }

  /// Opens the GPS position stream and stores the subscription in [_posSub].
  /// Extracted so both [startRun] and [resumeFromScratch] share the same
  /// subscription setup without duplicating code.
  void _openGpsStream() {
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25, // skip updates when device hasn't moved 25 m+
      ),
    ).listen(_onPosition, onError: (_) {});
  }

  /// Scratch-table key used for the CURRENT fix. During a simulation this is
  /// a namespaced key derived from the real user id (never the raw uid), so
  /// simulated scratch rows can never be picked up by [resumeFromScratch],
  /// which is always called with the real, unprefixed uid. Outside a
  /// simulation this is just [_activeUserId].
  String? _scratchUserId() {
    final uid = _activeUserId;
    if (uid == null) return null;
    return _simActive ? 'sim:$uid' : uid;
  }

  /// Starts a tester-only simulated replay session. This is the ONLY entry
  /// point into simulation mode and it enforces the position-source
  /// isolation guarantee: any real GPS subscription is cancelled and nulled
  /// out BEFORE recorder state is reset and BEFORE the caller can possibly
  /// feed a single synthetic fix, so a real sensor fix can never land in
  /// _track while a simulation is active.
  ///
  /// Does not start the foreground service/notification a real run uses -
  /// a simulation is a short, foreground-only diagnostic the operator
  /// watches live. If the app is backgrounded mid-simulation, the Dart timer
  /// driving fix emission may be throttled or paused by the OS; it never
  /// falls back to opening the real GPS stream, it simply advances slower
  /// or stalls until the app is foregrounded again.
  ///
  /// Pre: state == idle; no simulation already active.
  /// Post: real _posSub is null; _track is empty; a fresh _currentSessionId
  ///       has been minted; state == recording; isSimulationActive == true.
  ///
  /// Returns false when refused (a real run is already recording, or a
  /// simulation is already active) instead of failing silently - the caller
  /// must be able to tell the difference between "started" and "refused" so
  /// the UI layer can surface it rather than leaving the operator staring at
  /// a picker sheet that does nothing.
  Future<bool> beginSimulation() async {
    final alreadyRecording = stateNotifier.value == RecorderState.recording;
    if (alreadyRecording || _simActive) {
      ErrorLogService.logClientError(
        provider: 'beginSimulation.recording_guard',
        error: 'refused: ${_simActive ? 'a simulation is already active' : 'a real run is already recording'}',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      return false;
    }
    await _posSub?.cancel();
    _posSub = null;
    assert(_posSub == null,
        'real GPS subscription must be closed before a simulation starts');
    _simActive = true;
    _clearTrackInternal();
    _loopStartTrailIndex = 0;
    _sessionStartTime = DateTime.now();
    _startedAt = DateTime.now().toUtc();
    trackVersion.value++;
    _currentSessionId = _uuid.v4();
    // Clear any leftover scratch from a previous simulation under the same
    // namespaced key - mirrors startRun()'s clear of real scratch rows.
    final scratchUid = _scratchUserId();
    if (scratchUid != null) {
      try {
        await RunScratchStore.instance.deleteForUser(scratchUid);
      } catch (_) {}
    }
    final sid = _currentSessionId!;
    final uid = _activeUserId;
    final cb = onRunUpdate;
    if (cb != null && uid != null) {
      cb(sid, {
        'id': sid,
        'user_id': uid,
        'city': activeCity,
        'started_at': _startedAt!.toIso8601String(),
        'status': 'active',
        // Marks the row as replay output, mirroring the forced is_mocked on
        // simulated gps_samples. Excludes it from leaderboards and analytics.
        'is_simulated': true,
      }).catchError((_) {});
    }
    stateNotifier.value = RecorderState.recording;
    return true;
  }

  /// Feeds one synthetic fixture-derived fix through the exact same
  /// _onPosition pipeline a real GPS fix goes through (spacing filter,
  /// proximity fast path, auto-claim scan). No-op unless a simulation is
  /// active, so this can never be misused to inject a fix into a real run
  /// or after a simulation has already ended.
  void injectSimulatedFix(Position pos) {
    if (!_simActive) return;
    _onPosition(pos);
  }

  /// Plays [events] into the simulation one at a time, preserving each
  /// event's original relative spacing (scaled by [multiplier]) so
  /// animations stay visually intelligible instead of jumping instantly.
  /// `claim_rejected` and `run_start` entries are historical context only
  /// and are never replayed as commands. A `user_stop_pressed` entry ends
  /// the simulation through the exact same finalize path a real Stop tap
  /// uses ([stopRun]). Every scheduled emission is owned by [_simTimer],
  /// the simulation's own subscription handle - never [_posSub] - so
  /// cancelling one can never be confused with cancelling the other.
  ///
  /// The returned future completes once the fixture is exhausted or the
  /// simulation ends early (stop/cancel/abort from any caller).
  ///
  /// Pre: beginSimulation() has already been called and completed.
  Future<void> runSimulationSequence(
    List<SimulationFixEvent> events, {
    double multiplier = kSimulationAccelerationMultiplier,
  }) {
    final completer = Completer<void>();
    var index = 0;

    void step() {
      if (!_simActive || index >= events.length) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final delayMs = index == 0
          ? 0
          : _simDelayMs(events[index - 1].t, events[index].t, multiplier);
      _simTimer = Timer(Duration(milliseconds: delayMs), () {
        if (!_simActive) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        _applySimulationEvent(events[index]);
        index++;
        step();
      });
    }

    step();
    return completer.future;
  }

  void _applySimulationEvent(SimulationFixEvent event) {
    switch (event.type) {
      case 'gps_fix':
        final data = event.data;
        _onPosition(Position(
          latitude: (data['lat'] as num).toDouble(),
          longitude: (data['lng'] as num).toDouble(),
          timestamp: event.t,
          accuracy: 5.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: (data['speed_ms'] as num?)?.toDouble() ?? 0.0,
          speedAccuracy: 0.0,
          // Forced true regardless of the fixture's own recorded value -
          // every fix a simulation feeds into the pipeline is synthetic.
          isMocked: true,
        ));
        break;
      case 'user_stop_pressed':
        // Fire-and-forget: this exercises the full stop/finalize path
        // exactly as a real Stop tap would, including the runs-row
        // completion write. stopRun() sets _simActive = false
        // synchronously before its first await, so the sequence loop
        // observes the end on the very next step.
        unawaited(stopRun());
        break;
      default:
        // run_start and claim_rejected are historical record only.
        break;
    }
  }

  /// Milliseconds to wait before emitting the fix at [next], given the
  /// fixture's own timestamp for the [prev] fix, scaled by [multiplier] and
  /// clamped to a sane on-screen-watchable range.
  static int _simDelayMs(DateTime prev, DateTime next, double multiplier) {
    final rawMs = next.difference(prev).inMilliseconds;
    final scaledMs = rawMs <= 0 ? 0 : (rawMs / multiplier).round();
    return scaledMs.clamp(kSimulationMinFixDelayMs, kSimulationMaxFixDelayMs);
  }

  /// Aborts the active simulation immediately: cancels the fix-emission
  /// timer, discards the in-progress synthetic track without dispatching
  /// any pending claim, and returns the recorder to idle via the same
  /// terminal-status write path [cancelRun] already uses for a real
  /// aborted run.
  Future<void> abortSimulation() async {
    if (!_simActive) return;
    _simTimer?.cancel();
    _simTimer = null;
    await cancelRun();
  }

  /// Rehydrates [_track] from run_scratch rows for [userId], then restarts
  /// the foreground service and GPS subscription.
  ///
  /// Pre: state == idle; [_activeUserId] is set; run_scratch has rows for [userId].
  /// Post: _track.length == row count; foreground service is running.
  Future<void> resumeFromScratch(String userId) async {
    if (stateNotifier.value == RecorderState.recording) return;
    try {
      final rows = await RunScratchStore.instance.getPoints(userId);
      if (rows.isEmpty) return;
      _track.clear();
      DateTime? earliest;
      // Read the durable session_id from the first scratch row (all rows share
      // the same session_id since they were written in the same run).
      final String? durableSessionId =
          rows.first['session_id'] as String?;
      for (final row in rows) {
        final lat = row['lat'] as double;
        final lng = row['lng'] as double;
        _track.add(LatLng(lat, lng));
        final tsStr = row['ts'] as String?;
        if (tsStr != null && earliest == null) {
          earliest = DateTime.tryParse(tsStr)?.toUtc();
        }
      }
      // Use the earliest scratch timestamp so elapsed time carries over.
      _startedAt = earliest ?? DateTime.now().toUtc();
      _closedAt = null;
      _loopStartTrailIndex = 0;
      // Wall-clock session start reconstructed from earliest sample so the
      // 60-second gate behaves correctly across kill+resume.
      _sessionStartTime = earliest?.toLocal() ?? DateTime.now();
      trackVersion.value++;

      // Restore durable session_id or mint a fresh one for legacy null rows.
      _currentSessionId = durableSessionId ?? _uuid.v4();

      // Always re-send the full stub runs row, regardless of whether the
      // session_id was already durable. writeRunUpdate is an idempotent
      // upsert (onConflict: 'id'), so re-sending id/user_id/city/started_at/
      // status here is safe even when the row already exists server-side,
      // and it guarantees started_at is present if a later partial update
      // (e.g. a confirmClaim or stopRun field merge) ever lands as a fresh
      // INSERT instead of an UPDATE - which would otherwise violate the
      // runs.started_at NOT NULL constraint.
      final runCb = onRunUpdate;
      if (runCb != null) {
        final sid = _currentSessionId!;
        runCb(sid, {
          'id': sid,
          'user_id': userId,
          'city': activeCity,
          'started_at': _startedAt!.toIso8601String(),
          'status': 'active',
        }).catchError((_) {});
      }

      // Replay all scratch rows into gps_samples outbox so they reach
      // the server even if they were not streamed before the crash.
      // The unique index (session_id, ts, user_id) deduplicates server-side.
      final gpsCb = onGpsFix;
      if (gpsCb != null) {
        final sid = _currentSessionId!;
        for (final row in rows) {
          final ts = row['ts'] as String?;
          if (ts == null) continue;
          gpsCb({
            'run_id': sid,
            'session_id': sid,
            'user_id': userId,
            'lat': row['lat'] as double,
            'lng': row['lng'] as double,
            'ts': ts,
            'speed_ms': 0.0,
            // Legacy scratch rows written before the is_mocked column existed
            // have no value here — default to false only in that case.
            'is_mocked': (row['is_mocked'] as int?) == 1,
          }).catchError((_) {});
        }
      }

      // Iterative re-scan for missed intersections during background.
      await _rescanRehydratedTrack();

      await _startForegroundTask();
      _openGpsStream();
      stateNotifier.value = RecorderState.recording;
    } catch (e, st) {
      ErrorLogService.logClientError(
        provider: 'resumeFromScratch', error: e, stackTrace: st, retryCount: 0,
      );
    }
  }

  /// Iterates _track from index 0, calling detectSelfIntersection at each
  /// position. Each successful claim advances _loopStartTrailIndex past the
  /// matched crossing and continues. Failed claims advance silently.
  Future<void> _rescanRehydratedTrack() async {
    for (int len = 2; len <= _track.length; len++) {
      final partial = _track.sublist(0, len);
      final scanStart = math.max(1, _loopStartTrailIndex);
      final hit = detectSelfIntersection(partial, scanStart);
      if (hit == null) continue;
      final polygon = computeCapture(
        partial,
        scanStart,
        hit.intersectingSegmentIdx,
        hit.intersectionPoint,
        len - 1,
      );
      final areaSqm = polygonArea(polygon) * 1e6;
      if (areaSqm < _minCapturedAreaSqm) {
        _loopStartTrailIndex = len;
        continue;
      }
      final diagonalM = polygonBboxDiagonalM(polygon);
      if (diagonalM < _minCapturedAreaDiagonalM) {
        _loopStartTrailIndex = len;
        continue;
      }
      // 60-second gate at the timestamp of partial.last (approximate via
      // _sessionStartTime, which was set above from the earliest scratch ts).
      final start = _sessionStartTime;
      if (start == null ||
          DateTime.now().difference(start).inSeconds < _minSessionElapsedSec) {
        // Edge: scratch was rehydrated very fast after start. Skip - the
        // crossing will re-fire from live GPS once 60 s elapses.
        continue;
      }
      _loopStartTrailIndex = len;
      final cb = onAutoClaim;
      if (cb != null) {
        // Run sequentially so concurrent zones never collide; await blocks
        // the rescan loop but the session is still in `idle` UI-wise.
        try {
          await cb(polygon);
        } catch (_) {}
      }
    }
  }

  /// Deletes all run_scratch rows for [userId] without affecting [_track],
  /// the foreground service, or state.
  Future<void> clearScratch(String userId) async {
    try {
      await RunScratchStore.instance.deleteForUser(userId);
    } catch (_) {}
  }

  void _clearTrackInternal() {
    _track.clear();
    _startedAt = null;
    _closedAt = null;
    _sessionStartTime = null;
    trackVersion.value++;
  }

  // ── Test-only seams ──────────────────────────────────────────────────────────

  @visibleForTesting
  static RunRecorderService instanceForTesting() => RunRecorderService._();

  @visibleForTesting
  void injectSessionStartTime(DateTime t) => _sessionStartTime = t;

  @visibleForTesting
  void injectState(RecorderState s) {
    stateNotifier.value = s;
    // When injecting recording state for tests, mint a session ID if absent.
    if (s == RecorderState.recording && _currentSessionId == null) {
      _currentSessionId = _uuid.v4();
    }
  }

  @visibleForTesting
  void injectTrackForTesting(List<LatLng> pts) {
    _track
      ..clear()
      ..addAll(pts);
  }

  @visibleForTesting
  void runScanForAutoClaimForTesting() => _scanForAutoClaim();

  @visibleForTesting
  int get loopStartTrailIndexForTesting => _loopStartTrailIndex;

  @visibleForTesting
  void handlePositionForTesting(Position p) => _onPosition(p);

  @visibleForTesting
  int get trackLengthForTesting => _track.length;

  @visibleForTesting
  void reset() {
    _loopStartTrailIndex = 0;
    _sessionStartTime = null;
    _currentSessionId = null;
    _simActive = false;
    _simTimer?.cancel();
    _simTimer = null;
    _track.clear();
    activeCity = '';
    stateNotifier.value = RecorderState.idle;
    onAutoClaim = null;
    onGateRejected = null;
    onGpsFix = null;
    onRunUpdate = null;
  }
}

/// Equirectangular distance in metres between two LatLng points.
/// Uses the same cos-lat projection as polygonArea in lasso.dart so the
/// spacing threshold scales consistently with the area floor.
/// Mirrors the copy in lasso.dart; duplication is intentional (design.md §C).
double _equirectangularDistanceM(LatLng a, LatLng b) {
  const double latM = 110540.0;
  final double lngM = 111320.0 * math.cos((a.latitude + b.latitude) / 2 * (math.pi / 180.0));
  final double dy = (b.latitude - a.latitude) * latM;
  final double dx = (b.longitude - a.longitude) * lngM;
  return math.sqrt(dx * dx + dy * dy);
}
