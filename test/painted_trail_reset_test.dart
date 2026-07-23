// test/painted_trail_reset_test.dart
//
// Verifies the painted run trail (RunRecorderService.currentSegmentTrack /
// currentSegmentStartIndex) stays put through a rejected or non-crossing
// scan, and only advances - resetting the painted segment - once a claim is
// actually dispatched. Exercised both through the direct scan seam (real-run
// path) and through a full simulated replay (beginSimulation /
// runSimulationSequence), since the requirement is that the reset fires on
// the same claim event whether the session is real or simulated.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

// A tiny X-crossing path, well below the area-floor gate - triggers a
// self-intersection but never dispatches a claim. Mirrors
// _buildTinyCrossPath in auto_claim_test.dart.
List<LatLng> _tinyCrossPath() {
  const a = LatLng(34.700000, 33.000000);
  const b = LatLng(34.7000125, 33.0000125);
  const c = LatLng(34.7000125, 33.000000);
  const d = LatLng(34.700000, 33.0000125);
  LatLng mid(LatLng x, LatLng y) =>
      LatLng((x.latitude + y.latitude) / 2, (x.longitude + y.longitude) / 2);
  return [a, b, mid(b, c), c, d];
}

// A genuine ~100 m x 100 m loop, well above the area floor - the same
// relative shape validated by _figure8Path in auto_claim_test.dart, so it
// closes and dispatches a claim.
List<LatLng> _largeLoopPath() => const [
      LatLng(34.700, 33.000),
      LatLng(34.700, 33.020),
      LatLng(34.720, 33.020),
      LatLng(34.720, 33.000),
      LatLng(34.700, 33.010),
    ];

// Continues _largeLoopPath with a second, geometrically distinct closing
// loop so a second claim can be dispatched in the same session. Mirrors
// _figure8PathExtended in auto_claim_test.dart.
List<LatLng> _largeLoopPathExtended() => [
      ..._largeLoopPath(),
      const LatLng(34.700, 33.030),
      const LatLng(34.730, 33.030),
      const LatLng(34.730, 33.010),
      const LatLng(34.700, 33.020),
    ];

class _AutoClaimCapture {
  final List<List<LatLng>> captured = [];
  Future<void> call(List<List<LatLng>> group) async {
    captured.add(group.first);
  }
}

