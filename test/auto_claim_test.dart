import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:runwar_app/geo/lasso.dart';
import 'package:runwar_app/services/run_recorder_service.dart';
import 'package:runwar_app/services/realtime_presence_service.dart';

// ---------------------------------------------------------------------------
// Helpers - geometry factories
//
// All coordinates are in the Limassol area (34.x N, 33.x E) - small lat/lng
// steps are used so the planar approximation in lasso.dart stays valid.
// ---------------------------------------------------------------------------

// A straight 4-point path with no crossing.
List<LatLng> _straightPath() => [
      const LatLng(34.700, 33.000),
      const LatLng(34.701, 33.001),
      const LatLng(34.702, 33.002),
      const LatLng(34.703, 33.003),
    ];

// A figure-8 path that produces a self-intersection.
// Walk: A -> B -> C -> D -> E where the segment D->E crosses segment A->B.
//
//   A(34.700, 33.000) -- B(34.701, 33.001)
//                               |
//                        C(34.700, 33.001)
//                               |
//   E(34.701, 33.000) ----------+  (crosses A->B somewhere in between)
//
// Concrete numeric construction:
//   A = (0.00, 0.00)   B = (0.00, 0.02)
//   C = (0.02, 0.02)   D = (0.02, 0.00)
//   E = (0.00, 0.01)   <- heading back toward AB
//
// Using a base offset of (34.700, 33.000), scale = 0.01 degrees.
//
// Segment AB: (34.700, 33.000) -> (34.700, 33.020)  [horizontal, lat=34.700]
// Segment DE: (34.720, 33.000) -> (34.700, 33.010)  [diagonal going SW]
//
// This guarantees that the segment D->E properly crosses the segment A->B
// at roughly (34.700, 33.005).
List<LatLng> _figure8Path() => [
      // index 0: A
      const LatLng(34.700, 33.000),
      // index 1: B - end of first segment
      const LatLng(34.700, 33.020),
      // index 2: C - turn
      const LatLng(34.720, 33.020),
      // index 3: D - turn
      const LatLng(34.720, 33.000),
      // index 4: E - this segment (D->E) crosses segment A->B
      const LatLng(34.700, 33.010),
    ];

// A tiny triangle with area well below 200 m^2.
// Side ~0.0001 degrees ~ 11 metres -> area ~ 60 m^2.
List<LatLng> _microPolygon() => [
      const LatLng(34.700000, 33.000000),
      const LatLng(34.700100, 33.000000),
      const LatLng(34.700100, 33.000100),
    ];

// A large square polygon: ~500 m side -> area ~250 000 m^2.
// Each 0.01 degree of lat ~ 1105 m; of lng at 34 N ~ 921 m.
// We use 0.005 deg lat x 0.005 deg lng -> ~553 m x ~461 m -> ~255 000 m^2.
List<LatLng> _largePolygon() => [
      const LatLng(34.700, 33.000),
      const LatLng(34.705, 33.000),
      const LatLng(34.705, 33.005),
      const LatLng(34.700, 33.005),
    ];

// ---------------------------------------------------------------------------
// Fake RealtimePresenceService used for presence-gate tests.
// We cannot easily instantiate the singleton; instead we test the service's
// internal _isRecording flag indirectly via the exposed setRecording / timer.
// ---------------------------------------------------------------------------

// Track calls to channel.track/untrack via a simple log.
class _PresenceCallLog {
  final List<String> calls = [];
  void track() => calls.add('track');
  void untrack() => calls.add('untrack');
  void clear() => calls.clear();
}

// ---------------------------------------------------------------------------
// Stub for the onAutoClaim callback injected into RunRecorderService.
// Records which polygon was received.
// ---------------------------------------------------------------------------

class _AutoClaimCapture {
  final List<List<LatLng>> captured = [];
  bool shouldThrow = false;
  bool shouldFail = false;

