import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'database_service.dart';
import 'realtime_presence_service.dart';
import 'telemetry_service.dart';
import 'daily_missions_service.dart';

enum RecorderState { idle, recording, awaitingClaim }

enum LoopResult { valid, invalid, notRecording }

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

  void setActiveUser(String? userId) => _activeUserId = userId;

  List<LatLng> get track => List.unmodifiable(_track);
  List<LatLng> get trackSnapshot => List.unmodifiable(_track);
  DateTime? get startedAt => _startedAt;
  DateTime? get closedAt => _closedAt;

  static const double _minPerimeterM = 200;
  static const double _maxReturnGapM = 250;
  static const int _minElapsedSec = 60;
  static const double _earthRadiusM = 6371008.8;

  Future<void> startRun() async {
    if (stateNotifier.value == RecorderState.recording) return;
    _track.clear();
    _startedAt = DateTime.now().toUtc();
    _closedAt = null;
    trackVersion.value++;
    // Clear any leftover scratch points from a previous run.
    final uid = _activeUserId;
    if (uid != null) {
      try {
        DatabaseService.instance.deleteScratchRun(uid);
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
    _track.add(LatLng(pos.latitude, pos.longitude));
    RealtimePresenceService.instance.updatePosition(LatLng(pos.latitude, pos.longitude));
    trackVersion.value++;
    // Persist point to scratch table for crash/process-kill recovery.
    final uid = _activeUserId;
    if (uid != null) {
      try {
        DatabaseService.instance.insertScratchPoint(
          uid,
          pos.latitude,
          pos.longitude,
          pos.accuracy,
          pos.timestamp.toIso8601String(),
        );
      } catch (_) {}
    }
  }

  Future<void> _startForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'runwar_run_tracking',
        channelName: 'Run Tracking',
        channelDescription: 'RunWar is recording your route.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
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
    await FlutterForegroundTask.startService(
      serviceId: 100,
      notificationTitle: 'Run in progress',
      notificationText: '00:00',
    );
    // Update the notification body with elapsed time every 30 s (AC-4).
    // The timer runs on the main isolate so it can read _startedAt directly.
    _notifTimer?.cancel();
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final started = _startedAt;
      if (started == null || stateNotifier.value != RecorderState.recording) {
        return;
      }
      final elapsed = DateTime.now().toUtc().difference(started);
      final mm = elapsed.inMinutes.toString().padLeft(2, '0');
      final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      unawaited(FlutterForegroundTask.updateService(
        notificationTitle: 'Run in progress',
        notificationText: '$mm:$ss',
      ));
    });
  }

  Future<LoopResult> stopRun() async {
    final s = stateNotifier.value;
    if (s == RecorderState.idle || s == RecorderState.awaitingClaim) {
      return LoopResult.notRecording;
    }
    _notifTimer?.cancel();
    _notifTimer = null;
    await _posSub?.cancel();
    _posSub = null;
    RealtimePresenceService.instance.setRecording(false);
    unawaited(FlutterForegroundTask.stopService());
    _closedAt = DateTime.now().toUtc();

    final perimeter = _trackPerimeter();
    final returnGap = _track.length >= 2
        ? _haversine(_track.first, _track.last)
        : double.infinity;
    final elapsed = (_startedAt == null)
        ? 0
        : _closedAt!.difference(_startedAt!).inSeconds;

    final valid = perimeter >= _minPerimeterM &&
        returnGap <= _maxReturnGapM &&
        elapsed > _minElapsedSec;

    if (valid) {
      stateNotifier.value = RecorderState.awaitingClaim;
      TelemetryService.instance.logEvent('valid_loop', props: {'perimeter_m': perimeter.round()}).catchError((_) {});
      final uid = _activeUserId;
      if (uid != null) {
        DailyMissionsService.instance.reportProgress(uid, 'walk_2km', perimeter.round()).catchError((_) {});
        DailyMissionsService.instance.reportProgress(uid, 'back_to_back', 1).catchError((_) {});
      }
      // Scratch cleared only after successful claim (in confirmClaim via discardRun).
      return LoopResult.valid;
    }
    // Invalid loop — clear scratch immediately.
    final uid = _activeUserId;
    if (uid != null) {
      try {
        DatabaseService.instance.deleteScratchRun(uid);
      } catch (_) {}
    }
    _clearTrackInternal();
    stateNotifier.value = RecorderState.idle;
    return LoopResult.invalid;
  }

  /// Force-close — bypasses loop-closure thresholds.
  void forceClose() {
    if (stateNotifier.value != RecorderState.recording) return;
    _posSub?.cancel();
    _posSub = null;
    _closedAt = DateTime.now().toUtc();
    stateNotifier.value = RecorderState.awaitingClaim;
  }

  /// Discard current run and reset to idle.
  void discardRun() {
    _notifTimer?.cancel();
    _notifTimer = null;
    _posSub?.cancel();
    _posSub = null;
    RealtimePresenceService.instance.setRecording(false);
    unawaited(FlutterForegroundTask.stopService());
    final uid = _activeUserId;
    if (uid != null) {
      try {
        DatabaseService.instance.deleteScratchRun(uid);
      } catch (_) {}
    }
    _clearTrackInternal();
    stateNotifier.value = RecorderState.idle;
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
  /// the foreground service and GPS subscription (AC-13).
  ///
  /// Pre: state == idle; [_activeUserId] is set; run_scratch has rows for [userId].
  /// Post: _track.length == row count; foreground service is running.
  Future<void> resumeFromScratch(String userId) async {
    if (stateNotifier.value == RecorderState.recording) return;
    try {
      final rows = DatabaseService.instance.getScratchRun(userId);
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
      trackVersion.value++;
      await _startForegroundTask();
      _openGpsStream();
      stateNotifier.value = RecorderState.recording;
    } catch (_) {}
  }

  /// Deletes all run_scratch rows for [userId] without affecting [_track],
  /// the foreground service, or state (AC-14, and used internally by discardRun).
  Future<void> clearScratch(String userId) async {
    try {
      DatabaseService.instance.deleteScratchRun(userId);
    } catch (_) {}
  }

  void _clearTrackInternal() {
    _track.clear();
    _startedAt = null;
    _closedAt = null;
    trackVersion.value++;
  }

  double _trackPerimeter() {
    if (_track.length < 2) return 0;
    var sum = 0.0;
    for (var i = 0; i < _track.length - 1; i++) {
      sum += _haversine(_track[i], _track[i + 1]);
    }
    return sum;
  }

  double _haversine(LatLng a, LatLng b) {
    final p1 = a.latitude * math.pi / 180.0;
    final p2 = b.latitude * math.pi / 180.0;
    final dp = (b.latitude - a.latitude) * math.pi / 180.0;
    final dl = (b.longitude - a.longitude) * math.pi / 180.0;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }
}
