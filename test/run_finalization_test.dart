// test/run_finalization_test.dart
//
// Covers the fix for runs.ended_at / runs.distance_m always landing NULL:
// stopRun and cancelRun must write a real ended_at, a distance computed from
// the recorded track, and finalized_at, via the onRunUpdate callback.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/geo/lasso.dart' show trackDistanceM;
import 'package:runwar_app/services/run_recorder_service.dart';

// ---------------------------------------------------------------------------
// Stub for the onRunUpdate callback. Records every (sessionId, fields) pair
// so tests can assert on exactly what would have been written to the runs
// table.
// ---------------------------------------------------------------------------

class _RunUpdateCapture {
  final List<({String sessionId, Map<String, dynamic> fields})> captured = [];

  Future<void> call(String sessionId, Map<String, dynamic> fields) async {
    captured.add((sessionId: sessionId, fields: fields));
  }
}

void main() {
  group('trackDistanceM', () {
    test('returns 0 for an empty track', () {
      expect(trackDistanceM(const []), 0.0);
    });

    test('returns 0 for a single-point track', () {
      expect(trackDistanceM([const LatLng(34.7, 33.0)]), 0.0);
    });

    test('accumulates great-circle distance over consecutive points', () {
      // Two points exactly 0.001 degrees of latitude apart, near the equator
      // scale used elsewhere in this file, are roughly 111 m apart.
      // Three collinear points should sum to the same distance as one
      // straight segment covering the same span.
      const a = LatLng(34.700000, 33.000000);
      const b = LatLng(34.701000, 33.000000);
      const c = LatLng(34.702000, 33.000000);

      final oneSegment = trackDistanceM([a, c]);
      final twoSegments = trackDistanceM([a, b, c]);

      expect(twoSegments, closeTo(oneSegment, 0.5),
          reason: 'summing two collinear legs should match the direct '
              'distance between the endpoints');
      // Roughly 222 m over 0.002 degrees latitude (about 111 m per 0.001deg).
      expect(oneSegment, greaterThan(200));
      expect(oneSegment, lessThan(240));
    });

    test('a closed loop back to the start point still counts the return leg',
        () {
      const a = LatLng(34.700000, 33.000000);
      const b = LatLng(34.701000, 33.000000);
      final loop = trackDistanceM([a, b, a]);
      final leg = trackDistanceM([a, b]);
      expect(loop, closeTo(leg * 2, 0.5));
    });
  });

  group('stopRun writes ended_at, distance_m and finalized_at', () {
    late RunRecorderService svc;
    late _RunUpdateCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _RunUpdateCapture();
      svc.onRunUpdate = capture.call;
      svc.setActiveUser('user-1');
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    test('a completed run gets a non-null ended_at, distance_m and finalized_at',
        () async {
      svc.injectTrackForTesting(const [
        LatLng(34.700000, 33.000000),
        LatLng(34.701000, 33.000000),
        LatLng(34.702000, 33.000000),
      ]);

      await svc.stopRun();

      expect(capture.captured, isNotEmpty);
      final fields = capture.captured.last.fields;
      expect(fields['status'], 'completed');
      expect(fields['ended_at'], isNotNull);
      expect(fields['distance_m'], isNotNull);
      expect(fields['distance_m'], greaterThan(0));
      expect(fields['finalized_at'], isNotNull);
      // ended_at and finalized_at land at the same moment as closed_at -
      // stopRun is the only place a completed run's terminal state is ever
      // written.
      expect(fields['ended_at'], fields['closed_at']);
      expect(fields['finalized_at'], fields['closed_at']);
    });

    test('an empty track still finalizes with distance_m of 0, not null',
        () async {
      await svc.stopRun();

      final fields = capture.captured.last.fields;
      expect(fields['distance_m'], 0.0);
      expect(fields['ended_at'], isNotNull);
    });
  });

  group('cancelRun writes ended_at, distance_m and finalized_at', () {
    late RunRecorderService svc;
    late _RunUpdateCapture capture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _RunUpdateCapture();
      svc.onRunUpdate = capture.call;
      svc.setActiveUser('user-1');
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    test('a cancelled run still records a real ended_at and distance_m',
        () async {
      svc.injectTrackForTesting(const [
        LatLng(34.700000, 33.000000),
        LatLng(34.701000, 33.000000),
      ]);

      await svc.cancelRun();

      expect(capture.captured, isNotEmpty);
      final fields = capture.captured.last.fields;
      expect(fields['status'], 'cancelled');
      expect(fields['ended_at'], isNotNull);
      expect(fields['distance_m'], isNotNull);
      expect(fields['distance_m'], greaterThan(0));
      expect(fields['finalized_at'], isNotNull);
    });
  });
}