  Future<void> call(List<LatLng> polygon) async {
    captured.add(polygon);
    if (shouldThrow) throw Exception('network error');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Group 1: Lasso geometry unit tests
  // These test lasso.dart functions directly - no service involvement.
  // =========================================================================

  group('lasso geometry - detectSelfIntersection', () {
    // GIVEN a straight 4-point path with no segment crossings
    // WHEN detectSelfIntersection is called on the full path
    // THEN it returns null (no crossing found)
    test('returns null for a straight path with no crossing', () {
      final path = _straightPath();
      // loopStartTrailIndex must be >= 1 for the algorithm to scan
      final result = detectSelfIntersection(path, 1);
      expect(result, isNull,
          reason: 'A straight non-crossing path must not produce an intersection');
    });

    // GIVEN a figure-8 path where the last segment crosses an earlier segment
    // WHEN detectSelfIntersection is called with loopStartTrailIndex = 1
    // THEN it returns a non-null SelfIntersection with an intersection point
    test('returns intersection point for a figure-8 crossing path', () {
      final path = _figure8Path();
      final result = detectSelfIntersection(path, 1);
      expect(result, isNotNull,
          reason: 'The last segment D->E must cross segment A->B in the figure-8 path');
      expect(result!.intersectionPoint, isA<LatLng>());
      expect(result.intersectingSegmentIdx, greaterThan(0));
    });

    // GIVEN a figure-8 path with a known self-intersection
    // WHEN computeCapture is called with the intersection result
    // THEN the returned polygon starts at the intersection point and contains >= 3 points
    test('computeCapture returns a closed polygon for a self-intersecting path', () {
      final path = _figure8Path();
      final hit = detectSelfIntersection(path, 1);
      expect(hit, isNotNull,
          reason: 'Precondition: figure-8 path must have an intersection');

      final k = path.length - 1;
      final polygon = computeCapture(
        path,
        1,
        hit!.intersectingSegmentIdx,
        hit.intersectionPoint,
        k,
      );

      expect(polygon.length, greaterThanOrEqualTo(3),
          reason: 'Captured polygon must have at least 3 vertices');
      expect(polygon.first, equals(hit.intersectionPoint),
          reason: 'Polygon must start at the intersection point');
    });
  });

  group('lasso geometry - polygonArea', () {
    // GIVEN a large square polygon with sides ~500 m
    // WHEN polygonArea is called (returns km^2; multiply by 1e6 for m^2)
    // THEN the area in m^2 is >= 200.0
    test('returns area >= 200 m^2 for a valid large lasso polygon', () {
      final poly = _largePolygon();
      final areaSqm = polygonArea(poly) * 1e6;
      expect(areaSqm, greaterThanOrEqualTo(200.0),
          reason: 'Large square polygon must exceed the 200 m^2 auto-claim floor');
    });

    // GIVEN a micro polygon with side ~11 m
    // WHEN polygonArea is called
    // THEN the area in m^2 is < 200.0
    test('returns area < 200 m^2 for a GPS-jitter micro-polygon', () {
      final poly = _microPolygon();
      final areaSqm = polygonArea(poly) * 1e6;
      expect(areaSqm, lessThan(200.0),
          reason: 'Micro-polygon must fall below the 200 m^2 floor');
    });
  });

  // =========================================================================
  // Group 2: Session time gate
  //
  // These tests exercise RunRecorderService._scanForAutoClaim indirectly
  // through the onAutoClaim callback. They test that the 60-second gate
  // suppresses auto-claim in the first minute of a session.
  //
  // After implementation, RunRecorderService will expose:
  //   - DateTime? _sessionStartTime (set at startRun)
  //   - int _loopStartTrailIndex
  //   - Future<void> Function(List<LatLng>)? onAutoClaim
  //   - void injectTrackAndScan(List<LatLng> points) [test-only escape hatch
  //     OR the test drives _onPosition via a stream injection seam]
  //
  // Since the service currently has none of these, ALL tests in this group
  // compile against the NEW API from design.md. They will fail with
  // "getter/method not found" until the implementation is merged.
  // =========================================================================

  group('session time gate - auto-claim suppressed within 60 seconds', () {
    late RunRecorderService svc;
    late _AutoClaimCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _AutoClaimCapture();
      svc.onAutoClaim = capture.call;
    });

    tearDown(() {
      svc.reset();
    });

    // GIVEN the recorder has been in recording state for fewer than 60 seconds
    //   AND detectSelfIntersection returns a non-null result with area >= 200 m^2
    // WHEN the auto-claim handler evaluates the session elapsed time
    // THEN no claim is triggered and no polygon is captured
    test('auto-claim does not fire when lasso closes within 60 seconds of session start', () {
      // Inject a session start time 30 seconds ago - within the 60-second window
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 30)));
      svc.injectState(RecorderState.recording);

      // Feed the figure-8 path to trigger a self-intersection
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();

