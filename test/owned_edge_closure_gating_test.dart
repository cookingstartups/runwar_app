// test/owned_edge_closure_gating_test.dart
//
// RED phase - the sliver produced by an owned-zone-edge closure must pass
// through the SAME four geometric floor gates as any other captured
// polygon, with no special-casing. RunRecorderService does not yet expose
// an ownedZoneEdgesProvider field, so every test below fails to compile
// until the implementation lands.
//
// Geometry: the wall and trail fixtures below were hand-derived (no working
// implementation exists yet to verify numerically against) to clear all
// four floors with a reasonable margin, assuming the captured polygon is
// [intersectionPoint, ...trail points from run start through the crossing
// fix]. If the eventual implementation slices the captured polygon
// differently, these fixtures may need re-tuning during GREEN-phase
// verification - flagged explicitly, not silently assumed correct.

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

// A single-edge owned-zone wall, plus a 3-point trail whose newest segment
// crosses it. `scale` uniformly scales every offset from the wall's origin
// corner, so shrinking it (T3) proportionally shrinks area while every
// other property of the shape stays geometrically similar.
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

  return (wall: wall, trail: [r0, r1, r2]);
}

// A deliberately elongated variant: the wall offset and the north excursion
// past it are equal, producing a shape whose area and diagonal both clear
// their floors but whose compactness (area / diagonal^2) falls under 0.15 -
// this isolates the compactness gate specifically, distinct from area/
// diagonal, mirroring auto_claim_test.dart's existing elongated-sliver
// pattern applied to an owned-edge closure instead of a self-closure.
({List<LatLng> wall, List<LatLng> trail}) _elongatedWallCrossingFixture() {
  const originLat = 34.700000;
  const originLng = 33.000000;
  const wallOffsetLat = 0.0008141; // ~90 m
  const wallSpanLng = 0.0009832; // ~90 m
  const excursionLat = 0.0008141; // ~90 m past the wall too - doubles the N-S span

  final r0 = LatLng(originLat - wallOffsetLat, originLng);
  final r1 = LatLng(originLat - wallOffsetLat, originLng + wallSpanLng);
  final r2 = LatLng(originLat - wallOffsetLat + excursionLat, originLng + wallSpanLng * 0.9);

  final wall = [
    LatLng(originLat, originLng),
    LatLng(originLat, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng),
  ];

  return (wall: wall, trail: [r0, r1, r2]);
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
    //   is too elongated to clear the compactness floor
    // WHEN _scanForAutoClaim runs
    // THEN onGateRejected fires with compactness and no claim is dispatched
    test('a sliver failing the compactness floor is rejected exactly like a self-closed loop', () async {
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
