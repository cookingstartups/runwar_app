// test/arc_close_expand_owned_zone_test.dart
//
// rw_app-T0604 regression: closing a SHORT arc against existing owned
// territory must produce a captured polygon whose consecutive-vertex hops
// all stay under the server's corrupt-track cap, so the claim reaches
// claim_territory's merge path (runSplitAndMerge -> apply_zone_merge)
// instead of being silently rejected as `corrupt_track`.
//
// Background (rw_app-T0602 -> rw_app-T0604): before the T0602 fix,
// `_scanForAutoClaim` anchored an owned-zone-wall hit at trail index 0
// whenever `_consumedSpans` was empty (first claim of the session). The
// captured polygon then always included a leading edge from the closing
// intersection point straight back to trail[0] - on any run where trail[0]
// sat more than ~2000m away (an ordinary transit prefix on a longer run),
// that single edge tripped `hasCorruptHop`
// (supabase/functions/claim_territory/handler.ts ~line 305), and the Edge
// Function returned a normal 200 `{result:'failed', reason:'corrupt_track'}`
// - client-side this short-circuits in `_onAutoClaimOutcome`
// (map_screen.dart) before any zone-render code runs, which is exactly what
// rw_app-T0604 reported as "closed a loop, saw nothing happen" and "my
// territory didn't expand".
//
// The T0602 fix (`findOwnedWallLoopEntryIdx` in lasso.dart,
// `_ownedWallCaptureAnchorIdx` in run_recorder_service.dart) anchors the
// polygon at the trail's OWN earlier crossing of the same owned wall
// instead, so the leading edge runs from the closing point back to that
// nearby entry crossing - not back to trail[0]. This test proves that edge
// now stays well under the 2000m cap even when trail[0] itself is ~2500m
// away, which is what lets the claim actually reach the server's
// same-owner merge routing (verified correct and unchanged by T0602 - see
// handler.ts:491-564) and expand the player's owned area, rather than
// dying silently at the corrupt-track gate.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

// Mirrors handler.ts's hasCorruptHop cap exactly (claim_territory/handler.ts):
// any single hop beyond this is treated as an obviously-corrupt track.
const double _kCorruptHopCapM = 2000.0;

const double _d = 0.0009046; // ~100m in latitude at this location
const double _e = 0.0010923; // ~100m in longitude at this location
const double _baseLat = 34.700;
const double _baseLng = 33.000;

// Owned zone Z1's stored boundary ring, ~100m square (same fixture geometry
// as owned_wall_first_claim_anchor_test.dart).
List<LatLng> _z1Ring() => [
      const LatLng(_baseLat, _baseLng), // corner0
      const LatLng(_baseLat, _baseLng + _e), // corner1
      const LatLng(_baseLat - _d, _baseLng + _e), // corner2
      const LatLng(_baseLat - _d, _baseLng), // corner3
    ];

// A trail with a LONG (~2500m) transit prefix - long enough that a leading
// edge anchored at trail[0] would alone exceed hasCorruptHop's 2000m cap -
// followed by a short entry crossing into Z1, a small arc through open
// ground, and a closing crossing back across Z1's wall. This is the "SHORT
// arc-close against existing owned territory" scenario rw_app-T0604 asks to
// be retested: the ARC itself (points 2..5 below) is small, only the
// transit walked to reach it is long.
List<LatLng> _trailShortArcAgainstOwnedZ1() => [
      const LatLng(_baseLat - 25 * _d, _baseLng + 0.5 * _e), // 0 far south (~2500m)
      const LatLng(_baseLat - 3 * _d, _baseLng + 0.3 * _e), // 1 south of Z1
      const LatLng(_baseLat - 0.5 * _d, _baseLng + 0.3 * _e), // 2 entry into Z1
      const LatLng(_baseLat + 0.8 * _d, _baseLng + 0.6 * _e), // 3 open ground (arc)
      const LatLng(_baseLat + 0.8 * _d, _baseLng + 0.9 * _e), // 4 open ground (arc)
      const LatLng(_baseLat - 0.3 * _d, _baseLng + 0.9 * _e), // 5 closes on Z1
    ];

class _AutoClaimCapture {
  final List<List<LatLng>> captured = [];
  Future<void> call(List<List<LatLng>> group) async => captured.add(group.first);
}

// Same haversine formula handler.ts's haversineM uses, reimplemented here so
// this test independently verifies the cap rather than importing the
// server-side TS module.
double _haversineM(LatLng a, LatLng b) {
  const earthRadiusM = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final sinLat = math.sin(dLat / 2);
  final sinLng = math.sin(dLng / 2);
  final h = sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
  return earthRadiusM * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _maxConsecutiveHopM(List<LatLng> polygon) {
  double maxHop = 0;
  for (int i = 1; i < polygon.length; i++) {
    final hop = _haversineM(polygon[i - 1], polygon[i]);
    if (hop > maxHop) maxHop = hop;
  }
  return maxHop;
}

void main() {
  group('rw_app-T0604: short arc-close against existing owned territory clears the corrupt-hop cap', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.ownedZoneEdgesProvider = () => [_z1Ring()];
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);
    });

    tearDown(() => svc.reset());

    test('captured polygon has no hop anywhere near hasCorruptHop\'s 2000m cap, '
        'even with a ~2500m transit prefix before the arc', () async {
      svc.injectTrackForTesting(_trailShortArcAgainstOwnedZ1());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'The closing arc must clear every client gate and dispatch exactly one claim');

      final polygon = claimCapture.captured.single;

      // Sanity: the captured polygon must be the small arc only, not the
      // whole track back to the ~2500m-away starting point - otherwise this
      // test would be trivially passing for the wrong reason.
      const farTransitLat = _baseLat - 25 * _d;
      expect(
        polygon.any((p) => (p.latitude - farTransitLat).abs() < 1e-9),
        isFalse,
        reason: 'The ~2500m-away transit start point must never appear in the captured polygon',
      );

      // The regression proper: this is exactly hasCorruptHop's own check
      // (handler.ts), run client-side against the polygon this fix
      // produces. Before the T0602 fix, the leading edge here ran straight
      // from the closing intersection point back to trail[0], ~2500m away
      // - comfortably over the cap, which is what made every such claim
      // die silently as corrupt_track before ever reaching the merge path.
      final maxHop = _maxConsecutiveHopM(polygon);
      expect(maxHop, lessThan(_kCorruptHopCapM),
          reason: 'Every consecutive-vertex hop in the captured polygon must stay under the '
              'server\'s ${_kCorruptHopCapM.toStringAsFixed(0)}m corrupt-track cap - clearing '
              'this is what lets the claim reach runSplitAndMerge/apply_zone_merge and expand '
              'the player\'s owned territory, instead of failing with reason=corrupt_track.');
    });
  });
}
