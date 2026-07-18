// test/run_recorder_proximity_gps_sample_test.dart
//
// The proximity pre-check fast path in _onPosition (used to let a loop-closing
// fix bypass the spacing filter so _scanForAutoClaim can detect the closure)
// must stream every fix it stores to onGpsFix, same as the normal spacing-
// filter path does. Before this fix, fixes that took the fast path were added
// to _track and scanned for auto-claim but never streamed to gps_samples,
// so the persisted track could not reconstruct what the recorder evaluated.

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

class _GpsFixCapture {
  final List<Map<String, dynamic>> captured = [];

  Future<void> call(Map<String, dynamic> sample) async {
    captured.add(sample);
  }
}

Position _fixAt(double lat, double lng) => Position(
      longitude: lng,
      latitude: lat,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      isMocked: false,
    );

void main() {
  group('gps sample integrity - proximity fast path streaming', () {
    late RunRecorderService svc;
    late _GpsFixCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _GpsFixCapture();
      svc.onGpsFix = capture.call;
      svc.setActiveUser('user-1');
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    // GIVEN two stored track points more than kTrackPointSpacingM apart
    // WHEN a third fix arrives within kProximityTriggerM of the first point
    //      (the proximity pre-check fast path, not the spacing filter path)
    // THEN the closing fix is streamed to onGpsFix exactly once, in addition
    //      to the two fixes stored via the normal path.
    test('a fix taking the proximity fast path is still streamed to onGpsFix', () async {
      // First fix: always stored (empty track), goes through the normal path.
      svc.handlePositionForTesting(_fixAt(34.700000, 33.000000));
      await Future<void>.delayed(Duration.zero);

      // Second fix: ~111 m north of the first, clears the 50 m spacing
      // filter, also goes through the normal path.
      svc.handlePositionForTesting(_fixAt(34.701000, 33.000000));
      await Future<void>.delayed(Duration.zero);

      expect(svc.trackLengthForTesting, 2,
          reason: 'Both setup fixes must be stored before the closing fix is tested');
      expect(capture.captured, hasLength(2),
          reason: 'Both setup fixes are stored via the normal spacing-filter path');

      // Third fix: ~11 m from the first stored point, well within
      // kProximityTriggerM (25 m). This takes the proximity fast path,
      // which returns before ever reaching the spacing-filter branch.
      svc.handlePositionForTesting(_fixAt(34.700100, 33.000000));
      await Future<void>.delayed(Duration.zero);

      expect(svc.trackLengthForTesting, 3,
          reason: 'The closing fix must still be appended to the track');
      expect(capture.captured, hasLength(3),
          reason: 'The proximity-path fix must be streamed to onGpsFix exactly once, '
              'in addition to the two normal-path fixes');

      final closingSample = capture.captured.last;
      expect(closingSample['lat'], closeTo(34.700100, 1e-9));
      expect(closingSample['lng'], closeTo(33.000000, 1e-9));
      expect(closingSample['is_mocked'], isFalse);
    });
  });
}
