
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/geo/lasso.dart';
import 'package:runwar_app/services/run_recorder_service.dart';
import 'package:runwar_app/services/realtime_presence_service.dart';
import 'package:runwar_app/utils/runwar_constants.dart';

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
          reason: 'A genuine ~100 m block loop must clear a 200 m^2 reference size '
              '(well above the current 500 m^2 area-floor gate)');
    });
  });

  group('lasso geometry - polygonArea', () {
    // GIVEN a large square polygon with sides ~500 m
    // WHEN polygonArea is called (returns km^2; multiply by 1e6 for m^2)
    // THEN the area in m^2 is >= 200.0
    //
    // 200 m^2 here is a geometry-sanity reference size for "clearly large",
    // not the current auto-claim area-floor gate value (see
    // RunRecorderService._minCapturedAreaSqm, currently 500.0).
    test('returns area >= 200 m^2 for a valid large lasso polygon', () {
      final poly = _largePolygon();
      final areaSqm = polygonArea(poly) * 1e6;
      expect(areaSqm, greaterThanOrEqualTo(200.0),
          reason: 'Large square polygon must exceed the 200 m^2 reference size');
    });

    // GIVEN a micro polygon with side ~11 m
    // WHEN polygonArea is called
    // THEN the area in m^2 is < 200.0, and is now also BELOW the current
    // 500 m^2 auto-claim area-floor gate - this test only verifies
    // polygonArea's numeric output, not gate behaviour (see the tiny-cross
    // fixtures below for a polygon that exercises gate behaviour directly).
    test('returns area < 200 m^2 for a GPS-jitter micro-polygon', () {
      final poly = _microPolygon();
      final areaSqm = polygonArea(poly) * 1e6;
      expect(areaSqm, lessThan(200.0),
          reason: 'Micro-polygon must fall below the 200 m^2 reference size');
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

  group('session time gate - auto-claim suppressed within 30 seconds of session start', () {
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

    // GIVEN the recorder has been in recording state for fewer than 30 seconds
    //   AND detectSelfIntersection returns a non-null result with area >= 200 m^2
    // WHEN the auto-claim handler evaluates the claim-interval gate
    // THEN no claim is triggered and no polygon is captured
    test('auto-claim does not fire when lasso closes within 30 seconds of session start', () {
      // Inject a session start time 15 seconds ago - within the 30-second window
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 15)));
      svc.injectState(RecorderState.recording);

      // Feed the figure-8 path to trigger a self-intersection
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();

      expect(capture.captured, isEmpty,
          reason: 'No claim should fire when session has been running for only 15 seconds');
    });

    // GIVEN the recorder has been in recording state for more than 30 seconds
    //   AND detectSelfIntersection returns a non-null result with area >= 200 m^2
    // WHEN the auto-claim handler evaluates the claim-interval gate
    // THEN the claim fires and the captured polygon is passed to onAutoClaim
    test('auto-claim fires when lasso closes after 30 seconds of session start', () async {
      // Inject a session start time 90 seconds ago - past the 30-second window
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

  group('area floor gate - 4 m^2 minimum', () {
    late RunRecorderService svc;
    late _AutoClaimCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _AutoClaimCapture();
      svc.onAutoClaim = capture.call;
      // Start well past the claim-interval gate
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    // GIVEN a captured polygon whose area is < 4 m^2
    // WHEN the auto-claim handler evaluates the area
    // THEN no claim is triggered
    test('auto-claim does not fire for a captured polygon with area below 4 m^2', () async {
      // Build a tiny-loop path that produces a near-zero polygon.
      // We inject it directly via the track seam.
      // The intersection is faked by using a known crossing tiny-path.
      // Because the polygon area is < 4, the claim must be suppressed.
      final tinyPath = _buildTinyCrossPath();
      svc.injectTrackForTesting(tinyPath);
      svc.runScanForAutoClaimForTesting();

      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, isEmpty,
          reason: 'Tiny loop with area < 4 m^2 must not trigger an auto-claim');
    });

    // GIVEN a captured polygon whose area is >= 4 m^2
    // WHEN the auto-claim handler evaluates the area
    // THEN the claim fires with the captured polygon
    test('auto-claim fires for a captured polygon with area >= 4 m^2', () async {
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();

      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, hasLength(1),
          reason: 'Large lasso (>= 4 m^2) must trigger an auto-claim');
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

      // The first claim just became the claim-interval reference point (see
      // the claim-interval gate group below) - fast-forward it well past the
      // 30s floor so the second intersection is not rejected only because
      // the two claims happened back-to-back in this test.
      svc.injectLastClaimAt(DateTime.now().toUtc().subtract(const Duration(seconds: 40)));

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

      // See the comment in the test above: the first claim set the
      // claim-interval reference to "now", so fast-forward past the 30s
      // floor before the second claim.
      svc.injectLastClaimAt(DateTime.now().toUtc().subtract(const Duration(seconds: 40)));

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

      svc.injectTrackForTesting(_buildTinyCrossPath());
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
      // SPEC-0143 scenario 1: a real run must reject the SAME way after the
      // clock-source fix lands, and the guard must never trip for a real fix.
      // Numeric assertion, not outcome-only - a guard-tripped wall-clock
      // fallback could also land near 25s and hide a broken clock domain.
      final elapsedSec = rejectionCapture.captured.first.details['elapsed_sec'] as int;
      expect(elapsedSec, closeTo(25, 2),
          reason: 'A real run must measure elapsed time from the fix that produced the '
              'crossing, on the wall-clock domain - approximately 25s, not a guard fallback');
      expect(svc.clockGuardTripsForTesting, 0,
          reason: 'A real GPS fix is always on the wall-clock domain and must never trip '
              'the clock-domain guard');
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

      svc.injectTrackForTesting(_buildTinyCrossPath());
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

  // =========================================================================
  // Group 9 (SPEC-0143 Part A): clock-domain guard against a mixed-domain
  // elapsed computation. These drive the gate through the injectLastFixTimestamp
  // seam directly, bypassing _onPosition's capture guard, so they exercise
  // _elapsedSecForGate's plausibility check on its own regardless of what
  // feeds it. All three currently fail because injectLastFixTimestamp is a
  // no-op (no field is read by the gate yet) and clockGuardTripsForTesting
  // never increments.
  // =========================================================================

  group('clock-domain guard - implausible fix timestamps fall back safely', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.injectState(RecorderState.recording);
    });

    tearDown(() => svc.reset());

    // Scenario 5a: an epoch-zero fix stamp must never poison the session
    // clock into computing a decades-long elapsed and passing unconditionally.
    test('epoch-zero fix timestamp trips the guard and falls back to wall clock', () async {
      final t0 = DateTime.now();
      svc.injectSessionStartTime(t0);
      svc.injectLastFixTimestamp(DateTime.fromMillisecondsSinceEpoch(0));
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'An epoch-zero stamp must never make the gate pass unconditionally');
      expect(svc.clockGuardTripsForTesting, greaterThan(0),
          reason: 'The clock-domain guard must trip on an epoch-zero timestamp');
    });

    // Scenario 5b: a fix stamp earlier than session start (negative elapsed,
    // device clock skew) must trip the guard, restoring real-run behavior.
    test('fix timestamp earlier than session start trips the guard', () async {
      final t0 = DateTime.now();
      svc.injectSessionStartTime(t0);
      svc.injectLastFixTimestamp(t0.subtract(const Duration(seconds: 5)));
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty);
      expect(svc.clockGuardTripsForTesting, greaterThan(0),
          reason: 'A negative elapsed value means the two operands are not on one '
              'timeline and must trip the guard');
    });

    // Scenario 5c: a deliberately mis-seeded multi-day skew (the primary
    // failure mode named in the operator brief) must trip the guard rather
    // than silently passing with a multi-day elapsed value.
    test('fix timestamp more than 24 hours ahead of session start trips the guard', () async {
      final t0 = DateTime.now();
      svc.injectSessionStartTime(t0);
      svc.injectLastFixTimestamp(t0.add(const Duration(days: 3)));
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'A mis-seeded multi-day-ahead stamp must never pass the gate silently');
      expect(svc.clockGuardTripsForTesting, greaterThan(0),
          reason: 'A implausible elapsed value above 24h must trip the guard');
    });
  });

  // =========================================================================
  // Group 10 (SPEC-0143 Part B): deferred crossing retry. A crossing that
  // clears all four geometric gates but fails only the session-elapsed gate
  // must be retained and later dispatched, instead of being lost once the
  // trail advances past the segment pair that produced it. All four tests
  // currently fail: deferredCrossingCountForTesting never leaves 0 because
  // nothing populates the (inert, RED-phase) _deferredCrossings list yet.
  // =========================================================================

  group('deferred crossing retry - a session-elapsed-only rejection is retained and later dispatched', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;
    late _GateRejectionCapture rejectionCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      rejectionCapture = _GateRejectionCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.onGateRejected = rejectionCapture.call;
      svc.injectState(RecorderState.recording);
    });

    tearDown(() => svc.reset());

    // Non-crossing extension of _figure8Path: the newest segment after this
    // extension no longer touches the original crossing pair, so a direct
    // rescan from the unchanged loopStartTrailIndex cannot rediscover it -
    // only the retained deferred entry can.
    List<LatLng> extended() => [
          ..._figure8Path(),
          const LatLng(34.700, 33.030),
          const LatLng(34.700, 33.040),
        ];

    // Scenario 6: dispatches once the elapsed threshold passes.
    test('a deferred crossing dispatches once the elapsed threshold passes, with no new crossing', () async {
      final t0 = DateTime.now();
      svc.injectSessionStartTime(t0);
      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 20)));
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty);
      expect(svc.deferredCrossingCountForTesting, 1,
          reason: 'A crossing that clears all four geometric gates but fails only the '
              'elapsed gate must be retained, not discarded');

      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 70)));
      svc.injectTrackForTesting(extended());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'The originally-detected polygon must dispatch once the threshold passes, '
              'even though the newest segment no longer touches the original crossing pair');
      expect(svc.deferredCrossingCountForTesting, 0);
    });

    // Scenario 7: at-most-once dispatch.
    test('a dispatched deferred crossing never dispatches a second time on later scans', () async {
      final t0 = DateTime.now();
      svc.injectSessionStartTime(t0);
      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 20)));
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 70)));
      svc.injectTrackForTesting(extended());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'A dispatched deferred crossing must never fire a second onAutoClaim call');
    });

    // Scenario 8: a session boundary discards a pending deferral.
    test('cancelRun discards a pending deferred crossing; it never resurrects in a later session', () async {
      svc.onRunUpdate = (_, __) async {};
      final t0 = DateTime.now();
      svc.injectSessionStartTime(t0);
      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 20)));
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(svc.deferredCrossingCountForTesting, 1);

      await svc.cancelRun();
      expect(svc.deferredCrossingCountForTesting, 0,
          reason: 'cancelRun must discard any pending deferred crossing');

      svc.injectState(RecorderState.recording);
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'A crossing deferred in a cancelled session must never claim in a later, unrelated session');
    });

    // Scenario 9: two independent crossings in one session are tracked and
    // dispatched independently. Offsets scaled to the 30s claim-interval
    // floor (previously 60s): both crossings must stay deferred while
    // elapsed is still under 30s (10s, then 20s), and only drain once
    // elapsed reaches 30s or more (35s).
    test('two independent crossings in one session are each retained and dispatched exactly once', () async {
      final t0 = DateTime.now();
      svc.injectSessionStartTime(t0);
      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 10)));
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(svc.deferredCrossingCountForTesting, 1);

      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 20)));
      svc.injectTrackForTesting(_figure8PathExtended());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(svc.deferredCrossingCountForTesting, 2,
          reason: 'A second, later, geometrically distinct crossing must be tracked '
              'independently of the first');

      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 35)));
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(2),
          reason: 'Both deferred crossings must eventually dispatch independently, each once');
      expect(svc.deferredCrossingCountForTesting, 0);
    });
  });

  // =========================================================================
  // Group 11 (SPEC-0143 Part B + F1): crash/resume rescan path. F1 is
  // safety-critical: _rescanRehydratedTrack currently checks only area and
  // diagonal, so deferring from it as literally specified would let a thin
  // sliver claim once 60s elapses. The design adds the compactness and
  // path-length gates to this path before it is allowed to defer anything.
  // =========================================================================

  group('rehydration rescan path - retains instead of discarding, and never skips the safety gates', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      svc.onAutoClaim = claimCapture.call;
    });

    tearDown(() => svc.reset());

    // Scenario 10.
    test('a crossing clearing all four geometric gates but failing only elapsed is retained, not dropped', () async {
      svc.injectTrackForTesting(_figure8Path());
      svc.injectSessionStartTime(DateTime.now());
      await svc.rescanRehydratedTrackForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty);
      expect(svc.deferredCrossingCountForTesting, 1,
          reason: 'The rescan path must retain a session-elapsed-only rejection instead of '
              'the dead-end continue it uses today');
    });

    // F1 safety test, shape gates ON: a long thin sliver clears area (1500
    // sqm+) and diagonal (30 m+) but fails compactness (0.15) - with shape
    // gates enabled, the rescan path must still reject it, exactly as the
    // live path already does, even though the elapsed threshold has passed.
    // Shape gates are off by default now (kEnforceShapeGates); this test
    // explicitly re-enables them to prove F1 parity still holds when they
    // are on, which is the whole point of keeping the gate code reversible.
    test('shape gates ON: a thin sliver clearing only area and diagonal is still rejected by the rescan path', () async {
      svc.debugSetEnforceShapeGates(true);
      svc.injectTrackForTesting(_elongatedSliverPath());
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      await svc.rescanRehydratedTrackForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'F1: the rescan path must apply the same compactness and path-length '
              'floors as the live path - a sliver that only clears area and diagonal must '
              'never claim via rehydration, even after the elapsed threshold has passed');
    });

    // Mirror of the test above with the shipped default (shape gates OFF):
    // the SAME thin sliver now claims via the rescan path too, because the
    // rescan path (_rescanRehydratedTrack) mirrors the live path's flag
    // check exactly - the two paths must never disagree on the same
    // polygon (see the comment on the rescan path's shape-gate guard).
    test('shape gates OFF (default): the same thin sliver now claims via the rescan path', () async {
      svc.injectTrackForTesting(_elongatedSliverPath());
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      await svc.rescanRehydratedTrackForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'With shape gates off, the rescan path is area-only, same as the live '
              'path - it must not still enforce compactness on its own');
    });
  });

  // =========================================================================
  // Group 12: non-regression lock, shape gates ON - the geometric gates and
  // their order are unaffected by this change WHEN kEnforceShapeGates is
  // true. This test is expected to pass already (the compactness gate
  // predates this spec); it documents the invariant so a future edit to the
  // deferred-crossing plumbing cannot silently weaken it. The shipped
  // default is OFF - see the shape-gate flag group below for that behaviour.
  // =========================================================================

  group('non-regression - an elongated sliver is still rejected by compactness when shape gates are ON', () {
    test('an elongated sliver never reaches the session-elapsed gate', () async {
      final svc = RunRecorderService.instanceForTesting();
      final claimCapture = _AutoClaimCapture();
      final rejectionCapture = _GateRejectionCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.onGateRejected = rejectionCapture.call;
      svc.debugSetEnforceShapeGates(true);
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);

      svc.injectTrackForTesting(_elongatedSliverPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty);
      expect(rejectionCapture.captured, hasLength(1));
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.compactness,
          reason: 'With shape gates on, the compactness floor must still reject a thin '
              'sliver before the claim-interval gate is ever reached');
      svc.reset();
    });
  });

  // =========================================================================
  // Group 13: shape-gate flag (kEnforceShapeGates) - the operator wants a
  // claim gated on the area floor only for now, because a loop that
  // legitimately extends an already-owned zone can be a thin wedge on its
  // own and was being rejected by the shape gates before it ever reached
  // the merge step. Default OFF: only the diagonal, compactness and
  // path-length checks are skipped; the area floor and the claim-interval
  // gate are unaffected and stay enforced in both flag states.
  // =========================================================================

  group('shape-gate flag (kEnforceShapeGates) - area-only claim widening', () {
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

    tearDown(() => svc.reset());

    test('the shipped default is OFF', () {
      expect(kEnforceShapeGates, isFalse,
          reason: 'if this fails, the constant itself changed - update this test '
              'deliberately, do not just make it pass');
    });

    // Reproduction: a thin wedge (~1650 sqm, ~431 m bounding-box diagonal,
    // ~0.0089 compactness - see _thinWedgePath) that clears the area and
    // diagonal floors but fails compactness badly. This is exactly the
    // shape a real zone-extension loop produces.
    test('default (shape gates OFF): a thin wedge that fails compactness is ACCEPTED', () async {
      svc.injectTrackForTesting(_thinWedgePath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'With shape gates off, only the area floor gates a claim - the thin '
              'wedge must now dispatch a claim, where it was rejected before this change');
      expect(rejectionCapture.captured, isEmpty,
          reason: 'No gate rejection may fire on the accepted path');
    });

    test('shape gates ON: the same thin wedge is REJECTED with compactness', () async {
      svc.debugSetEnforceShapeGates(true);

      svc.injectTrackForTesting(_thinWedgePath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'Flipping the flag back on must restore exactly today\'s enforcement');
      expect(rejectionCapture.captured, hasLength(1));
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.compactness,
          reason: 'The wedge clears area (~1650 sqm > 1500) and diagonal (~431 m > 30 m) '
              'but fails compactness (~0.0089 < 0.15), so compactness is the reason it '
              'is rejected once shape gates are re-enabled');
    });

    test('area floor still bites regardless of the flag - OFF', () async {
      svc.injectTrackForTesting(_buildTinyCrossPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty);
      expect(rejectionCapture.captured, hasLength(1));
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.areaFloor,
          reason: 'The area floor is never gated behind the shape-gate flag');
    });

    test('area floor still bites regardless of the flag - ON', () async {
      svc.debugSetEnforceShapeGates(true);

      svc.injectTrackForTesting(_buildTinyCrossPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty);
      expect(rejectionCapture.captured, hasLength(1));
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.areaFloor);
    });
  });

  // =========================================================================
  // Group 14: claim-interval gate - claim-to-claim or 0-to-claim per session.
  //
  // Was a single "total session elapsed since start" floor of 60 s, checked
  // only against session start and never updated per claim. Now a per-claim
  // interval floor of 30 s: the first claim of a session is still gated
  // from session start (0-to-claim), but every claim AFTER the first is
  // gated from the PREVIOUS dispatched claim (claim-to-claim), not from
  // session start again.
  // =========================================================================

  group('claim-interval gate - claim-to-claim after the first claim, 0-to-claim for the first', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;
    late _GateRejectionCapture rejectionCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      rejectionCapture = _GateRejectionCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.onGateRejected = rejectionCapture.call;
      svc.injectState(RecorderState.recording);
    });

    tearDown(() => svc.reset());

    // 0-to-claim: the first claim of a session is gated from session start.
    test('first claim of a session, only 20s after session start, is rejected', () async {
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 20)));

      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty);
      expect(rejectionCapture.captured, hasLength(1));
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.sessionElapsed);
      expect(svc.lastClaimAtForTesting, isNull,
          reason: 'A rejected claim must never become the new interval reference');
    });

    // 0-to-claim: the first claim of a session is accepted once 30s have
    // passed since session start, and its own dispatch becomes the new
    // claim-interval reference point for the next claim.
    test('first claim of a session, 30s after session start, is accepted and becomes the new reference', () async {
      final base = DateTime.now().toUtc();
      svc.injectSessionStartTime(base.subtract(const Duration(seconds: 30)).toLocal());
      svc.injectLastFixTimestamp(base);

      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1));
      expect(rejectionCapture.captured, isEmpty);
      expect(svc.lastClaimAtForTesting, base,
          reason: 'A dispatched claim must become the new claim-interval reference point');
    });

    // Claim-to-claim: a second claim attempted less than 30s after the
    // first dispatched claim is rejected, measured from the FIRST CLAIM,
    // not from session start again.
    test('second claim, 10s after the first claim, is rejected', () async {
      final base = DateTime.now().toUtc();
      svc.injectSessionStartTime(base.subtract(const Duration(seconds: 90)).toLocal());
      svc.injectLastFixTimestamp(base);
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(claimCapture.captured, hasLength(1),
          reason: 'Precondition: the first claim must dispatch (90s since session start)');

      // Second crossing, only 10s of fix-clock time after the first claim's
      // own dispatch - well under the 30s claim-interval floor, even though
      // it is well over 30s since session start.
      svc.injectLastFixTimestamp(base.add(const Duration(seconds: 10)));
      svc.injectTrackForTesting(_figure8PathExtended());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'The second claim must NOT dispatch - only 10s have passed since the '
              'first claim, even though session start was 100s ago');
      expect(rejectionCapture.captured, hasLength(1));
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.sessionElapsed);
      expect(rejectionCapture.captured.first.details['elapsed_sec'], 10,
          reason: 'elapsed_sec must be measured from the first claim (10s), not from '
              'session start (which would read ~100s)');
    });

    // Claim-to-claim: a second claim attempted 30s or more after the first
    // dispatched claim is accepted.
    test('second claim, 30s after the first claim, is accepted', () async {
      final base = DateTime.now().toUtc();
      svc.injectSessionStartTime(base.subtract(const Duration(seconds: 90)).toLocal());
      svc.injectLastFixTimestamp(base);
      svc.injectTrackForTesting(_figure8Path());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(claimCapture.captured, hasLength(1),
          reason: 'Precondition: the first claim must dispatch');

      svc.injectLastFixTimestamp(base.add(const Duration(seconds: 30)));
      svc.injectTrackForTesting(_figure8PathExtended());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(2),
          reason: 'A second claim exactly 30s after the first must be accepted');
      expect(rejectionCapture.captured, isEmpty);
    });

    // Session boundary: _lastClaimAt must never leak into a new session.
    test('reset() clears the claim-interval reference so a new session cannot inherit it', () {
      svc.injectLastClaimAt(DateTime.now().toUtc());
      expect(svc.lastClaimAtForTesting, isNotNull);

      svc.reset();

      expect(svc.lastClaimAtForTesting, isNull,
          reason: 'A stale claim timestamp from a prior session must never leak into the next one');
    });
  });
}

