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
        trackDistanceM,
        minRingBoundaryDistanceM;
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

  // Monotonically increasing counter bumped on every beginSimulation() call,
  // regardless of how the PREVIOUS simulation ended (stopRun, cancelRun,
  // abortSimulation, or not ended at all before a new one starts). A
  // listener that caches the last value it saw can detect "a new simulation
  // has begun" unconditionally, without depending on any particular end path
  // having fired a matching signal first. See SPEC-0144 map_screen.dart
  // _lastSimulationGeneration for the consumer.
  int _simulationGeneration = 0;

  /// Generation counter for simulated replays. Bumped on every
  /// [beginSimulation] call. Callers that need to detect "a new simulation
  /// has started" should compare this against a cached value rather than
  /// relying on [isSimulationActive] edges, which can be missed when a
  /// simulation ends via [stopRun] (no [trackVersion] bump on end).
  int get simulationGeneration => _simulationGeneration;

  @visibleForTesting
  bool get hasRealGpsSubscriptionForTesting => _posSub != null;

  // Expose session ID so the provider layer can wire lasso_id + zone_id writes.
  String? get currentSessionId => _currentSessionId;

  // Segment-index spans [startSegIdx, endSegIdx] (inclusive) already
  // consumed by a DISPATCHED claim this session (live, drain, owned-wall,
  // or rehydration rescan). Replaces the old scan-floor advancement
  // (_loopStartTrailIndex): the self-intersection scan always runs over the
  // full trail history now (scan start is the constant 1), and a detected
  // closure is checked against these spans by the consumed-span dedup gate
  // in _scanForAutoClaim rather than by truncating what the scan can see.
  // Cleared to empty everywhere a new session begins or ends - the same
  // lifecycle points the old floor field had.
  final List<List<int>> _consumedSpans = <List<int>>[];

  // Highest end index across every consumed span, or 0 when nothing has
  // been consumed yet this session. Used as the owned-zone-wall capture
  // anchor (see _scanForAutoClaim), mirroring the old "capture the
  // unconsumed corridor" semantics of the floor field it replaces.
  int get _maxConsumedEndIdx {
    int maxEnd = 0;
    for (final span in _consumedSpans) {
      if (span[1] > maxEnd) maxEnd = span[1];
    }
    return maxEnd;
  }

  // Counts segments s in [i..k] that fall outside every span currently in
  // _consumedSpans. Backs the consumed-span dedup gate: a detected closure
  // is only claimable when this count is at least kMinNewLoopTrailSegments.
  int _newSegmentsOutsideConsumed(int i, int k) {
    int count = 0;
    for (int s = i; s <= k; s++) {
      bool inConsumed = false;
      for (final span in _consumedSpans) {
        if (s >= span[0] && s <= span[1]) {
          inConsumed = true;
          break;
        }
      }
      if (!inConsumed) count++;
    }
    return count;
  }

  // Groups a freshly, atomically-computed batch of newly-closed loop
  // polygons from THIS run by mutual proximity, using the same 25 m seal
  // radius (kProximityTriggerM) already used server-side to merge a new
  // claim with pre-existing adjacent territory. A plain union-find over
  // pairwise minRingBoundaryDistanceM: transitive (A-B close, B-C close, A-C
  // far still end up in one group via B), same contract as
  // merge_geometry.ts's computeZoneMerges grouping step. This function only
  // DECIDES which polygons belong together - the actual sealed union
  // geometry is always computed server-side (unionCandidateRings), never
  // here.
  //
  // Callers must pass a batch collected and grouped in one synchronous pass,
  // never assembled incrementally across awaited gaps - see the doc comment
  // on _drainDeferredCrossings and _rescanRehydratedTrack's dispatch step for
  // why this matters (a stale, previously-read snapshot can silently drop a
  // sibling loop from its group).
  List<List<List<LatLng>>> _groupPolygonsByProximity(
      List<List<LatLng>> polygons) {
    final n = polygons.length;
    if (n <= 1) return polygons.map((p) => [p]).toList();
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (minRingBoundaryDistanceM(polygons[i], polygons[j]) <=
            kProximityTriggerM) {
          union(i, j);
        }
      }
    }

    final groups = <int, List<List<LatLng>>>{};
    for (int i = 0; i < n; i++) {
      groups.putIfAbsent(find(i), () => []).add(polygons[i]);
    }
    return groups.values.toList();
  }

  // Wall-clock moment of the FAB Start tap. Used as the claim-interval
  // gate's reference point for the FIRST claim of a session (0-to-claim).
  // Persists across multiple auto-claims within the same session.
  DateTime? _sessionStartTime;

  // Timestamp of the most recently DISPATCHED auto-claim (a crossing that
  // cleared every gate and was handed to onAutoClaim), on the same clock
  // domain as _lastFixTimestamp below. Null until the first claim of a
  // session. Used as the claim-interval gate's reference point for every
  // claim AFTER the first (claim-to-claim). This service only ever learns
  // that a crossing cleared its own gates and was dispatched - whether the
  // server subsequently confirmed or rejected the claim is decided in
  // run_recorder_provider.dart's confirmClaim, which this service does not
  // see, so "claim" here means "gate-cleared dispatch", not
  // server-confirmed. Reset alongside _sessionStartTime everywhere a new
  // session begins (startRun, beginSimulation, resumeFromScratch) or ends
  // (stopRun, cancelRun, _clearTrackInternal) so a stale timestamp from a
  // prior session can never leak into the next one.
  DateTime? _lastClaimAt;

  // Timestamp of the most recent fix admitted into the pipeline. For a real
  // run this is the device fix time (same wall-clock domain as
  // DateTime.now(), differing only by fix latency). For a simulation this is
  // the fixture's own recorded time, already stamped on every synthetic
  // Position by _applySimulationEvent. Null until the first fix of a
  // session. SPEC-0143.
  DateTime? _lastFixTimestamp;

  // Crossings that cleared all four geometric gates and failed ONLY the
  // session-elapsed gate. Retained for later dispatch. Session-scoped; never
  // carried across sessions. Capped at kMaxDeferredCrossings, FIFO.
  // SPEC-0143.
  final List<_DeferredCrossing> _deferredCrossings = <_DeferredCrossing>[];

  // Number of times the clock-domain guard rejected an implausible elapsed
  // value and fell back to DateTime.now(). Session-scoped, reset with the
  // session. A correct simulation must leave this at 0. SPEC-0143.
  int _clockGuardTrips = 0;

  // Callback invoked when an auto-claim should fire. Set by the provider
  // during construction; the service does not import the provider layer.
  //
  // Takes a LIST of one-or-more captured polygons, never a single polygon:
  // when a run self-closes multiple loops that fall within the existing
  // kProximityTriggerM seal-merge radius of EACH OTHER, they are grouped by
  // [_groupPolygonsByProximity] and dispatched together as ONE claim so the
  // server can union them into a single contiguous shape (merge_geometry.ts
  // unionCandidateRings), instead of being submitted as N independent
  // claims/zone rows. The live single-hit scan path only ever detects one
  // loop per call, so it always dispatches a list of exactly one - this is
  // not a behaviour change for that path, only a signature change.
  Future<void> Function(List<List<LatLng>> capturedPolygons)? onAutoClaim;

  // Callback invoked when an auto-claim scan silently rejects a detected loop
  // closure at the area-floor or session-elapsed gate. Set by the provider
  // during construction, same pattern as onAutoClaim.
  Future<void> Function(GateRejectionReason reason, Map<String, dynamic> details)?
      onGateRejected;

  // Callback invoked for each spacing-filtered GPS fix so the provider layer
  // can stream it to gps_samples via OutboxAwareWriter without this service
  // importing connectivity or Riverpod.
  Future<void> Function(Map<String, dynamic> sample)? onGpsFix;

  // Supplies a fresh snapshot of the runner's own owned-zone outlines (one
  // entry per outline, closed ring, same city as the active run) at the
  // moment _scanForAutoClaim asks for it. Set by the provider layer at
  // run-start, same push-don't-pull pattern as onAutoClaim/onGpsFix - this
  // service never imports zonesProvider or any Riverpod type itself.
  // Left unset by default: the scan then treats "no owned-zone data" exactly
  // as it did before this field existed (regression safety net).
  List<List<LatLng>> Function()? ownedZoneEdgesProvider;

  // Callback invoked when the runs row needs a partial update (stop/cancel/
  // confirmClaim lasso link). Arguments: sessionId, field map.
  Future<void> Function(String sessionId, Map<String, dynamic> fields)? onRunUpdate;

  // Area floor for auto-claim. Below this, a captured loop is silently
  // discarded (no claim dispatched, onGateRejected fires with areaFloor).
  //
  // Must stay numerically equal to the server-side floor in
  // supabase/functions/claim_territory/handler.ts (minCapturedAreaSqm) - the
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

  // Minimum interval (seconds) between two auto-claims in the same session:
  // claim-to-claim after the first claim, or 0-to-claim (session start) for
  // the first claim. Was previously a single "total session elapsed since
  // start" floor of 60 s (checked against _sessionStartTime only, never
  // updated per claim); it is now a per-claim interval floor of 30 s,
  // checked against whichever is more recent - the last dispatched claim, or
  // session start if there has not been one yet. See _lastClaimAt above.
  static const int _minClaimIntervalSec = 30;

  // Effective shape-gate enforcement for THIS service instance. Defaults to
  // kEnforceShapeGates (runwar_constants.dart), the single source of truth
  // for shipped behaviour - production code never sets this field, so
  // production always reflects the constant. It exists as a field, rather
  // than reading the constant directly at both call sites, purely so a test
  // can exercise the ON branch (see debugSetEnforceShapeGates below)
  // without a second const-flipped build - Dart cannot branch a single test
  // run on two different values of the same compile-time constant.
  bool _enforceShapeGates = kEnforceShapeGates;

  @visibleForTesting
  void debugSetEnforceShapeGates(bool value) => _enforceShapeGates = value;

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
    _consumedSpans.clear();
    _sessionStartTime = DateTime.now();
    _lastFixTimestamp = null;
    _deferredCrossings.clear();
    _clockGuardTrips = 0;
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
    // Clock source for the session-elapsed gate. Captured after the
    // validity guards above so a NaN/infinite/low-accuracy fix can never
    // poison the session clock, and only when the stamp is itself
    // plausible: an epoch-zero or negative stamp is a broken OS/platform
    // value, and keeping the previous good stamp is strictly better than
    // adopting it. SPEC-0143.
    if (pos.timestamp.millisecondsSinceEpoch > 0) {
      _lastFixTimestamp = pos.timestamp;
    }
    final newLatLng = LatLng(pos.latitude, pos.longitude);
    // Always update presence so rival comets stay live regardless of spacing
    // filter - except during a simulation, where the position is synthetic
    // and must never be broadcast to other players as if it were a real
    // runner moving through the city.
    if (!_simActive) {
      RealtimePresenceService.instance.updatePosition(newLatLng);
    }
    // Proximity pre-check: if raw fix is within kProximityTriggerM of any
    // prior stored vertex (from the very first stored vertex onward - full
    // history, no scan floor), bypass the spacing filter so the closing fix
    // is stored and _scanForAutoClaim can detect the closure.
    if (_track.length > 1) {
      for (int i = 0; i < _track.length; i++) {
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

            // Stream this fix to gps_samples too, same as the spacing-filter
            // path below. Without this, every fix that takes the proximity
            // shortcut - which is exactly the set of fixes that can trigger
            // an auto-claim scan - never reaches the server, leaving the
            // persisted track unable to reconstruct what the recorder
            // actually evaluated. This branch always returns before falling
            // through to the spacing-filter path, so a given fix is streamed
            // from exactly one of the two call sites, never both.
            //
            // The server write always uses the real, unprefixed
            // _activeUserId - never the namespaced scratchUid above, which
            // exists only to keep simulated scratch rows out of
            // resumeFromScratch.
            final uid = _activeUserId;
            final sid = _currentSessionId;
            final gpsCb = onGpsFix;
            if (uid != null && gpsCb != null && sid != null) {
              gpsCb({
                'run_id': sid,
                'session_id': sid,
                'user_id': uid,
                'lat': pos.latitude,
                'lng': pos.longitude,
                'ts': pos.timestamp.toIso8601String(),
                'speed_ms': pos.speed,
                // Matches the spacing-filter path's write-time guarantee:
                // every row written during a simulation is forced true
                // regardless of the fixture's own recorded value.
                'is_mocked': _simActive ? true : pos.isMocked,
              }).catchError((e, st) {
                // Fire-and-forget stays non-blocking - the GPS loop must
                // never stall on a write failure - but the failure is now
                // observable instead of silently disappearing.
                ErrorLogService.logClientError(
                  provider: 'run_recorder_service.onGpsFix.proximity',
                  error: e,
                  stackTrace: st,
                  retryCount: 0,
                );
              });
            }
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
    _consumedSpans.clear();
    _sessionStartTime = null;
    _lastClaimAt = null;
    _lastFixTimestamp = null;
    _deferredCrossings.clear();
    _clockGuardTrips = 0;
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
    _consumedSpans.clear();
    _sessionStartTime = null;
    _lastClaimAt = null;
    _lastFixTimestamp = null;
    _deferredCrossings.clear();
    _clockGuardTrips = 0;
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
    _drainDeferredCrossings();
    // Full-history scan: scan start is the constant 1 (the lower bound
    // detectSelfIntersection itself requires), never a floor derived from
    // prior claims. Earlier trail history is never hidden from the scan -
    // a big loop that closes against segments from before an earlier
    // dispatched claim must still be detectable. Duplicate/near-duplicate
    // re-crossings of already-claimed ground are filtered below by the
    // consumed-span dedup gate instead of by truncating the scan.
    final ownedZoneEdges = ownedZoneEdgesProvider?.call() ?? const [];
    final hit = detectSelfIntersection(
      _track,
      1,
      ownedZoneEdges: ownedZoneEdges,
    );
    if (hit == null) return;

    final k = _track.length - 1;
    // An owned-zone-wall hit has no earlier trail segment to anchor to (see
    // lasso.dart's -1 sentinel doc comment); computeCapture's anchor is the
    // highest end index across every consumed span, plus one, or 0 when
    // nothing has been consumed yet (not _maxConsumedEndIdx + 1 == 1 in that
    // case), so the captured polygon covers the WHOLE unconsumed corridor
    // run so far - starting at trail index 0, same as the very first run
    // through this path today - rather than re-including ground an earlier
    // dispatched claim already covers.
    final captureAnchorIdx = hit.isOwnedZoneWall
        ? (_consumedSpans.isEmpty ? 0 : _maxConsumedEndIdx + 1)
        : hit.intersectingSegmentIdx;
    final polygon = computeCapture(
      _track,
      1,
      captureAnchorIdx,
      hit.intersectionPoint,
      k,
      isProximityClosure: hit.isProximityClosure,
    );

    final areaSqm = polygonArea(polygon) * 1e6;

    // Consumed-span dedup gate, checked BEFORE the area floor: a detected
    // closure is only claimable when at least kMinNewLoopTrailSegments of
    // its candidate span [captureAnchorIdx..k] lie outside every span
    // already consumed by a dispatched claim this session. This is what
    // lets a genuinely new loop that shares corridor with claimed ground
    // through (the big-loop case the scan-floor removal above exists for)
    // while blocking a near-duplicate re-crossing of a loop already
    // claimed. Silent: no onGateRejected call (this is not a gate the UI
    // needs to explain to the runner - it is jitter/re-crossing noise, not
    // a legitimate attempt that fell short), and nothing is consumed.
    final newSegs = _newSegmentsOutsideConsumed(captureAnchorIdx, k);
    if (newSegs < kMinNewLoopTrailSegments) {
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.consumed_span_dedup',
        error: 'rejected: span=($captureAnchorIdx,$k) newSegs=$newSegs '
            'area=${areaSqm.toStringAsFixed(1)}sqm',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      return;
    }

    // Area floor (m^2). polygonArea returns km^2 -> convert.
    if (areaSqm < _minCapturedAreaSqm) {
      // Consume nothing here. A below-floor result only means the newest
      // edge did not close a big-enough loop yet - it does not mean the
      // trail history is invalid. Nothing is added to _consumedSpans, so
      // the segments this closure covers stay available for a later,
      // genuinely large loop to close against.
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.area_floor_gate',
        error: 'rejected: area=${areaSqm.toStringAsFixed(1)}sqm floor=$_minCapturedAreaSqm',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      onGateRejected?.call(GateRejectionReason.areaFloor, {'area_sqm': areaSqm});
      return;
    }

    // Shape gates (diagonal, compactness, path-length) are gated behind
    // kEnforceShapeGates, default OFF - the operator wants a claim gated on
    // the area floor only for now, so a loop that legitimately extends an
    // owned zone but is a thin wedge on its own is no longer rejected before
    // it ever reaches the merge step. The three checks and their reasoning
    // comments are kept in full, not deleted, so flipping the flag back on
    // in runwar_constants.dart is a one-line, fully reversible change. Must
    // stay numerically and behaviourally identical to kEnforceShapeGates in
    // supabase/functions/claim_territory/handler.ts.
    if (_enforceShapeGates) {
      // Bounding-box diagonal floor. Rejects a thin sliver that clears the
      // area floor only because it is long and narrow, not because it
      // encloses a real block-scale loop. Same as the area-floor branch
      // above: rejection here consumes nothing, so the trail history stays
      // available for a later, genuinely large loop to close against.
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
      // rectangle about 0.19, a needle near zero. Same as the branches
      // above: rejection here consumes nothing.
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
    }

    // Claim-interval gate: at least _minClaimIntervalSec must have elapsed
    // since the reference point below before this claim may dispatch.
    // Reference is the last DISPATCHED claim this session (claim-to-claim),
    // or session start if there has not been one yet (0-to-claim, first
    // claim of the session). See _lastClaimAt's doc comment above.
    final start = _lastClaimAt ?? _sessionStartTime;
    final elapsedSec = start == null ? -1 : _elapsedSecForGate(start);
    if (start == null || elapsedSec < _minClaimIntervalSec) {
      // Do NOT add this span to _consumedSpans, and do NOT discard this
      // crossing. The geometric gate(s) above have already passed; the only
      // thing missing is elapsed time. The polygon is retained in
      // _deferredCrossings and re-dispatched by _drainDeferredCrossings() on
      // a later fix once the threshold passes. That retention is what makes
      // the crossing recoverable: detectSelfIntersection only ever tests
      // the NEWEST segment against history (lasso.dart), so once the trail
      // advances past this point the same segment pair is never evaluated
      // again and the crossing could not re-fire on its own.
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.session_elapsed_gate',
        error: 'rejected: elapsed=${elapsedSec}s floor=$_minClaimIntervalSec',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      _retainDeferredCrossing(polygon, k, hit.intersectingSegmentIdx, elapsedSec);
      onGateRejected?.call(GateRejectionReason.sessionElapsed, {'elapsed_sec': elapsedSec});
      return;
    }

    // Consume this claim's span BEFORE dispatching so a fast second fix
    // cannot re-fire the same crossing (the consumed-span dedup gate above
    // checks candidate spans against this list). Deferred crossings are
    // intentionally left in place rather than cleared here: with a
    // full-history scan a live claim's span no longer necessarily contains
    // every earlier deferred entry's span, so each deferred entry is
    // re-checked against the updated consumed spans at drain time instead
    // of being unconditionally discarded on every live dispatch.
    _consumedSpans.add([captureAnchorIdx, k]);
    // Record this claim as the new claim-interval reference point for the
    // NEXT auto-claim in this session. Same fix-preferred-else-wall-clock
    // domain as _elapsedSecForGate, so the next comparison stays on one
    // consistent timeline.
    _lastClaimAt = _lastFixTimestamp ?? DateTime.now().toUtc();

    final cb = onAutoClaim;
    if (cb != null) {
      // Fire-and-forget; exceptions are swallowed here so a failed claim
      // does not crash the GPS recording loop. The provider layer catches
      // errors and surfaces them via _autoClaimOutcomeController. This scan
      // only ever detects one loop per call, so it always dispatches a
      // single-member group - grouping across sibling loops happens in the
      // batch paths (_drainDeferredCrossings, _rescanRehydratedTrack).
      cb([polygon]).catchError((_) {});
    }
  }

  /// Seconds elapsed since [start], measured on the clock domain of the fix
  /// currently under evaluation. Returns the wall-clock value as a fallback
  /// whenever the fix-derived value is not trustworthy.
  ///
  /// Both operands are normalised with toUtc() so a local-dated
  /// _sessionStartTime (startRun, resumeFromScratch) and a UTC-dated fix
  /// stamp are compared on one absolute timeline rather than by accident.
  ///
  /// The guard is the defence against the primary failure mode of this
  /// change: if _sessionStartTime were left wall-clock-dated while the fix
  /// stamp is fixture-dated, the subtraction would produce several DAYS and
  /// the gate would pass unconditionally while appearing healthy. Falling
  /// back to DateTime.now() in that case produces a near-zero elapsed and
  /// therefore a REJECTION, so the failure is loud and conservative instead
  /// of silent and permissive. SPEC-0143.
  int _elapsedSecForGate(DateTime start) {
    final fixTs = _lastFixTimestamp;
    if (fixTs != null) {
      final candidate = fixTs.toUtc().difference(start.toUtc()).inSeconds;
      if (candidate >= 0 && candidate <= kMaxPlausibleSessionElapsedSec) {
        return candidate;
      }
      _clockGuardTrips++;
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.clock_domain_guard',
        error: 'implausible elapsed=${candidate}s '
            'fix=${fixTs.toIso8601String()} start=${start.toIso8601String()} '
            'sim=$_simActive - falling back to wall clock',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
    }
    return DateTime.now().toUtc().difference(start.toUtc()).inSeconds;
  }

  /// Retains a crossing that cleared all four geometric gates and failed
  /// only the session-elapsed gate, so it can be dispatched later by
  /// [_drainDeferredCrossings] once genuinely enough time has elapsed.
  /// SPEC-0143.
  void _retainDeferredCrossing(
      List<LatLng> polygon, int k, int intersectingSegmentIdx, int elapsedSec) {
    if (polygon.length < 3) return; // cannot be claimed; nothing to retain
    final identity = '$intersectingSegmentIdx:$k';
    for (final d in _deferredCrossings) {
      if (d.identity == identity) return; // already pending, do not duplicate
    }
    if (_deferredCrossings.length >= kMaxDeferredCrossings) {
      _deferredCrossings.removeAt(0); // FIFO: drop the oldest
      ErrorLogService.logClientError(
        provider: '_scanForAutoClaim.deferred_overflow',
        error: 'deferred crossing buffer full at $kMaxDeferredCrossings, '
            'oldest dropped',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
    }
    _deferredCrossings.add(_DeferredCrossing(
      polygon: List<LatLng>.unmodifiable(polygon),
      detectedAtTrailIndex: k,
      intersectingSegmentIdx: intersectingSegmentIdx,
      detectedAtElapsedSec: elapsedSec,
    ));
  }

  /// Dispatches every retained session-elapsed-only rejection whose
  /// threshold has now passed. At most once per crossing. SPEC-0143.
  void _drainDeferredCrossings() {
    if (_deferredCrossings.isEmpty) return;
    final start = _lastClaimAt ?? _sessionStartTime;
    if (start == null) {
      _deferredCrossings.clear(); // no session: nothing may claim
      return;
    }
    if (_elapsedSecForGate(start) < _minClaimIntervalSec) return;

    // Detach BEFORE dispatching. onAutoClaim is provider code that can run
    // synchronously up to its first await; if it re-entered _scanForAutoClaim
    // it must not see these entries again.
    final pending = List<_DeferredCrossing>.of(_deferredCrossings);
    _deferredCrossings.clear();

    // Collected freshly, in this one synchronous pass, before any dispatch
    // fires - never assembled across an awaited gap. Grouping this batch by
    // proximity BEFORE dispatch (rather than firing one independent
    // fire-and-forget request per entry, as before) is what actually
    // eliminates the race that used to defeat server-side merging here: two
    // fire-and-forget requests issued back-to-back could each read the
    // database before the other's insert committed, so neither ever saw the
    // other's zone row to merge against. Grouping sibling loops into ONE
    // request removes that race entirely - there is no second in-flight
    // request left to race against.
    final toDispatch = <List<LatLng>>[];

    for (final d in pending) {
      if (d.dispatched) continue; // second guard, belt and braces
      d.dispatched = true;
      if (d.polygon.length < 3) continue;
      // Re-check the consumed-span dedup gate against the CURRENT
      // _consumedSpans, not the spans in effect when this entry was
      // retained: a live claim dispatched while this entry sat deferred may
      // have consumed ground that now makes it a near-duplicate.
      final newSegs = _newSegmentsOutsideConsumed(
          d.intersectingSegmentIdx, d.detectedAtTrailIndex);
      if (newSegs < kMinNewLoopTrailSegments) {
        ErrorLogService.logClientError(
          provider: '_scanForAutoClaim.consumed_span_dedup',
          error: 'drain: skip dup span=(${d.intersectingSegmentIdx},'
              '${d.detectedAtTrailIndex}) newSegs=$newSegs',
          stackTrace: StackTrace.current,
          retryCount: 0,
        );
        continue;
      }
      // Consume the trail span this polygon covers, mirroring the live
      // path's "consume before dispatch" rule.
      _consumedSpans.add([d.intersectingSegmentIdx, d.detectedAtTrailIndex]);
      toDispatch.add(d.polygon);
    }

    if (toDispatch.isNotEmpty) {
      final groups = _groupPolygonsByProximity(toDispatch);
      for (final group in groups) {
        onAutoClaim?.call(group).catchError((_) {});
      }
    }
    // Record the drain as the new claim-interval reference point, same as
    // the live dispatch path. The whole batch is gated by one check above
    // (pre-existing design: the batch either all clears the floor together
    // or none of it does), so one reference update after the batch mirrors
    // that same granularity rather than inventing a new per-item interval
    // this method never enforced even under the old session-elapsed gate.
    if (pending.isNotEmpty) {
      _lastClaimAt = _lastFixTimestamp ?? DateTime.now().toUtc();
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
  ///
  /// [simulatedSessionStart], when provided, seeds the session-elapsed
  /// gate's reference point from the FIXTURE's own timeline instead of wall
  /// clock, so the gate and every synthetic fix's timestamp share one clock
  /// domain. It is unreachable from any real-run path: startRun() is a
  /// separate method and never calls beginSimulation(). SPEC-0143.
  Future<bool> beginSimulation({DateTime? simulatedSessionStart}) async {
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
    _simulationGeneration++;
    _clearTrackInternal();
    _consumedSpans.clear();
    _sessionStartTime = simulatedSessionStart ?? DateTime.now();
    // _startedAt stays wall-clock-dated even when _sessionStartTime becomes
    // fixture-dated. _startedAt feeds runs.started_at, stopRun's
    // ended_at/finalized_at and the foreground notification elapsed
    // counter. A runs row dated days in the past (from a fixture's own
    // timeline) would misrepresent when the replay actually ran and could
    // fall outside server-side time windows. Deliberate divergence -
    // SPEC-0143 design.md section 1. Do not "fix" this.
    _startedAt = DateTime.now().toUtc();
    _lastFixTimestamp = null;
    _deferredCrossings.clear();
    _clockGuardTrips = 0;
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
      _consumedSpans.clear();
      // Wall-clock session start reconstructed from earliest sample so the
      // claim-interval gate's 0-to-claim reference behaves correctly across
      // kill+resume. This is a resumed session, not a new one, but the
      // resumed process has no memory of any claim that may have already
      // dispatched before the kill, so _lastClaimAt resets to null here and
      // the interval falls back to this reconstructed session start until a
      // claim actually dispatches within the resumed process.
      _sessionStartTime = earliest?.toLocal() ?? DateTime.now();
      _lastClaimAt = null;
      _lastFixTimestamp = null;
      _deferredCrossings.clear();
      _clockGuardTrips = 0;
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
  /// position with a full-history scan (scan start is the constant 1) and
  /// the same consumed-span dedup-then-area-floor ordering _scanForAutoClaim
  /// uses. Each dispatched claim adds its span to _consumedSpans and
  /// continues; a rejected candidate (dedup, area, or shape) consumes
  /// nothing and continues - prefix iteration over an ever-growing `partial`
  /// already guarantees this loop makes forward progress without needing a
  /// floor advance of its own.
  Future<void> _rescanRehydratedTrack() async {
    // Collected across the whole rescan pass, dispatched only once the loop
    // finishes: every span-consumption / dedup-gate / claim-interval
    // bookkeeping step below still runs synchronously and in order exactly
    // as before (none of it depends on a dispatch's return value), so
    // deferring the actual onAutoClaim call to the end changes nothing about
    // which loops get consumed or when - it only lets sibling loops closed
    // during THIS SAME rescan be grouped by proximity and submitted as one
    // claim instead of N independent ones, mirroring the live-session batch
    // path in _drainDeferredCrossings.
    final rescannedLoops = <List<LatLng>>[];
    for (int len = 2; len <= _track.length; len++) {
      final partial = _track.sublist(0, len);
      final ownedZoneEdges = ownedZoneEdgesProvider?.call() ?? const [];
      final hit = detectSelfIntersection(
        partial,
        1,
        ownedZoneEdges: ownedZoneEdges,
      );
      if (hit == null) continue;
      // Mirrors _scanForAutoClaim's anchor choice: an owned-zone-wall hit has
      // no earlier trail segment to anchor to (intersectingSegmentIdx is the
      // -1 sentinel), so the highest consumed end index (plus one), or 0
      // when nothing has been consumed yet, is used instead.
      final captureAnchorIdx = hit.isOwnedZoneWall
          ? (_consumedSpans.isEmpty ? 0 : _maxConsumedEndIdx + 1)
          : hit.intersectingSegmentIdx;
      final polygon = computeCapture(
        partial,
        1,
        captureAnchorIdx,
        hit.intersectionPoint,
        len - 1,
      );
      final areaSqm = polygonArea(polygon) * 1e6;

      // Consumed-span dedup gate, checked before the area floor - same
      // ordering and same rule as the live path in _scanForAutoClaim.
      final newSegs = _newSegmentsOutsideConsumed(captureAnchorIdx, len - 1);
      if (newSegs < kMinNewLoopTrailSegments) continue;

      if (areaSqm < _minCapturedAreaSqm) {
        continue;
      }
      // F1 (SPEC-0143 design.md): the rescan path must apply the same shape
      // gates the live path applies, so a "deferred" crossing provably means
      // "cleared the same gates" on every path, not just the live one.
      // Gated behind kEnforceShapeGates exactly like the live path in
      // _scanForAutoClaim - see the comment there. Without this guard, a
      // thin sliver the live path now accepts could still be rejected here
      // after an app-kill-and-resume, which would make the two paths
      // disagree on the same polygon.
      if (_enforceShapeGates) {
        final diagonalM = polygonBboxDiagonalM(polygon);
        if (diagonalM < _minCapturedAreaDiagonalM) {
          continue;
        }
        final compactness = diagonalM > 0 ? areaSqm / (diagonalM * diagonalM) : 0.0;
        if (compactness < kMinCapturedAreaCompactness) {
          continue;
        }
        final loopPathM = trackDistanceM(polygon);
        if (loopPathM < kMinCapturedPathLengthM) {
          continue;
        }
      }
      // Claim-interval gate at the timestamp of partial.last (approximate
      // via _lastClaimAt, or _sessionStartTime for the first claim - set
      // above from the earliest scratch ts). This path stays wall-clock
      // (finding F2 in design.md): scratch ts values are real device
      // wall-clock stamps on the same absolute timeline as DateTime.now(),
      // so there is no mixed-domain comparison here to repair.
      final start = _lastClaimAt ?? _sessionStartTime;
      if (start == null ||
          DateTime.now().difference(start).inSeconds < _minClaimIntervalSec) {
        // The geometric gate(s) passed and only elapsed time is missing.
        // Retain the polygon so it dispatches from _drainDeferredCrossings
        // on the first live fix after the threshold passes. Nothing is
        // consumed here: the polygon is already captured, and consuming its
        // span now (before it has actually dispatched) would make the
        // dedup gate reject it right back out at drain time.
        _retainDeferredCrossing(polygon, len - 1, hit.intersectingSegmentIdx, -1);
        continue;
      }
      _consumedSpans.add([captureAnchorIdx, len - 1]);
      // Record this claim as the new claim-interval reference point, same
      // as the live dispatch path.
      _lastClaimAt = DateTime.now().toUtc();
      rescannedLoops.add(polygon);
    }

    if (rescannedLoops.isEmpty) return;
    final cb = onAutoClaim;
    if (cb == null) return;
    final groups = _groupPolygonsByProximity(rescannedLoops);
    for (final group in groups) {
      // Run sequentially so concurrent zones never collide; await blocks
      // the rescan loop but the session is still in `idle` UI-wise.
      try {
        await cb(group);
      } catch (_) {}
    }
  }

  /// Test-only direct access to the sibling-loop proximity grouping
  /// decision, without needing to drive a real GPS self-intersection scan
  /// end to end. Same union-find/25m-threshold algorithm the drain and
  /// rescan batch paths use internally.
  @visibleForTesting
  List<List<List<LatLng>>> groupPolygonsByProximityForTesting(
          List<List<LatLng>> polygons) =>
      _groupPolygonsByProximity(polygons);

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
    _lastClaimAt = null;
    _lastFixTimestamp = null;
    _deferredCrossings.clear();
    _clockGuardTrips = 0;
    trackVersion.value++;
  }

  // ── Test-only seams ──────────────────────────────────────────────────────────

  @visibleForTesting
  static RunRecorderService instanceForTesting() => RunRecorderService._();

  @visibleForTesting
  void injectSessionStartTime(DateTime t) => _sessionStartTime = t;

  @visibleForTesting
  void injectLastClaimAt(DateTime? t) => _lastClaimAt = t;

  @visibleForTesting
  DateTime? get lastClaimAtForTesting => _lastClaimAt;

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
  List<List<int>> get consumedSpansForTesting =>
      _consumedSpans.map((s) => List<int>.of(s)).toList();

  @visibleForTesting
  void handlePositionForTesting(Position p) => _onPosition(p);

  @visibleForTesting
  int get trackLengthForTesting => _track.length;

  // RED-phase test seams for SPEC-0143 (design.md section 5.6). Each seam
  // exposes state or a code path the fix will populate; none of them run
  // any new gate/retry/drain logic themselves.
  @visibleForTesting
  void injectLastFixTimestamp(DateTime? t) => _lastFixTimestamp = t;

  @visibleForTesting
  DateTime? get sessionStartTimeForTesting => _sessionStartTime;

  @visibleForTesting
  int get deferredCrossingCountForTesting => _deferredCrossings.length;

  @visibleForTesting
  int get clockGuardTripsForTesting => _clockGuardTrips;

  @visibleForTesting
  Future<void> rescanRehydratedTrackForTesting() => _rescanRehydratedTrack();

  @visibleForTesting
  void reset() {
    _consumedSpans.clear();
    _sessionStartTime = null;
    _lastClaimAt = null;
    _enforceShapeGates = kEnforceShapeGates;
    _currentSessionId = null;
    _simActive = false;
    _simulationGeneration = 0;
    _simTimer?.cancel();
    _simTimer = null;
    _track.clear();
    activeCity = '';
    stateNotifier.value = RecorderState.idle;
    onAutoClaim = null;
    onGateRejected = null;
    onGpsFix = null;
    onRunUpdate = null;
    ownedZoneEdgesProvider = null;
    _lastFixTimestamp = null;
    _deferredCrossings.clear();
    _clockGuardTrips = 0;
  }
}

/// RED-phase data-only placeholder for SPEC-0143's deferred-crossing value
/// type (design.md section 2.2). Holds a snapshot only; no code path
/// constructs or consumes an instance until the fix lands.
class _DeferredCrossing {
  _DeferredCrossing({
    required this.polygon,
    required this.detectedAtTrailIndex,
    required this.intersectingSegmentIdx,
    required this.detectedAtElapsedSec,
  });

  final List<LatLng> polygon;
  final int detectedAtTrailIndex;
  final int intersectingSegmentIdx;
  final int detectedAtElapsedSec;
  bool dispatched = false;

  String get identity => '$intersectingSegmentIdx:$detectedAtTrailIndex';
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
