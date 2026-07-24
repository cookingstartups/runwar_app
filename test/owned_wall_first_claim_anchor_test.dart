// test/owned_wall_first_claim_anchor_test.dart
//
// rw_app-T0602 regression: a first-session claim that closes against a zone
// the player already owns (from an earlier session) must capture only the
// small newly-closed loop, not the whole track walked so far.
//
// Root cause was _scanForAutoClaim anchoring an owned-zone-wall hit at trail
// index 0 whenever _consumedSpans was empty (nothing consumed yet THIS
// session), which conflates "nothing claimed this session" with "no prior
// claim exists anywhere". The fix searches the trail itself for its own
// earlier crossing of the SAME owned wall and anchors there instead.
//
// Geometry: a 100m-square owned zone Z1. The synthetic trail starts ~450m
// south of Z1 (pure transit, must be excluded from the capture), enters Z1
// by crossing its south edge (edge2) once, loops through open ground north
// of Z1, then closes by crossing Z1's north edge (edge0) - this final
// crossing is the owned-zone-wall hit under test. Every crossing here was
// verified with a standalone geometry check before being committed to this
// fixture (no crossings besides the two owned-wall ones and no accidental
// self-intersection against the newest segment).

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

const double _d = 0.0009046; // ~100m in latitude at this location
const double _e = 0.0010923; // ~100m in longitude at this location
const double _baseLat = 34.700;
const double _baseLng = 33.000;

// Owned zone Z1's stored boundary ring, ~100m square.
List<LatLng> _z1Ring() => [
      const LatLng(_baseLat, _baseLng), // corner0
      const LatLng(_baseLat, _baseLng + _e), // corner1
      const LatLng(_baseLat - _d, _baseLng + _e), // corner2
      const LatLng(_baseLat - _d, _baseLng), // corner3
    ];

// A trail with a long transit prefix (must be excluded from the capture),
// one entry crossing into Z1, a small loop through open ground, and a final
// closure back across Z1's wall.
List<LatLng> _trailClosingAgainstOwnedZ1() => [
      const LatLng(_baseLat - 5 * _d, _baseLng + 0.5 * _e), // 0 far south
      const LatLng(_baseLat - 5 * _d, _baseLng + 0.3 * _e), // 1 far south
      const LatLng(_baseLat - 3 * _d, _baseLng + 0.3 * _e), // 2 south of Z1
      const LatLng(_baseLat - 0.5 * _d, _baseLng + 0.3 * _e), // 3 entry into Z1
      const LatLng(_baseLat + 0.8 * _d, _baseLng + 0.6 * _e), // 4 open ground
      const LatLng(_baseLat + 0.8 * _d, _baseLng + 0.9 * _e), // 5 open ground
      const LatLng(_baseLat - 0.3 * _d, _baseLng + 0.9 * _e), // 6 closes on Z1
    ];

class _AutoClaimCapture {
  final List<List<LatLng>> captured = [];
  Future<void> call(List<List<LatLng>> group) async => captured.add(group.first);
}

void main() {
  group('owned-zone-wall first-session claim anchors at the loop entry, not trail index 0', () {
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

    // GIVEN this is the FIRST claim of the session (_consumedSpans empty)
    //   AND the newest segment closes against the wall of a zone already
    //   owned from a prior session
    // WHEN the trail also crossed that same wall earlier THIS session on its
    //   way in
    // THEN the captured polygon starts at that earlier entry crossing, not
    //   trail index 0 - it must contain only the small loop, never the long
    //   transit prefix that walked in from far away.
    test('captures only the small loop, excluding the far transit prefix', () async {
      svc.injectTrackForTesting(_trailClosingAgainstOwnedZ1());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'The closing loop must clear every gate and dispatch exactly one claim');

      final polygon = claimCapture.captured.single;

      // The buggy anchor-at-0 behaviour produces an 8-point polygon (the
      // intersection point plus all 7 trail points, i.e. the whole track).
      // The fix must produce a 5-point polygon: the intersection point plus
      // trail[3..6] (entry, the two open-ground points, and the closing
      // point) - the transit prefix (trail[0..2]) must be excluded.
      expect(polygon, hasLength(5),
          reason: 'The captured polygon must be just the closed loop (entry onward), '
              'not the whole track including the far transit prefix');

      const farTransitLat = _baseLat - 5 * _d;
      expect(
        polygon.any((p) => (p.latitude - farTransitLat).abs() < 1e-9),
        isFalse,
        reason: 'The far transit prefix (trail point 0/1, ~450m south of Z1) must never '
            'appear in the captured polygon',
      );

      // A loop confined to the entry + small open-ground excursion must have
      // a much tighter bounding-box diagonal than the whole ~450m-plus track
      // would produce.
      final lats = polygon.map((p) => p.latitude).toList();
      final latSpan = lats.reduce((a, b) => a > b ? a : b) -
          lats.reduce((a, b) => a < b ? a : b);
      expect(latSpan, lessThan(2 * _d),
          reason: 'The captured polygon must span roughly the small loop only '
              '(~2 zone-widths), not the ~5-zone-width transit prefix');
    });
  });
}
