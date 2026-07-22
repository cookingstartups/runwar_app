// test/owned_edge_closure_gating_test.dart
//
// RED phase - the sliver produced by an owned-zone-edge closure must pass
// through the SAME four geometric floor gates as any other captured
// polygon, with no special-casing. RunRecorderService does not yet expose
// an ownedZoneEdgesProvider field, so every test below fails to compile
// until the implementation lands.
//
// Geometry: the wall and trail fixtures below are derived against the
// captured polygon RunRecorderService actually produces for an owned-zone-
// wall closure: [wallHitPoint, ...every trail point from index 0 through
// the crossing fix], anchored at 0 (nothing consumed yet this session)
// rather than at the crossing segment alone. Each fixture's four gate
// values (area, diagonal, compactness, path length) were computed against
// that real polygon before being asserted on here, not assumed from an
// earlier convention. Each trail also inserts one collinear midpoint (see
// _mid below) purely to clear the consumed-span dedup gate's 4-segment
// floor - it changes point count only, not any of the four measured
// geometric properties.
//
// One geometric constraint shapes every fixture below: for a bounding-box
// diagonal d, area is at most d^2 / 2, so any polygon clearing the 1500 sqm
// area floor always has a diagonal of at least about 54.8 m - well above
// the 30 m diagonal floor. The diagonal floor can therefore never be
// isolated on its own; only compactness and path length can be.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

class _AutoClaimCapture {
  final List<List<LatLng>> captured = [];
  Future<void> call(List<LatLng> polygon) async => captured.add(polygon);
}

class _GateRejectionCapture {
  final List<({GateRejectionReason reason, Map<String, dynamic> details})> captured = [];
  Future<void> call(GateRejectionReason reason, Map<String, dynamic> details) async {
    captured.add((reason: reason, details: details));
  }
}

// A midpoint of a->b, collinear with the segment it splits. Inserting it
// into a trail adds a point (and therefore a segment) without changing the
// resulting captured polygon's area, diagonal, compactness, or path length
// at all - used below to keep each wall-crossing trail at or above the
// consumed-span dedup gate's 4-segment floor (kMinNewLoopTrailSegments)
// while leaving every other measured property of the fixture untouched.
LatLng _mid(LatLng a, LatLng b) =>
    LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2);

// A single-edge owned-zone wall, plus a 4-point trail (r0, its midpoint
// with r1, r1, r2) whose newest segment crosses it. `scale` uniformly
// scales every offset from the wall's origin corner, so shrinking it (T3)
// proportionally shrinks area while every other property of the shape
// stays geometrically similar. The midpoint between r0 and r1 exists only
// to clear the consumed-span dedup gate's 4-segment floor (see _mid above)
// - it does not change the captured polygon's geometry.
({List<LatLng> wall, List<LatLng> trail}) _wallCrossingFixture({double scale = 1.0}) {
  const originLat = 34.700000;
  const originLng = 33.000000;
  final wallOffsetLat = 0.0008141 * scale; // ~90 m at scale 1.0
  final wallSpanLng = 0.0009832 * scale; // ~90 m at scale 1.0
  final excursionLat = 0.0009950 * scale; // ~110 m north of the trail's start row
  final crossingLng = 0.0008739 * scale;

  final r0 = LatLng(originLat - wallOffsetLat, originLng);
  final r1 = LatLng(originLat - wallOffsetLat, originLng + wallSpanLng);
  final r2 = LatLng(originLat - wallOffsetLat + excursionLat, originLng + crossingLng);

  final wall = [
    LatLng(originLat, originLng),
    LatLng(originLat, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng),
  ];

  return (wall: wall, trail: [r0, _mid(r0, r1), r1, r2]);
}

// A deliberately elongated variant, re-derived by measuring the actual
// captured polygon rather than assuming a slicing convention: for an
// owned-zone-wall closure, RunRecorderService anchors computeCapture at 0
// (nothing consumed yet), so the captured polygon is always [wallHitPoint,
// r0, midpoint(r0,r1), r1, r2] - the whole trail, not just the crossing
// segment's own two endpoints. To isolate compactness under that real
// slicing rule, r0 is placed far from the wall crossing along a near-
// collinear run, stretching the bounding-box diagonal much further than
// the enclosed area grows, while r1/r2 stay close enough together to keep
// the polygon narrow. Measured against the real computeCapture output:
// area ~8154 sqm (clears the 1500 sqm floor with a wide margin), diagonal
// ~422 m (clears the 30 m floor - a diagonal that large can never be the
// gate that fails here, see the module-level derivation note below),
// compactness ~0.046 (well under the 0.15 floor), loop path ~844 m
// (clears the 150 m floor). Only compactness is anywhere near its floor.
// The inserted midpoint(r0,r1) does not change any of these four values -
// see _mid's doc comment above.
({List<LatLng> wall, List<LatLng> trail}) _elongatedWallCrossingFixture() {
  const originLat = 34.700000;
  const originLng = 33.000000;
  const wallOffsetLat = 0.00062; // ~69 m - trail start's offset south of the wall
  const wallSpanLng = 0.0026; // ~238 m - wall span, also r0->r1's run east
  const excursionLat = 0.00315; // ~348 m north - stretches the bounding box
  const crossingLng = 0.0007; // ~64 m - keeps the crossing within the wall span

  final r0 = LatLng(originLat - wallOffsetLat, originLng);
  final r1 = LatLng(originLat - wallOffsetLat, originLng + wallSpanLng);
  final r2 = LatLng(originLat - wallOffsetLat + excursionLat, originLng + crossingLng);

  final wall = [
    LatLng(originLat, originLng),
    LatLng(originLat, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng),
  ];

  return (wall: wall, trail: [r0, _mid(r0, r1), r1, r2]);
}

