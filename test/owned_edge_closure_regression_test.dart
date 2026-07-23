// test/owned_edge_closure_regression_test.dart
//
// RED phase - a real, previously-recorded GPS run (self-closed loop only,
// no owned-zone edge involved) must claim identically before and after this
// feature ships. RunRecorderService does not yet expose an
// ownedZoneEdgesProvider field, so this test fails to compile until the
// implementation lands - it directly exercises the "unset provider" default
// path the design relies on for backward compatibility.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

class _AutoClaimCapture {
  final List<List<LatLng>> captured = [];
  Future<void> call(List<List<LatLng>> group) async => captured.add(group.first);
}

// A genuine ~100 m x 100 m self-closing loop, the same proven relative
// shape validated elsewhere in this suite (auto_claim_test.dart's
// _detourThenLargeLoopPath / _figure8Path family).
List<LatLng> _realRecordedRun() {
  const dLat100 = 0.0009046;
  const dLng100 = 0.0010923;
  return [
    const LatLng(34.700000, 33.000000),
    LatLng(34.700000, 33.000000 + dLng100),
    LatLng(34.700000 + dLat100, 33.000000 + dLng100),
    LatLng(34.700000 + dLat100, 33.000000),
    LatLng(34.700000, 33.000000 + dLng100 / 2),
  ];
}

void main() {
  group('non-regression - a real self-closed GPS run claims identically once ownedZoneEdgesProvider exists', () {
    late RunRecorderService svc;
    late _AutoClaimCapture claimCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      claimCapture = _AutoClaimCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);
    });

    tearDown(() => svc.reset());

    // GIVEN the new field defaults to unset (as it does for every session
    //   until RunRecorderNotifier wires it at run-start)
    // WHEN a real, self-closed loop is scanned with no owned-zone data
    //   available at all
    // THEN the claim fires exactly as it did before this feature existed -
    //   no owned-zone edge is consulted, no new gate fires
    test('ownedZoneEdgesProvider defaults to unset and a real self-closed run claims normally', () async {
      expect(svc.ownedZoneEdgesProvider, isNull,
          reason: 'A freshly constructed service must not require the new provider to be set');

      svc.injectTrackForTesting(_realRecordedRun());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'A genuine self-closed loop must still claim with no owned-zone data present');
    });

    // GIVEN the provider IS set, but returns an empty list (no owned zones
    //   nearby)
    // WHEN the same real self-closed loop is scanned
    // THEN the claim fires identically - an empty owned-zone set must be
    //   inert, never suppressing or altering the pre-existing self-closure
    test('a provider returning no owned zones behaves identically to no provider at all', () async {
      svc.ownedZoneEdgesProvider = () => const [];

      svc.injectTrackForTesting(_realRecordedRun());
      svc.runScanForAutoClaimForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(claimCapture.captured, hasLength(1),
          reason: 'An empty owned-zone set must never change the outcome of a real self-closed run');
    });
  });
}
