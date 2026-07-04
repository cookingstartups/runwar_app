// test/run_recorder_gps_sample_test.dart
//
// RED phase - R6-AC1, R6-AC2: real-time GPS fixes must propagate the actual
// Position.isMocked flag into the gps_samples payload's 'is_mocked' field,
// instead of the current hardcoded `false` in _onPosition() (design.md
// section 1, run_recorder_service.dart:201).

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

// ---------------------------------------------------------------------------
// Stub for the onGpsFix callback. Records every sample map streamed by
// _onPosition() to the provider layer.
// ---------------------------------------------------------------------------

class _GpsFixCapture {
  final List<Map<String, dynamic>> captured = [];

  Future<void> call(Map<String, dynamic> sample) async {
    captured.add(sample);
  }
}

Position _fixAt({required bool isMocked}) => Position(
      longitude: 33.000000,
      latitude: 34.700000,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      isMocked: isMocked,
    );

void main() {
  group('gps sample integrity - is_mocked propagation (R6)', () {
    late RunRecorderService svc;
    late _GpsFixCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _GpsFixCapture();
      svc.onGpsFix = capture.call;
      svc.setActiveUser('user-1');
      // injectState mints a session id when entering recording, which is a
      // precondition for _onPosition's onGpsFix branch to fire.
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    // GIVEN the recorder is recording
    // WHEN a GPS fix arrives with Position.isMocked == true
    // THEN the sample map passed to onGpsFix contains 'is_mocked': true
    test('a fix flagged as mocked emits is_mocked: true in the gps_samples payload', () async {
      svc.handlePositionForTesting(_fixAt(isMocked: true));
      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, hasLength(1),
          reason: 'The first fix on an empty track is always stored and streamed');
      expect(capture.captured.first['is_mocked'], isTrue,
          reason: 'Position.isMocked == true must propagate through, not be hardcoded to false');
    });

    // GIVEN the recorder is recording
    // WHEN a GPS fix arrives with Position.isMocked == false
    // THEN the sample map passed to onGpsFix contains 'is_mocked': false
    //
    // Regression-lock (requirements.md R6-AC2 invariant): this scenario is
    // already satisfied by today's hardcoded `false`, so it is expected to
    // pass even before the R6-AC1 fix lands - it guards against a future
    // regression once is_mocked reads pos.isMocked dynamically.
    test('a non-mocked fix continues to emit is_mocked: false in the gps_samples payload', () async {
      svc.handlePositionForTesting(_fixAt(isMocked: false));
      await Future<void>.delayed(Duration.zero);

      expect(capture.captured, hasLength(1));
      expect(capture.captured.first['is_mocked'], isFalse,
          reason: 'Non-mocked fixes must continue to emit is_mocked: false');
    });
  });
}