      expect(capture.captured, isEmpty,
          reason: 'No claim should fire when session has been running for only 30 seconds');
    });

    // GIVEN the recorder has been in recording state for more than 60 seconds
    //   AND detectSelfIntersection returns a non-null result with area >= 200 m^2
    // WHEN the auto-claim handler evaluates the session elapsed time
    // THEN the claim fires and the captured polygon is passed to onAutoClaim
    test('auto-claim fires when lasso closes after 60 seconds of session start', () async {
      // Inject a session start time 90 seconds ago - past the 60-second window
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);

      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();

      // Give the fire-and-forget future a microtask to settle
      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, hasLength(1),
          reason: 'Claim should fire when 90 seconds have elapsed since session start');
    });
  });

  // =========================================================================
  // Group 3: Area floor gate
  // =========================================================================

  group('area floor gate - 200 m^2 minimum', () {
    late RunRecorderService svc;
    late _AutoClaimCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _AutoClaimCapture();
      svc.onAutoClaim = capture.call;
      // Start well past the 60-second gate
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    // GIVEN a captured polygon whose area is < 200 m^2
    // WHEN the auto-claim handler evaluates the area
    // THEN no claim is triggered
    test('auto-claim does not fire for a captured polygon with area below 200 m^2', () async {
      // Build a micro-loop path (tiny triangle) that produces a near-zero polygon.
      // We inject it directly via the track seam.
      // The intersection is faked by using a known crossing micro-path.
      // Because the polygon area is < 200, the claim must be suppressed.
      final microPath = _buildMicroCrossPath();
      svc.injectTrackForTesting(microPath);
      svc.runScanForAutoClaimForTesting();

      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, isEmpty,
          reason: 'Micro-loop with area < 200 m^2 must not trigger an auto-claim');
    });

    // GIVEN a captured polygon whose area is >= 200 m^2
    // WHEN the auto-claim handler evaluates the area
    // THEN the claim fires with the captured polygon
    test('auto-claim fires for a captured polygon with area >= 200 m^2', () async {
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();

      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, hasLength(1),
          reason: 'Large lasso (>= 200 m^2) must trigger an auto-claim');
      expect(capture.captured.first.length, greaterThanOrEqualTo(3));
    });
  });

  // =========================================================================
  // Group 4: Multi-lasso per session
  // =========================================================================

  group('multi-lasso - two lassoes in one session claim independently', () {
    late RunRecorderService svc;
    late _AutoClaimCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _AutoClaimCapture();
      svc.onAutoClaim = capture.call;
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    // GIVEN two sequential self-intersections in one recording session
    //   AND _loopStartTrailIndex advances after the first claim
    // WHEN the second intersection is detected
    // THEN a second separate claim is dispatched and loopStartTrailIndex advances again
    test('two self-intersections in one session each trigger a separate claim', () async {
      // First intersection
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      final indexAfterFirst = svc.loopStartTrailIndexForTesting;

      // Second intersection: extend the trail with another crossing loop
      svc.injectTrackForTesting(_figure8PathExtended());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, hasLength(2),
          reason: 'Two qualifying intersections must produce two separate claims');
    });

    // GIVEN the first claim has advanced _loopStartTrailIndex to T1
    // WHEN a second intersection is detected at T2 > T1
    // THEN _loopStartTrailIndex advances from T1 to T2 after the second claim
    test('loopStartTrailIndex advances after each claim', () async {
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      final indexAfterFirst = svc.loopStartTrailIndexForTesting;
      expect(indexAfterFirst, greaterThan(0),
          reason: 'Index must advance after the first claim');

      svc.injectTrackForTesting(_figure8PathExtended());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      final indexAfterSecond = svc.loopStartTrailIndexForTesting;
      expect(indexAfterSecond, greaterThan(indexAfterFirst),
          reason: 'Index must advance again after the second claim');
    });
  });

  // =========================================================================
  // Group 5: Presence visibility gate
  //
  // Tests that the realtime presence service only broadcasts when recording
  // is active. These test the NEW behaviour from design.md section C where
  // setRecording(false) calls _untrackSafely() and the timer is gated.
  //
  // We test RealtimePresenceService via its public API: setRecording(bool).
  // The service is a singleton so we use a testing reset seam.
  // =========================================================================

  group('presence visibility - gated to recording window', () {
    late RealtimePresenceService presenceSvc;

    setUp(() {
      presenceSvc = RealtimePresenceService.instanceForTesting();
    });

    tearDown(() {
      presenceSvc.resetForTesting();
    });

    // GIVEN the recorder is in idle state (setRecording has not been called)
    // WHEN the presence broadcast timer ticks
    // THEN no track() call is emitted to the channel
    test('rivals do not receive position broadcast before Start is pressed', () {
      // The service starts with _isRecording == false.
      // Verify the timer body guard is in place by checking isRecordingForTesting.
      expect(presenceSvc.isRecordingForTesting, isFalse,
          reason: 'Presence must start in non-recording state');
    });

    // GIVEN setRecording(true) has been called (Start pressed)
    // WHEN the presence broadcast timer ticks
    // THEN the service is in recording state and would emit track()
    test('rivals receive position broadcast after Start is pressed', () {
      presenceSvc.setRecording(true);

      expect(presenceSvc.isRecordingForTesting, isTrue,
          reason: 'Presence must enter recording state after setRecording(true)');
    });

    // GIVEN setRecording(true) was called and then setRecording(false) is called (End pressed)
    // WHEN the presence broadcast timer ticks
    // THEN the service is in non-recording state AND untrackCalled is true
    test('rivals stop receiving position after End is pressed', () {
      presenceSvc.setRecording(true);
      presenceSvc.setRecording(false);

      expect(presenceSvc.isRecordingForTesting, isFalse,
          reason: 'Presence must exit recording state after setRecording(false)');
      expect(presenceSvc.untrackCalledForTesting, isTrue,
          reason: 'untrack() must be called when recording transitions from true to false');
    });
  });

  // =========================================================================
  // Group 6: Failed claim recovery
  // =========================================================================

  group('failed claim recovery - session stays alive', () {
    late RunRecorderService svc;
    late _AutoClaimCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _AutoClaimCapture();
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    // GIVEN a valid auto-claim is triggered
    //   AND the onAutoClaim callback throws a network exception
    // WHEN the scan completes
    // THEN the recorder state remains recording (does not transition to idle)
    test('failed auto-claim does not end the recording session', () async {
      capture.shouldThrow = true;
      svc.onAutoClaim = capture.call;

      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(svc.stateNotifier.value, equals(RecorderState.recording),
          reason: 'A thrown onAutoClaim must not change recorder state to idle');
    });

    // GIVEN a valid auto-claim is triggered
    //   AND the claim fails (throws or returns failure)
    // WHEN the scan completes
    // THEN _loopStartTrailIndex is advanced so the same crossing does not re-fire
    test('failed auto-claim still advances loopStartTrailIndex', () async {
      capture.shouldThrow = true;
      svc.onAutoClaim = capture.call;

      final indexBefore = svc.loopStartTrailIndexForTesting;
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(svc.loopStartTrailIndexForTesting, greaterThan(indexBefore),
          reason: 'loopStartTrailIndex must advance even after a failed claim to prevent re-firing');
    });
  });
}

