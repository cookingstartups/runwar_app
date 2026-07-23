// test/sibling_loop_grouping_test.dart
//
// Covers RunRecorderService._groupPolygonsByProximity: when a run
// self-closes MORE THAN ONE loop, sibling loops within the 25m seal-merge
// radius (kProximityTriggerM) of EACH OTHER must be submitted as ONE grouped
// claim, while loops beyond that radius stay independent - the Panel 2
// "Union" decision.
//
// Two layers of coverage:
//   1. groupPolygonsByProximityForTesting - the grouping decision itself,
//      driven directly against constructed rectangle rings so the geometry
//      is exact and deterministic (within/beyond/transitive-chain).
//   2. A real end-to-end pass through the deferred-crossing drain batch
//      path, proving two GPS-trail-derived loop closures detected in the
//      same run are actually grouped and dispatched as one claim, not just
//      that the grouping FUNCTION works in isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

const double _latM = 110540.0;

// Axis-aligned rectangle ring in metres-offset-from-origin terms, converted
// to lat/lng near the equator-adjacent test latitude used throughout the
// project's other fixtures (34.7 N).
const double _testLat = 34.700;

double _mLat(double meters) => meters / _latM;
double _mLng(double meters) =>
    meters / (111320.0 * (0.8225)); // cos(34.7 deg) ~ 0.8225

List<LatLng> _rectRing(double x0, double y0, double w, double h) {
  final lat0 = _testLat + _mLat(y0);
  final lat1 = _testLat + _mLat(y0 + h);
  final lng0 = 33.000 + _mLng(x0);
  final lng1 = 33.000 + _mLng(x0 + w);
  return [
    LatLng(lat0, lng0),
    LatLng(lat0, lng1),
    LatLng(lat1, lng1),
    LatLng(lat1, lng0),
  ];
}

// A self-crossing "figure-8" loop (same shape auto_claim_test.dart uses),
// parameterised by a base lat/lng so multiple independent loops can be
// placed at controlled distances from each other for the end-to-end test.
List<LatLng> _figure8At(double baseLat, double baseLng) => [
      LatLng(baseLat, baseLng),
      LatLng(baseLat, baseLng + 0.020),
      LatLng(baseLat + 0.020, baseLng + 0.020),
      LatLng(baseLat + 0.020, baseLng),
      LatLng(baseLat, baseLng + 0.010),
    ];

class _AutoClaimGroupCapture {
  final List<List<List<LatLng>>> groups = [];

  Future<void> call(List<List<LatLng>> group) async {
    groups.add(group);
  }
}

void main() {
  group('groupPolygonsByProximityForTesting - the grouping decision itself', () {
    late RunRecorderService svc;

    setUp(() => svc = RunRecorderService.instanceForTesting());
    tearDown(() => svc.reset());

    test('two rings within 25m of each other group into one', () {
      // 40x40 ring at x:[0,40], and a second 40x40 ring at x:[50,90] - a 10m
      // gap, well inside the 25m seal radius.
      final a = _rectRing(0, 0, 40, 40);
      final b = _rectRing(50, 0, 40, 40);

      final groups = svc.groupPolygonsByProximityForTesting([a, b]);

      expect(groups, hasLength(1),
          reason: 'two rings 10m apart must collapse into one group');
      expect(groups.single, hasLength(2));
    });

    test('two rings beyond 25m of each other stay in separate groups', () {
      // 40x40 ring at x:[0,40], and a second 40x40 ring at x:[100,140] - a
      // 60m gap, well beyond the 25m seal radius.
      final a = _rectRing(0, 0, 40, 40);
      final b = _rectRing(100, 0, 40, 40);

      final groups = svc.groupPolygonsByProximityForTesting([a, b]);

      expect(groups, hasLength(2),
          reason: 'two rings 60m apart must stay in separate groups');
      expect(groups.every((g) => g.length == 1), isTrue);
    });

    test('a three-ring transitive chain (A-B close, B-C close, A-C far) collapses into ONE group via B', () {
      // A: x:[0,40]. B: x:[50,90] (10m gap from A). C: x:[100,140] (10m gap
      // from B, but 60m gap from A directly).
      final a = _rectRing(0, 0, 40, 40);
      final b = _rectRing(50, 0, 40, 40);
      final c = _rectRing(100, 0, 40, 40);

      // A and C alone (60m apart) must not link directly.
      final directAC = svc.groupPolygonsByProximityForTesting([a, c]);
      expect(directAC, hasLength(2),
          reason: 'A and C alone (60m apart) must not link directly');

      final chain = svc.groupPolygonsByProximityForTesting([a, b, c]);
      expect(chain, hasLength(1),
          reason: 'A, B and C must collapse into exactly one transitive group via B');
      expect(chain.single, hasLength(3));
    });

    test('a single polygon batch is its own group of one - no behaviour change for the ordinary single-loop case', () {
      final a = _rectRing(0, 0, 40, 40);
      final groups = svc.groupPolygonsByProximityForTesting([a]);
      expect(groups, hasLength(1));
      expect(groups.single, hasLength(1));
    });
  });

  group('end-to-end: sibling-loop grouping via the deferred-crossing drain batch', () {
    late RunRecorderService svc;
    late _AutoClaimGroupCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _AutoClaimGroupCapture();
      svc.onAutoClaim = capture.call;
    });

    tearDown(() => svc.reset());

    test('two sibling loops closed in the same run, both deferred then drained together, submit as ONE grouped claim', () async {
      final t0 = DateTime.now();
      svc.injectSessionStartTime(t0);

      const baseLat = 34.700;
      const baseLng = 33.000;
      final firstLoop = _figure8At(baseLat, baseLng);

      // First closure - deferred (elapsed 10s, under the 30s floor).
      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 10)));
      svc.injectTrackForTesting(firstLoop);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(svc.deferredCrossingCountForTesting, 1);

      // Second closure, continuing directly from the first loop's own
      // closing point (both loops overlap the same small area, well within
      // the 25m radius) - also deferred (elapsed 20s, still under the 30s
      // floor).
      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 20)));
      svc.injectTrackForTesting([
        ...firstLoop,
        LatLng(baseLat, baseLng + 0.020),
        LatLng(baseLat + 0.020, baseLng + 0.020),
        LatLng(baseLat + 0.020, baseLng),
        LatLng(baseLat, baseLng + 0.010),
      ]);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(svc.deferredCrossingCountForTesting, 2,
          reason: 'two distinct trail spans must be tracked independently, '
              'even though they will later group into one claim');

      // Drain: elapsed now clears the 30s floor for both.
      svc.injectLastFixTimestamp(t0.add(const Duration(seconds: 35)));
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(capture.groups, hasLength(1),
          reason: 'both sibling loops sit within the seal-merge radius, so they must dispatch as ONE claim');
      expect(capture.groups.single, hasLength(2),
          reason: 'the one dispatched claim must carry BOTH sibling loops - neither is dropped');
    });
  });
}