// ---------------------------------------------------------------------------
// Path builders for area-floor tests
// ---------------------------------------------------------------------------

// A tiny X-crossing path: segment C->D crosses segment A->B at their midpoints.
// Captured polygon is roughly a 1.75m x 1.4m quadrilateral (~2.5 m^2), below
// the 500 m^2 area-floor gate (_minCapturedAreaSqm).
List<LatLng> _buildTinyCrossPath() => [
      // index 0: A - origin
      const LatLng(34.700000, 33.000000),
      // index 1: B - ~1.75m NE
      const LatLng(34.7000125, 33.0000125),
      // index 2: C - ~1.4m north of A, same longitude
      const LatLng(34.7000125, 33.000000),
      // index 3: D - crosses A->B at midpoint; captured area ~2.5 m^2
      const LatLng(34.700000, 33.0000125),
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

// A long thin sliver, same A-B-C-D-E shape as _figure8Path but squashed on
// the short axis by 100x: clears the area floor (1500 sqm) and the diagonal
// floor (30 m) but fails compactness (0.15) badly. Used to prove the
// rehydration rescan path (F1) applies the same compactness/path-length
// floors the live path already enforces.
List<LatLng> _elongatedSliverPath() => [
      const LatLng(34.700000, 33.000000),
      const LatLng(34.700000, 33.040000),
      const LatLng(34.700200, 33.040000),
      const LatLng(34.700200, 33.000000),
      const LatLng(34.700000, 33.020000),
    ];

// A thin wedge that reproduces the shape a real zone-extension loop
// produces: a genuine loop that legitimately extends an already-owned zone,
// but whose OWN shape is a thin rectangle, not a compact block. Closes via
// the vertex-proximity fallback (the closing fix E lands ~0.4 m from the
// starting vertex A, well inside kProximityTriggerM), mirroring the "large
// near-vertex closure" fixture already validated above (idx0..idx4, closes
// near A). A(0,0) -> B(east, short edge) -> C(north, long edge) ->
// D(west, back to A's longitude) -> E(closes near A).
//
// Captured polygon: area ~1650 sqm (clears the 1500 sqm area floor), a
// bounding-box diagonal ~431 m (clears the 30 m diagonal floor), and a
// compactness of ~0.0089 (area / diagonal^2), far below the 0.15
// compactness floor - so it clears area and diagonal but fails compactness
// hard. Exact figures verified against the app's own polygonArea /
// polygonBboxDiagonalM projections (lib/geo/lasso.dart) before being fixed
// as literals here.
List<LatLng> _thinWedgePath() => const [
      LatLng(34.7, 33.0),
      LatLng(34.7, 33.00004292345667),
      LatLng(34.70389904107111, 33.00004292345667),
      LatLng(34.70389904107111, 33.0),
      LatLng(34.70000271394971, 33.00000218528903),
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