void main() {
  group('owned-zone-edge closure - floor gates via RunRecorderService', () {
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

    // GIVEN a trail closes against an owned zone's edge with a sliver that
    //   clears all four existing geometric floors
    // WHEN _scanForAutoClaim runs
    // THEN onAutoClaim fires exactly once with the sliver-only polygon,
    //   exactly as it would for any other qualifying closure
    test('a sliver clearing all four floors dispatches a claim, unchanged from a self-closure', () async {
      final fixture = _wallCrossingFixture();
      svc.ownedZoneEdgesProvider = () => [fixture.wall];
      svc.injectTrackForTesting(fixture.trail);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'A qualifying owned-edge-assisted sliver must dispatch exactly one claim');
      expect(rejectionCapture.captured, isEmpty);
    });

    // GIVEN the same owned-edge closure, but scaled down so the enclosed
    //   sliver falls below the area floor
    // WHEN _scanForAutoClaim runs
    // THEN onGateRejected fires with areaFloor and no claim is dispatched -
    //   the owned-edge path gets no special-casing around the existing gate
    test('a sliver failing the area floor is rejected exactly like a self-closed loop', () async {
      final fixture = _wallCrossingFixture(scale: 0.05);
      svc.ownedZoneEdgesProvider = () => [fixture.wall];
      svc.injectTrackForTesting(fixture.trail);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'A tiny owned-edge sliver must not dispatch a claim');
      expect(rejectionCapture.captured, hasLength(1));
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.areaFloor);
    });

    // GIVEN an owned-edge closure whose sliver clears area and diagonal but
    //   is too elongated to clear the compactness floor, WITH shape gates ON
    // WHEN _scanForAutoClaim runs
    // THEN onGateRejected fires with compactness and no claim is dispatched
    //
    // Shape gates are off by default now (kEnforceShapeGates in
    // runwar_constants.dart) - this test explicitly re-enables them to prove
    // the owned-edge path still applies compactness exactly like the
    // self-closure path when the flag is on, same reversibility guarantee
    // covered for the self-closure path in auto_claim_test.dart.
    test('shape gates ON: a sliver failing the compactness floor is rejected exactly like a self-closed loop', () async {
      svc.debugSetEnforceShapeGates(true);
      final fixture = _elongatedWallCrossingFixture();
      svc.ownedZoneEdgesProvider = () => [fixture.wall];
      svc.injectTrackForTesting(fixture.trail);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'An elongated owned-edge sliver must not dispatch a claim');
      expect(rejectionCapture.captured, hasLength(1));
      expect(rejectionCapture.captured.first.reason, GateRejectionReason.compactness,
          reason: 'The elongated shape must fail specifically on compactness, having already '
              'cleared area and diagonal');
    });

    // Mirror of the test above with the shipped default (shape gates OFF):
    // the SAME elongated sliver now claims, because only the area floor
    // gates it - the owned-edge path gets no special-casing around the
    // shape-gate flag either.
    test('shape gates OFF (default): the same elongated sliver now dispatches a claim', () async {
      final fixture = _elongatedWallCrossingFixture();
      svc.ownedZoneEdgesProvider = () => [fixture.wall];
      svc.injectTrackForTesting(fixture.trail);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'With shape gates off, only the area floor gates a claim - the elongated '
              'sliver clears it (~8154 sqm) so it must now dispatch');
      expect(rejectionCapture.captured, isEmpty);
    });

    // GIVEN a runner's trail runs along what would be a rival zone's edge,
    //   simulated here by an ownedZoneEdgesProvider that returns nothing
    //   (rival zones are filtered out before reaching this callback, per
    //   AC-3's structural guarantee)
    // WHEN _scanForAutoClaim runs
    // THEN no claim fires from an owned-edge-style closure, and the
    //   existing self-closure path (which finds nothing in this 3-point
    //   trail either) is the only mechanism evaluated
    test('a rival-zone-edge-style crossing never dispatches a claim when the wall is not owned', () async {
      final fixture = _wallCrossingFixture();
      svc.ownedZoneEdgesProvider = () => const [];
      svc.injectTrackForTesting(fixture.trail);
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, isEmpty,
          reason: 'A wall geometrically identical to Z1 but never supplied as an owned edge '
              'must never trigger a claim');
    });
  });
}
