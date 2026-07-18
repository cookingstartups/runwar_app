
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

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
// Stub for the NEW onGateRejected callback (design.md section 1). Records
// every (reason, details) pair passed by _scanForAutoClaim's two early-return
// branches. RunRecorderService currently has neither the GateRejectionReason
// enum nor the onGateRejected field, so every test in Group 7 below fails to
// compile ("member not found") until the implementation lands.
// ---------------------------------------------------------------------------

class _GateRejectionCapture {
  final List<({GateRejectionReason reason, Map<String, dynamic> details})>
      captured = [];

  Future<void> call(GateRejectionReason reason, Map<String, dynamic> details) async {
    captured.add((reason: reason, details: details));
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

  group('lasso geometry - vertex-proximity closure filtering', () {
    // GIVEN a candidate proximity closure that is within kProximityTriggerM
    //   of an earlier vertex but spans fewer than the minimum required
    //   trail points
    // WHEN detectSelfIntersection runs the proximity fallback
    // THEN it does not report a closure (ordinary consecutive fixes near an
    //   old vertex must not be mistaken for a real loop)
    test('proximity fallback ignores a near-vertex match with too few intervening points', () {
      // A (idx0) -> a tiny 2-point detour back near A (idx1, idx2).
      // k=2 at the point of interest: k - vertexIdx(0) = 2, below the
      // minimum of 4 intervening trail points, so this must be rejected.
      final path = [
        const LatLng(34.700000, 33.000000), // idx0: A
        const LatLng(34.700450, 33.000000), // idx1: 50 m north
        const LatLng(34.700020, 33.000002), // idx2: back within ~2.2 m of A
      ];
      final result = detectSelfIntersection(path, 1);
      expect(result, isNull,
          reason: 'A near-vertex match spanning only 2 points must not be treated as a closure');
    });

    // GIVEN a candidate proximity closure with enough intervening points but
    //   a bounding box too small to represent a genuine loop
    // WHEN detectSelfIntersection runs the proximity fallback
    // THEN it does not report a closure
    test('proximity fallback ignores a near-vertex match with too small a bounding box', () {
      // Non-crossing zigzag clustered within a ~6 m box - four intervening
      // points clear the point-count filter, but the bounding box is far
      // too small to represent a real captured area.
      final path = [
        const LatLng(34.700000, 33.000000), // idx0
        const LatLng(34.700050, 33.000000), // idx1: ~5.5 m north
        const LatLng(34.700050, 33.000030), // idx2: ~2.6 m east
        const LatLng(34.700000, 33.000030), // idx3: ~5.5 m south
        const LatLng(34.700010, 33.000002), // idx4: back within ~1.7 m of idx0
      ];
      final result = detectSelfIntersection(path, 1);
      expect(result, isNull,
          reason: 'A tightly clustered near-vertex match must not be treated as a closure');
    });

    // GIVEN a candidate proximity closure with enough intervening points AND
    //   a large enough bounding box
    // WHEN detectSelfIntersection runs the proximity fallback
    // THEN it reports a valid, non-degenerate closure
    test('proximity fallback accepts a genuine large near-vertex closure', () {
      final path = [
        const LatLng(34.700000, 33.000000), // idx0: A
        const LatLng(34.700000, 33.001092), // idx1: ~100 m east
        const LatLng(34.700905, 33.001092), // idx2: ~100 m north
        const LatLng(34.700905, 33.000000), // idx3: ~100 m west
        const LatLng(34.700020, 33.000002), // idx4: back within ~2.2 m of A
      ];
      final result = detectSelfIntersection(path, 1);
      expect(result, isNotNull,
          reason: 'A genuine block-scale loop closing near the start vertex must be detected');
      expect(result!.isProximityClosure, isTrue);
      expect(result.intersectingSegmentIdx, 0);

      final k = path.length - 1;
      final polygon = computeCapture(
        path,
        1,
        result.intersectingSegmentIdx,
        result.intersectionPoint,
        k,
        isProximityClosure: result.isProximityClosure,
      );

      // The leading vertex must not be duplicated for a proximity closure.
      expect(polygon.first, equals(path[0]));
      expect(polygon[1], isNot(equals(polygon.first)),
          reason: 'computeCapture must not duplicate the leading vertex for a proximity closure');

      final areaSqm = polygonArea(polygon) * 1e6;
      expect(areaSqm, greaterThan(200.0),
          reason: 'A genuine ~100 m block loop must clear the 200 m^2 floor');
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

  // =========================================================================
  // Group 7: Gate rejection observability (R1-AC1, R1-AC2, R1-AC3)
  // =========================================================================

  group('gate rejection observability - area floor and session elapsed', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;
    late _GateRejectionCapture rejectionCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      rejectionCapture = _GateRejectionCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.onGateRejected = rejectionCapture.call;
    });

    tearDown(() {
      svc.reset();
    });

    // R1-AC1: area-floor gate rejection is observable
    test('area-floor rejection fires onGateRejected with the computed area and dispatches no claim', () async {
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);

      svc.injectTrackForTesting(_buildMicroCrossPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'Area-floor rejection must not dispatch a claim (unchanged)');
      expect(rejectionCapture.captured, hasLength(1),
          reason: 'Area-floor rejection must fire onGateRejected exactly once');
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.areaFloor);
      expect(rejectionCapture.captured.first.details['area_sqm'], isNotNull,
          reason: 'Rejection details must carry the computed area value for diagnostics');
    });

    // R1-AC2: session-elapsed gate rejection is observable
    test('session-elapsed rejection fires onGateRejected with elapsed seconds and dispatches no claim', () async {
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 25)));
      svc.injectState(RecorderState.recording);

      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'Session-elapsed rejection must not dispatch a claim (unchanged)');
      expect(rejectionCapture.captured, hasLength(1),
          reason: 'Session-elapsed rejection must fire onGateRejected exactly once');
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.sessionElapsed);
      expect(rejectionCapture.captured.first.details['elapsed_sec'], isNotNull,
          reason: 'Rejection details must carry the elapsed-seconds value for diagnostics');
    });

    // R1-AC3: gate feedback must not fire on a successful claim path
    test('a successful claim fires onAutoClaim and never onGateRejected', () async {
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);

      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'A qualifying loop must dispatch exactly one claim (unchanged)');
      expect(rejectionCapture.captured, isEmpty,
          reason: 'onGateRejected must never fire on the successful claim path');
    });

    // R1 edge case: both gates would trip - area floor short-circuits first,
    // so only the area-floor rejection fires (never both).
    test('when both gates would trip, only the area-floor rejection fires', () async {
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 10)));
      svc.injectState(RecorderState.recording);

      svc.injectTrackForTesting(_buildMicroCrossPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(rejectionCapture.captured, hasLength(1),
          reason: 'Only one rejection reason must fire when both gates would trip');
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.areaFloor,
          reason: 'Area-floor check runs first and short-circuits before the session-elapsed check');
    });
  });

  // =========================================================================
  // Group 8: real-world regression - large genuine loop survives spurious
  // near-vertex closures encountered earlier in the same session.
  //
  // Reproduces a live-run report: a runner completes a real, roughly
  // 100 m x 100 m enclosing loop with a genuine segment/segment crossing,
  // but earlier in the same trail a short near-vertex detour (well short of
  // enclosing anything) passes close to an old vertex. Before this fix, any
  // such near-miss that reached the area-floor gate would truncate
  // _loopStartTrailIndex, permanently discarding the history the real loop
  // later needed - so the genuine closure could never compute the full
  // polygon. This test asserts the real loop still claims correctly.
  // =========================================================================

  group('real-world regression - genuine large loop survives an earlier near-vertex detour', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;
    late _GateRejectionCapture rejectionCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      rejectionCapture = _GateRejectionCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.onGateRejected = rejectionCapture.call;
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    test('a genuine ~100 m loop still claims correctly after an earlier near-vertex detour', () async {
      final fullPath = _detourThenLargeLoopPath();

      // Feed the trail incrementally, exactly as GPS fixes arrive in the
      // running app, scanning after every new point.
      for (int i = 2; i < fullPath.length; i++) {
        svc.injectTrackForTesting(fullPath.sublist(0, i + 1));
        svc.runScanForAutoClaimForTesting();
        await Future<void>.delayed(Duration.zero);
      }

      expect(rejectionCapture.captured, isEmpty,
          reason: 'The early near-vertex detour must not even reach a gate rejection - '
              'it must be filtered by the proximity closure guards before an area check');
      expect(claimCapture.captured, hasLength(1),
          reason: 'The genuine large loop at the end of the trail must dispatch exactly one claim');

      final areaSqm = polygonArea(claimCapture.captured.first) * 1e6;
      expect(areaSqm, greaterThan(200.0),
          reason: 'The captured polygon must be the real, large loop - not a near-zero fragment');
      expect(areaSqm, greaterThan(2000.0),
          reason: 'A genuine ~100 m x 100 m loop must capture on the order of thousands of m^2, '
              'not the tiny (1.5-37 m^2) fragments seen in the live-run regression');
    });
  });
}