void main() {
  group('painted trail segment - direct scan seam', () {
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

    test('segment start stays at 0 while no claim has landed yet', () {
      svc.injectTrackForTesting(_largeLoopPath().sublist(0, 3));
      expect(svc.currentSegmentStartIndex, 0,
          reason: 'Before any claim, the whole trail so far is the current segment');
      expect(svc.currentSegmentTrack, hasLength(3),
          reason: 'currentSegmentTrack must mirror the full trail before any claim');
    });

    test('a scan that is not a crossing leaves the painted segment untouched', () {
      svc.injectTrackForTesting(_largeLoopPath().sublist(0, 4));
      svc.runScanForAutoClaimForTesting();

      expect(capture.captured, isEmpty, reason: 'Precondition: no crossing yet, no claim');
      expect(svc.currentSegmentStartIndex, 0,
          reason: 'A non-crossing scan must never advance the painted segment boundary');
      expect(svc.currentSegmentTrack, hasLength(4));
    });

    test('a scan that is a crossing but is gate-rejected leaves the painted segment untouched', () async {
      svc.injectTrackForTesting(_tinyCrossPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, isEmpty,
          reason: 'Precondition: the tiny loop must fail the area floor, not claim');
      expect(svc.currentSegmentStartIndex, 0,
          reason: 'A gate-rejected crossing must never reset the painted trail - '
              'the trail stays visible until a claim actually lands');
      expect(svc.currentSegmentTrack, hasLength(_tinyCrossPath().length),
          reason: 'The full trail-so-far must still be the painted segment after a rejection');
    });

    test('a dispatched claim resets the painted segment to the claim boundary', () async {
      svc.injectTrackForTesting(_largeLoopPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, hasLength(1),
          reason: 'Precondition: the large loop must clear every gate and dispatch a claim');

      final k = _largeLoopPath().length - 1;
      expect(svc.currentSegmentStartIndex, k,
          reason: 'After a claim, the painted segment must reset to start at the claim '
              'boundary - the same index _scanForAutoClaim itself just consumed');
      expect(svc.currentSegmentTrack, hasLength(1),
          reason: 'Immediately after the claim, only the claim-boundary point remains '
              'painted - a fresh trail then grows from there onward');
    });

    test('after a claim, new GPS points extend only the reset (post-claim) segment', () async {
      svc.injectTrackForTesting(_largeLoopPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(capture.captured, hasLength(1));

      // Extend the trail past the claim point - these new points must join
      // the fresh, reset segment, not the whole session history.
      svc.injectTrackForTesting([..._largeLoopPath(), const LatLng(34.700, 33.011)]);

      expect(svc.currentSegmentTrack, hasLength(2),
          reason: 'The reset segment must grow from the claim boundary - it must not '
              'silently re-include the whole pre-claim trail');
    });

    test('a second claim in the same session resets the segment again, further along', () async {
      svc.injectTrackForTesting(_largeLoopPath());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(capture.captured, hasLength(1));

      // Fast-forward past the 30 s claim-interval floor so the second
      // crossing is not rejected purely on timing.
      svc.injectLastClaimAt(DateTime.now().toUtc().subtract(const Duration(seconds: 40)));

      svc.injectTrackForTesting(_largeLoopPathExtended());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, hasLength(2),
          reason: 'Precondition: the second, distinct loop must also dispatch a claim');

      final secondK = _largeLoopPathExtended().length - 1;
      expect(svc.currentSegmentStartIndex, secondK,
          reason: 'A second claim must reset the painted segment again, to the SECOND '
              'claim boundary, not leave it at the first');
    });
  });

  group('painted trail segment - through a full simulated replay', () {
    late RunRecorderService svc;
    late _AutoClaimCapture capture;

    setUp(() {
      svc = RunRecorderService.instance;
      capture = _AutoClaimCapture();
      svc.onAutoClaim = capture.call;
    });

    tearDown(() {
      svc.reset();
    });

    test('a claim dispatched through beginSimulation/runSimulationSequence resets the painted segment too', () async {
      final base = DateTime.parse('2026-07-18T16:00:00.000Z');
      const lats = [34.700, 34.700, 34.720, 34.720, 34.700];
      const lngs = [33.000, 33.020, 33.020, 33.000, 33.010];
      final offsets = [5, 10, 15, 20, 65];
      final events = [
        for (var i = 0; i < offsets.length; i++)
          SimulationFixEvent(
            t: base.add(Duration(seconds: offsets[i])),
            type: 'gps_fix',
            data: {'lat': lats[i], 'lng': lngs[i], 'speed_ms': 2.0},
          ),
        SimulationFixEvent(
          t: base.add(const Duration(seconds: 70)),
          type: 'user_stop_pressed',
          data: const {},
        ),
      ];

      // Captured at the moment of the claim itself (onAutoClaim fires
      // synchronously, before user_stop_pressed's own end-of-session
      // teardown clears _consumedSpans) - segment-start state observed
      // AFTER the whole sequence completes would reflect that teardown,
      // not the claim-time reset this test is proving.
      int? segmentStartAtClaimTime;
      svc.onAutoClaim = (polygon) async {
        segmentStartAtClaimTime = svc.currentSegmentStartIndex;
        await capture.call(polygon);
      };

      expect(svc.currentSegmentStartIndex, 0,
          reason: 'Precondition: nothing consumed before the simulation starts');

      final started = await svc.beginSimulation(simulatedSessionStart: base);
      expect(started, isTrue);
      await svc.runSimulationSequence(events, multiplier: 200.0);

      expect(capture.captured, hasLength(1),
          reason: 'Precondition: the simulated closing loop must dispatch exactly one claim, '
              'the same shared onAutoClaim path a real run uses');
      expect(segmentStartAtClaimTime, isNotNull);
      expect(segmentStartAtClaimTime, greaterThan(0),
          reason: 'A claim dispatched through the simulated replay must reset the painted '
              'trail segment exactly as a real-run claim does - simulation runs through '
              'the identical _scanForAutoClaim path');
    });
  });
}
