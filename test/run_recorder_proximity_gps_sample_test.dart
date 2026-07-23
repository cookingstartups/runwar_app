// test/run_recorder_proximity_gps_sample_test.dart
//
// The proximity pre-check fast path in _onPosition (used to let a loop-closing
// fix bypass the spacing filter so _scanForAutoClaim can detect the closure)
// must persist every fix it stores to gps_samples, same as the normal
// spacing-filter path does. Before this fix, fixes that took the fast path
// were added to _track and scanned for auto-claim but never streamed
// anywhere, so the persisted track could not reconstruct what the recorder
// evaluated.
//
// Unlike the spacing-filter path (which streams through onGpsFix, one write
// per fix), the proximity fast path bypasses the spacing filter entirely and
// can fire on every raw GPS fix while a runner lingers near a loop-closing
// point. To avoid turning that into an unbounded stream of single-row
// upserts, proximity-path fixes are buffered in memory and flushed through
// onGpsFixBatch as a single batched write - either once the buffer reaches
// its size threshold, once the flush timer elapses, or when the run ends.

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

class _GpsFixCapture {
  final List<Map<String, dynamic>> captured = [];

  Future<void> call(Map<String, dynamic> sample) async {
    captured.add(sample);
  }
}

class _GpsFixBatchCapture {
  final List<List<Map<String, dynamic>>> flushes = [];

  Future<void> call(List<Map<String, dynamic>> samples) async {
    flushes.add(List<Map<String, dynamic>>.of(samples));
  }

  /// Total number of individual samples across every flush so far, and the
  /// number of separate write calls (flushes.length) - the two diverging is
  /// exactly what proves batching is happening instead of one write per fix.
  int get totalSamples =>
      flushes.fold(0, (sum, batch) => sum + batch.length);
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
    late _GpsFixBatchCapture batchCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      capture = _GpsFixCapture();
      batchCapture = _GpsFixBatchCapture();
      svc.onGpsFix = capture.call;
      svc.onGpsFixBatch = batchCapture.call;
      svc.setActiveUser('user-1');
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    // GIVEN two stored track points more than kTrackPointSpacingM apart
    // WHEN a third fix arrives within kProximityTriggerM of the first point
    //      (the proximity pre-check fast path, not the spacing filter path)
    // THEN the closing fix is buffered rather than dropped, and forcing a
    //      flush persists it exactly once via onGpsFixBatch, in addition to
    //      the two fixes already streamed via the normal path's onGpsFix.
    test('a fix taking the proximity fast path is buffered and flushed, not dropped',
        () async {
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
      expect(svc.proximityGpsBufferLengthForTesting, 1,
          reason: 'The proximity-path fix is buffered, not written immediately');
      expect(batchCapture.flushes, isEmpty,
          reason: 'Below the batch-size threshold, no flush has happened yet');

      svc.flushProximityGpsBufferForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(batchCapture.flushes, hasLength(1),
          reason: 'Forcing a flush persists the buffered proximity fix exactly once');
      expect(batchCapture.flushes.single, hasLength(1));
      final closingSample = batchCapture.flushes.single.single;
      expect(closingSample['lat'], closeTo(34.700100, 1e-9));
      expect(closingSample['lng'], closeTo(33.000000, 1e-9));
      expect(closingSample['is_mocked'], isFalse);
    });

    // GIVEN a run whose track already has one stored vertex
    // WHEN more proximity-fast-path fixes arrive than the batch-size
    //      threshold in quick succession
    // THEN they are written as batched flushes (each flush call carrying
    //      more than one sample on average), never one write per fix.
    test('proximity fixes flush in batches, not one upsert per fix', () async {
      // Seed the track with a single vertex so every subsequent fix within
      // kProximityTriggerM of it takes the proximity fast path.
      svc.handlePositionForTesting(_fixAt(34.700000, 33.000000));
      await Future<void>.delayed(Duration.zero);
      capture.captured.clear();

      // A dead-track guard means the proximity loop only runs once
      // _track.length > 1, so add one more distant point first via the
      // normal path to satisfy that precondition.
      svc.handlePositionForTesting(_fixAt(34.701000, 33.000000));
      await Future<void>.delayed(Duration.zero);

      const fixCount = 12;
      for (var i = 0; i < fixCount; i++) {
        // Each fix is within kProximityTriggerM (25 m) of the first vertex,
        // so every one of them takes the proximity fast path.
        svc.handlePositionForTesting(_fixAt(34.700000 + i * 0.000001, 33.000000));
        await Future<void>.delayed(Duration.zero);
      }

      // Flush whatever is still buffered below the size threshold.
      svc.flushProximityGpsBufferForTesting();
      await Future<void>.delayed(Duration.zero);

      expect(batchCapture.totalSamples, fixCount,
          reason: 'Every proximity-path fix must eventually reach the server');
      expect(batchCapture.flushes.length, lessThan(fixCount),
          reason: 'Batching means far fewer write calls than fixes - '
              'never one upsert per fix');
    });

    // GIVEN a proximity-path fix has been buffered but not yet flushed
    // WHEN the run is stopped
    // THEN stopRun flushes the buffer so the closing fix is never silently
    //      dropped just because the run ended before the timer/threshold
    //      fired.
    test('stopRun flushes any buffered proximity fixes before ending the run',
        () async {
      svc.handlePositionForTesting(_fixAt(34.700000, 33.000000));
      await Future<void>.delayed(Duration.zero);
      svc.handlePositionForTesting(_fixAt(34.701000, 33.000000));
      await Future<void>.delayed(Duration.zero);
      svc.handlePositionForTesting(_fixAt(34.700100, 33.000000));
      await Future<void>.delayed(Duration.zero);

      expect(svc.proximityGpsBufferLengthForTesting, 1,
          reason: 'The closing fix is buffered, awaiting a flush');

      await svc.stopRun();
      await Future<void>.delayed(Duration.zero);

      expect(svc.proximityGpsBufferLengthForTesting, 0,
          reason: 'stopRun must flush the buffer rather than abandon it');
      expect(batchCapture.totalSamples, 1,
          reason: 'The buffered fix must reach onGpsFixBatch once stopRun flushes it');
    });
  });
}
