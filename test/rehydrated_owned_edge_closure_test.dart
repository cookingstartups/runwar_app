// test/rehydrated_owned_edge_closure_test.dart
//
// The rehydration rescan that runs after resumeFromScratch must apply the
// same owned-zone-edge wall test the live scan already applies. Before the
// fix, _rescanRehydratedTrack called detectSelfIntersection with no
// ownedZoneEdges argument, so a closure that only exists because the
// newest segment crosses a zone the runner already owns was silently
// invisible to the rehydration path - once the trail advanced past that
// pair, the closure could never be detected again on any later scan.
//
// This test exercises the real rehydration code path end to end (track,
// owned-edge provider, gate floors, auto-claim dispatch) rather than
// inspecting source text, so it fails only when the runtime behaviour is
// actually wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

class _AutoClaimCapture {
  final List<List<LatLng>> captured = [];
  Future<void> call(List<LatLng> polygon) async => captured.add(polygon);
}

// Same geometry shape as owned_edge_closure_gating_test.dart's
// _wallCrossingFixture: a single-edge owned-zone wall plus a 3-point trail
// whose newest segment crosses it, producing a sliver that clears all four
// capture floors (area, diagonal, compactness, path length) on its own.
({List<LatLng> wall, List<LatLng> trail}) _wallCrossingFixture() {
  const originLat = 34.700000;
  const originLng = 33.000000;
  const wallOffsetLat = 0.0008141;
  const wallSpanLng = 0.0009832;
  const excursionLat = 0.0009950;
  const crossingLng = 0.0008739;

  const r0 = LatLng(originLat - wallOffsetLat, originLng);
  const r1 = LatLng(originLat - wallOffsetLat, originLng + wallSpanLng);
  const r2 = LatLng(originLat - wallOffsetLat + excursionLat, originLng + crossingLng);

  const wall = [
    LatLng(originLat, originLng),
    LatLng(originLat, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng),
  ];

  return (wall: wall, trail: [r0, r1, r2]);
}

void main() {
  group('rehydration rescan - owned-zone-edge wall closure', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      svc.onAutoClaim = claimCapture.call;
      // Past the 60-second post-start gate so the only thing left to prove
      // is whether the owned-edge wall test itself runs on this path.
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
    });

    tearDown(() => svc.reset());

    // GIVEN a track rehydrated after an app kill, whose only loop closure
    //   is a crossing against a zone the runner already owns
    // WHEN the rehydration rescan runs (the path resumeFromScratch calls
    //   after replaying scratch rows on next launch)
    // THEN the same owned-edge wall closure the live scan would have caught
    //   dispatches a claim - it must not be lost just because the app was
    //   killed before the live scan reached it
    test('a closure that only exists via an owned-zone wall is detected on replay', () async {
      final fixture = _wallCrossingFixture();
      svc.ownedZoneEdgesProvider = () => [fixture.wall];
      svc.injectTrackForTesting(fixture.trail);

      await svc.rescanRehydratedTrackForTesting();

      expect(claimCapture.captured, hasLength(1),
          reason: 'The rehydration rescan must run the owned-edge wall test, '
              'exactly like the live scan, so this closure is not lost forever '
              'once the trail has advanced past it');
    });
  });
}