// ---------------------------------------------------------------------------
// Path builders for area-floor tests
// ---------------------------------------------------------------------------

// A tiny X-crossing path: segment C->D crosses segment A->B at their midpoints.
// Captured polygon is roughly a 5m x 4m quadrilateral (~63 m^2), well below 200 m^2.
// At lat 34.7: 0.00005 deg lat = ~5.5m, 0.00005 deg lng = ~4.3m.
List<LatLng> _buildMicroCrossPath() => [
      // index 0: A - origin
      const LatLng(34.700000, 33.000000),
      // index 1: B - ~7m NE
      const LatLng(34.700050, 33.000050),
      // index 2: C - ~5.5m north of A, same longitude
      const LatLng(34.700050, 33.000000),
      // index 3: D - crosses A->B at midpoint (34.700025, 33.000025); captured area ~63 m^2
      const LatLng(34.700000, 33.000050),
    ];

// A short near-vertex detour (indices 0-2, far south so it can never
// geometrically overlap the loop that follows) followed by a genuine
// ~100 m x 100 m enclosing loop (indices 3-7) whose last edge crosses its
// own first edge. Mirrors _figure8Path's proven relative shape, scaled down
// to city-block size (100 m x 100 m instead of ~2 km x ~1.8 km).
List<LatLng> _detourThenLargeLoopPath() {
  const dLat100 = 0.0009046; // ~100 m of latitude at this scale
  const dLng100 = 0.0010923; // ~100 m of longitude at 34.7 N
  return [
    // idx0: T0 - detour anchor, ~11 km south of the real loop so its
    // bounding box never overlaps the loop below.
    const LatLng(34.600000, 33.000000),
    // idx1: T1 - ~50 m north of T0.
    const LatLng(34.600453, 33.000000),
    // idx2: T2 - back within ~2.2 m of T0. Only 2 points span T0->T2, so
    // the point-count guard must reject this as a closure candidate.
    const LatLng(34.600020, 33.000002),
    // idx3: A - start of the real loop.
    const LatLng(34.700000, 33.000000),
    // idx4: B - ~100 m east of A.
    const LatLng(34.700000, 33.000000 + dLng100),
    // idx5: C - ~100 m north of B.
    const LatLng(34.700000 + dLat100, 33.000000 + dLng100),
    // idx6: D - ~100 m west of C, back to A's longitude.
    const LatLng(34.700000 + dLat100, 33.000000),
    // idx7: E - closes the loop by crossing segment A->B roughly at its
    // midpoint, the same relative geometry validated by _figure8Path.
    const LatLng(34.700000, 33.000000 + dLng100 / 2),
  ];
}

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
