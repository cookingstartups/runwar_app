import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'error_log_service.dart';
import 'realtime_presence_service.dart';
import 'run_scratch_store.dart';
import 'telemetry_service.dart';
import '../geo/lasso.dart' show detectSelfIntersection, computeCapture, polygonArea;
import '../utils/runwar_constants.dart';

enum RecorderState { idle, recording }

class RunRecorderService {
  RunRecorderService._();
  static final RunRecorderService instance = RunRecorderService._();

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

  // Lower bound for the self-intersection scan. Set to 0 at startRun,
  // advanced to _track.length after each successful or area-rejected claim.
  int _loopStartTrailIndex = 0;

  // Wall-clock moment of the FAB Start tap. Used for the 60-second gate.
  // Persists across multiple auto-claims within the same session.
  DateTime? _sessionStartTime;

  // Callback invoked when an auto-claim should fire. Set by the provider
  // during construction; the service does not import the provider layer.
  Future<void> Function(List<LatLng> capturedPolygon)? onAutoClaim;

  // Area floor for auto-claim. Below this, GPS jitter micro-loops are
  // silently discarded.
  static const double _minCapturedAreaSqm = 200.0;

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
  static const String kNotificationChannelImportance = 'high';

  void setActiveUser(String? userId) => _activeUserId = userId;

  List<LatLng> get track => List.unmodifiable(_track);
  List<LatLng> get trackSnapshot => List.unmodifiable(_track);
  DateTime? get startedAt => _startedAt;
  DateTime? get closedAt => _closedAt;

  Future<void> startRun() async {
    if (stateNotifier.value == RecorderState.recording) return;
    _clearTrackInternal();
    _startedAt = DateTime.now().toUtc();
    _closedAt = null;
    _loopStartTrailIndex = 0;
    _sessionStartTime = DateTime.now();
    trackVersion.value++;
    // Clear any leftover scratch points from a previous run.
    final uid = _activeUserId;
    if (uid != null) {
      try {
        await RunScratchStore.instance.deleteForUser(uid);
      } catch (_) {}
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
    final newLatLng = LatLng(pos.latitude, pos.longitude);
    // Always update presence so rival comets stay live regardless of spacing filter.
    RealtimePresenceService.instance.updatePosition(newLatLng);
    // Proximity pre-check: if raw fix is within kProximityTriggerM of any prior
    // stored vertex (from _loopStartTrailIndex onward), bypass the spacing filter
    // so the closing fix is stored and _scanForAutoClaim can detect the closure.
    if (_track.length > 1) {
      final scanFrom = math.max(0, _loopStartTrailIndex);
      for (int i = scanFrom; i < _track.length; i++) {
        if (_equirectangularDistanceM(_track[i], newLatLng) < kProximityTriggerM) {
          _track.add(newLatLng);
          trackVersion.value++;
          final uid = _activeUserId;
          if (uid != null) {
            // Intentional: closing fix may be closer than kTrackPointSpacingM; invariant relaxed only at loop closure
            RunScratchStore.instance.insertPoint(
              uid, pos.latitude, pos.longitude,
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
    // Persist point to scratch table for crash/process-kill recovery.
    final uid = _activeUserId;
    if (uid != null) {
      RunScratchStore.instance.insertPoint(
        uid,
        pos.latitude,
        pos.longitude,
        accuracy: pos.accuracy,
        ts: pos.timestamp.toIso8601String(),
      ).catchError((_) {});
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
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
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
    _notifTimer?.cancel();
    _notifTimer = null;
    await _posSub?.cancel();
    _posSub = null;
    RealtimePresenceService.instance.setRecording(false);
    unawaited(FlutterForegroundTask.stopService());
    _closedAt = DateTime.now().toUtc();
    // Track is retained in memory in case an in-flight onAutoClaim future
    // is still using it. _clearTrackInternal runs on the NEXT startRun().
    // Scratch is cleared here so a future resumeFromScratch on a
    // killed-app path does not re-hydrate this finished session.
    final uid = _activeUserId;
    if (uid != null) {
      try {
        await RunScratchStore.instance.deleteForUser(uid);
      } catch (_) {}
    }
    _loopStartTrailIndex = 0;
    _sessionStartTime = null;
    stateNotifier.value = RecorderState.idle;
    TelemetryService.instance.logEvent('stop_run').catchError((_) {});
  }

  /// Discards the current track and idles the recorder WITHOUT claiming.
  /// Triggered by FAB long-press while recording.
  ///
  /// Pre: state == recording (no-op otherwise).
  /// Post: state == idle; track cleared; presence untracked; GPS stream closed;
  ///       scratch table cleared.
  Future<void> cancelRun() async {
    if (stateNotifier.value != RecorderState.recording) return;
    _notifTimer?.cancel();
    _notifTimer = null;
    await _posSub?.cancel();
    _posSub = null;
    RealtimePresenceService.instance.setRecording(false);
    unawaited(FlutterForegroundTask.stopService());
    final uid = _activeUserId;
    if (uid != null) {
      try {
        await RunScratchStore.instance.deleteForUser(uid);
      } catch (_) {}
    }
    _clearTrackInternal();
    _loopStartTrailIndex = 0;
    _sessionStartTime = null;
    stateNotifier.value = RecorderState.idle;
    TelemetryService.instance.logEvent('cancel_run').catchError((_) {});
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
    );

    // Area floor (m^2). polygonArea returns km^2 -> convert.
    final areaSqm = polygonArea(polygon) * 1e6;
    if (areaSqm < _minCapturedAreaSqm) {
      _loopStartTrailIndex = _track.length; // skip this crossing forever
      return;
    }

    // 60-second gate (per session, not per loop).
    final start = _sessionStartTime;
    if (start == null ||
        DateTime.now().difference(start).inSeconds < _minSessionElapsedSec) {
      // Leave _loopStartTrailIndex unchanged so this crossing re-evaluates
      // on the next fix once the 60-second wall-clock threshold passes.
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
  void injectState(RecorderState s) => stateNotifier.value = s;

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
    _track.clear();
    stateNotifier.value = RecorderState.idle;
    onAutoClaim = null;
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
