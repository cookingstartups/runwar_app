// test/capture_all_loops_union_test.dart
//
// RED-phase pin for a known auto-claim gap: when a run's GPS trail closes
// multiple loops, RunRecorderService only captures the loops detected after
// the last dispatched claim. After each dispatched auto-claim,
// _loopStartTrailIndex advances to _track.length, which drops earlier trail
// history from the self-intersection scan - so a big loop that closes
// against early trail segments is never detected, and the territory a
// runner actually earned on the ground is not fully captured.
//
// This test replays the Valencia fixture through the real recorder pipeline
// (beginSimulation + injectSimulatedFix, the same synchronous path
// run_replay_simulation_test.dart uses) and asserts that the union of every
// captured polygon covers both a small early loop and a large excursion
// loop closed later in the same run. On current code only two small
// polygons are captured and the large excursion loop is missing entirely.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/geo/lasso.dart';
import 'package:runwar_app/services/run_recorder_service.dart';

class _GpsFix {
  final DateTime t;
  final double lat;
  final double lng;
  const _GpsFix({required this.t, required this.lat, required this.lng});
}

List<_GpsFix> _loadValenciaGpsFixes() {
  final raw = File('assets/fixtures/session-2026-07-18-valencia.json')
      .readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final events = decoded['events'] as List<dynamic>;
  return events
      .where((e) => (e as Map<String, dynamic>)['type'] == 'gps_fix')
      .map((e) {
    final ev = e as Map<String, dynamic>;
    final data = ev['data'] as Map<String, dynamic>;
    return _GpsFix(
      t: DateTime.parse(ev['t'] as String),
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
    );
  }).toList();
}

Position _posAt(DateTime t, double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: t,
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      isMocked: true,
    );

void main() {
  group('capture the union of every loop a runner closes in one session', () {
    test('captures the union of all loops the runner closes, not just the '
        'loops detected after the last dispatched claim', () async {
      final fixes = _loadValenciaGpsFixes();
      expect(fixes, hasLength(69),
          reason: 'Sanity check on the fixture itself - 69 gps_fix events '
              'are expected in the Valencia session recording');

      final svc = RunRecorderService.instanceForTesting();
      svc.setActiveUser('tester-valencia-union');
      svc.onRunUpdate = (_, __) async {};

      final capturedPolygons = <List<LatLng>>[];
      svc.onAutoClaim = (group) async {
        capturedPolygons.addAll(group);
      };

      final started =
          await svc.beginSimulation(simulatedSessionStart: fixes.first.t);
      expect(started, isTrue,
          reason: 'Precondition: the simulation must start cleanly from idle');

      for (final fix in fixes) {
        svc.injectSimulatedFix(_posAt(fix.t, fix.lat, fix.lng));
      }

      // Let any fire-and-forget onAutoClaim futures settle before asserting.
      await Future<void>.delayed(Duration.zero);

      // Probe point inside the big excursion loop the runner closed late in
      // the trail - it does not lie inside either of the two small loops the
      // current (buggy) code captures.
      const bigLoopProbe = LatLng(39.516879, -0.43065);
      // Probe point inside the small early loop.
      const smallLoopProbe = LatLng(39.51975, -0.43328);

      final bigLoopCaptured =
          capturedPolygons.any((p) => pointInPolygon(bigLoopProbe, p));
      final smallLoopCaptured =
          capturedPolygons.any((p) => pointInPolygon(smallLoopProbe, p));

      double totalAreaSqm = 0;
      for (final p in capturedPolygons) {
        totalAreaSqm += polygonArea(p) * 1e6;
      }

      // Diagnostic output for triage - not itself an assertion.
      // ignore: avoid_print
      print('captured ${capturedPolygons.length} polygon(s), '
          'total area ${totalAreaSqm.toStringAsFixed(1)} sqm');
      for (var i = 0; i < capturedPolygons.length; i++) {
        final areaSqm = polygonArea(capturedPolygons[i]) * 1e6;
        // ignore: avoid_print
        print('  polygon $i: ${capturedPolygons[i].length} vertices, '
            '${areaSqm.toStringAsFixed(1)} sqm');
      }

      expect(bigLoopCaptured, isTrue,
          reason: 'The big excursion loop the runner closed against early '
              'trail history must be part of the captured territory - it is '
              'dropped because _loopStartTrailIndex advances to _track.length '
              'after each dispatched claim, removing the early trail segments '
              'the big loop closes against from the self-intersection scan');
      expect(smallLoopCaptured, isTrue,
          reason: 'The small early loop the runner closed must also be part '
              'of the captured territory');
      expect(totalAreaSqm, greaterThan(150000.0),
          reason: 'The union of every closed loop should be on the order of '
              'hundreds of thousands of square metres (the big excursion '
              'loop alone is about 270,005 sqm) - an order of magnitude '
              'above the roughly 25,000 sqm a single-slice capture produces '
              'when only the two small loops are claimed');

      await svc.stopRun();
    });
  });
}
