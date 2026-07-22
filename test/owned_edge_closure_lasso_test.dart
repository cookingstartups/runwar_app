// test/owned_edge_closure_lasso_test.dart
//
// RED phase - closing a lasso against the edge of a zone the runner already
// owns. Targets lasso.dart's detectSelfIntersection, which does not yet
// accept an ownedZoneEdges parameter - every test below fails to compile
// ("no named parameter 'ownedZoneEdges'") until the implementation lands.
//
// Geometry note: the wall edge and trail points below reuse the exact
// A/B/C/D/E coordinates already validated by the existing figure-8 fixture
// in auto_claim_test.dart (segment D->E crossing segment A->B at
// (34.700, 33.010), t=0.5, u=1.0) so the crossing algebra is proven, not
// hand-derived fresh.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/geo/lasso.dart';

// Owned zone Z1's stored boundary ring. Its first edge (corner0 -> corner1)
// is exactly the A->B segment from the proven figure-8 fixture.
List<LatLng> _z1Ring() => [
      const LatLng(34.700, 33.000), // corner0 = A
      const LatLng(34.700, 33.020), // corner1 = B
      const LatLng(34.680, 33.020), // corner2
      const LatLng(34.680, 33.000), // corner3
    ];

// A trail with only 3 points: no earlier trail segment exists for the
// newest segment to self-cross against (loopStartTrailIndex's scan range is
// empty), so any closure detected here can only have come from the new
// owned-zone-wall pass, never the pre-existing self-intersection pass.
List<LatLng> _trailApproachingZ1Edge() => [
      const LatLng(34.720, 33.020), // C: open ground, far from Z1
      const LatLng(34.720, 33.000), // D
      const LatLng(34.700, 33.010), // E: newest fix, lands on Z1's edge
    ];

void main() {
  group('owned-zone-edge closure - detectSelfIntersection', () {
    // GIVEN a runner owns Z1 and the newest trail segment crosses Z1's edge
    // WHEN detectSelfIntersection runs with Z1's ring passed as an owned wall
    // THEN it reports a hit flagged as an owned-zone-wall closure, with the
    //   intersection point on Z1's edge rather than a self-crossing
    test('reports a hit against an owned-zone edge when the newest segment crosses it', () {
      final trail = _trailApproachingZ1Edge();
      final result = detectSelfIntersection(
        trail,
        1,
        ownedZoneEdges: [_z1Ring()],
      );

      expect(result, isNotNull,
          reason: 'The newest segment D->E crosses Z1s stored edge and must be detected');
      expect(result!.isOwnedZoneWall, isTrue,
          reason: 'A hit against a supplied owned-zone edge must be distinguishable from a self-closure');
      expect(result.intersectionPoint.latitude, closeTo(34.700, 1e-6),
          reason: 'The intersection point must lie on Z1s edge (lat = 34.700)');
    });

    // GIVEN the same geometry, but no owned zone is supplied (the default)
    // WHEN detectSelfIntersection runs exactly as it does today
    // THEN no closure is reported - real GPS runs and existing self-closed
    //   claims must not regress just because the new parameter exists
    test('without any owned-zone edges supplied, behaviour is unchanged from today', () {
      final trail = _trailApproachingZ1Edge();

      final resultNoArg = detectSelfIntersection(trail, 1);
      expect(resultNoArg, isNull,
          reason: 'With no owned-zone edges, only the pre-existing self-intersection scan runs, '
              'and this 3-point trail has no matching historical segment');

      final resultEmptyList = detectSelfIntersection(trail, 1, ownedZoneEdges: const []);
      expect(resultEmptyList, isNull,
          reason: 'An explicitly empty ownedZoneEdges list must behave identically to the default');
    });

    // GIVEN a rival owns a zone whose edge geometrically coincides with what
    //   would otherwise be a valid wall (same coordinates as Z1 above)
    // WHEN the caller does not include that rival zone in ownedZoneEdges
    //   (rival zones are filtered out upstream, before this function is ever
    //   called - AC-3's structural guarantee)
    // THEN detectSelfIntersection must not manufacture a closure against
    //   geometry it was never given - only rings actually present in
    //   ownedZoneEdges are ever treated as valid closure walls
    test('a zone edge never passed in ownedZoneEdges never becomes a closure wall', () {
      final trail = _trailApproachingZ1Edge();

      // Same crossing geometry as Z1 above, but simulating AC-3: a rival's
      // zone was filtered out before reaching this function, so it is never
      // included in ownedZoneEdges.
      final result = detectSelfIntersection(trail, 1, ownedZoneEdges: const []);

      expect(result, isNull,
          reason: 'A rival boundary that is never included in ownedZoneEdges must never be '
              'treated as a closure wall, regardless of its real-world geometry');
    });
  });
}