// ---------------------------------------------------------------------------
// Path builders for area-floor tests
// ---------------------------------------------------------------------------

// A tiny crossing path: two segments that cross but produce a very small polygon.
// The crossing creates a loop of roughly 0.0001 x 0.0001 degrees ~ 10m x 9m ~ 90 m^2.
List<LatLng> _buildMicroCrossPath() => [
      // index 0: A
      const LatLng(34.700000, 33.000000),
      // index 1: B
      const LatLng(34.700000, 33.000200), // 0.0002 deg lng ~ 18 m E
      // index 2: C
      const LatLng(34.700200, 33.000200), // 0.0002 deg lat ~ 22 m N
      // index 3: D
      const LatLng(34.700200, 33.000000), // back W
      // index 4: E - crosses A->B at roughly (34.700000, 33.000100)
      const LatLng(34.700000, 33.000100),
    ];

// Extended figure-8 path: appends a second crossing loop after the first one.
// Used in multi-lasso tests.
List<LatLng> _figure8PathExtended() {
  final base = _figure8Path();
  // Continue from where the first loop ended (index 4) and add a second loop.
  return [
    ...base,
    // index 5: continue east
    const LatLng(34.700, 33.030),
    // index 6: turn north
    const LatLng(34.730, 33.030),
    // index 7: turn west
    const LatLng(34.730, 33.010),
    // index 8: head south-east to cross segment index 5->6
    const LatLng(34.700, 33.020),
  ];
}
