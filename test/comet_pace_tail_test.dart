// test/comet_pace_tail_test.dart
//
// T0600 - dashed/thinner run trail + pace-dependent comet tail.
//
// Group 1: source inspection - the persisted trail Polyline on map_screen.dart
//          renders dashed and thinner than before (isDotted: true, strokeWidth 2).
// Group 2: unit tests - pace -> tail window/length mapping in runner_comet.dart
//          (mocked "pace" is just a speedMps double passed directly into the
//          pure helper functions - no GPS/service plumbing needed).
// Group 3: unit tests - selectCometTailForDistance picks a shorter trailing
//          slice for a short distance and a longer one for a longer distance,
//          proving the effective tail window is pace-reactive end to end.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/widgets/runner_comet.dart';

void main() {
  group('Trail rendering - dashed and thinner (source inspection)', () {
    // FlutterMap widget tests generate hundreds of tile-fetch exceptions in
    // this test environment (see infra/protocols/flutter-test-patterns.md
    // #2) - source inspection is the documented pattern for this class of AC.
    final src = File('lib/screens/map_screen.dart').readAsStringSync();

    test('own-player trail Polyline uses isDotted: true', () {
      expect(src, contains('isDotted: true'),
          reason: 'Trail must render dashed, not solid (T0600)');
    });

    test('own-player trail Polyline strokeWidth is thinner than the old solid 4px line', () {
      expect(src, contains('strokeWidth: 2'),
          reason: 'Trail must be thinner than the previous strokeWidth: 4 (T0600)');
      expect(src, isNot(contains('strokeWidth: 4,')),
          reason: 'The old solid 4px trail strokeWidth must no longer be present');
    });
  });

  group('Pace-dependent comet tail window (mocked pace input)', () {
    // GIVEN a runner at walking pace (<= kCometPaceMinSpeedMps)
    // WHEN the tail window is computed
    // THEN it is clamped to the minimum window (5s)
    test('slow pace (walking, 0.5 m/s) yields the minimum 5s tail window', () {
      final windowSec = cometTailWindowSecondsForSpeed(0.5);
      expect(windowSec, equals(kCometPaceTailMinSec));
    });

    // GIVEN a runner at fast running pace (>= kCometPaceMaxSpeedMps)
    // WHEN the tail window is computed
    // THEN it is clamped to the maximum window (15s)
    test('fast pace (running, 5.0 m/s) yields the maximum 15s tail window', () {
      final windowSec = cometTailWindowSecondsForSpeed(5.0);
      expect(windowSec, equals(kCometPaceTailMaxSec));
    });

    // GIVEN a runner at the exact midpoint speed between min and max
    // WHEN the tail window is computed
    // THEN it is exactly halfway between the min and max window
    test('mid pace (2.5 m/s, the midpoint) yields a 10s tail window', () {
      final windowSec = cometTailWindowSecondsForSpeed(2.5);
      expect(windowSec, closeTo(10.0, 0.001));
    });

    // GIVEN two speeds, a slow jog and a fast run
    // WHEN the tail length in meters is computed for each
    // THEN the fast pace produces a strictly longer tail than the slow pace
    test('a faster pace produces a longer tail length in meters than a slower pace', () {
      final slowTailMeters = cometTailLengthMetersForSpeed(1.2); // slow jog
      final fastTailMeters = cometTailLengthMetersForSpeed(3.8); // fast run

      expect(fastTailMeters, greaterThan(slowTailMeters),
          reason: 'Fast pace must yield a visibly longer comet tail than slow pace');
    });

    // GIVEN the walking-pace floor
    // WHEN tail length in meters is computed
    // THEN it equals kCometPaceMinSpeedMps * kCometPaceTailMinSec exactly
    test('tail length formula matches speed * window at the min-speed floor', () {
      final meters = cometTailLengthMetersForSpeed(kCometPaceMinSpeedMps);
      expect(meters, closeTo(kCometPaceMinSpeedMps * kCometPaceTailMinSec, 0.001));
    });
  });

  group('selectCometTailForDistance - distance-based trailing slice', () {
    LatLng offsetNorth(LatLng origin, double metersNorth) {
      return LatLng(origin.latitude + (metersNorth / 111320.0), origin.longitude);
    }

    // GIVEN a track of 10 points spaced 10m apart (90m total span)
    // WHEN selecting a tail for a short distance (slow pace) vs a long
    //      distance (fast pace)
    // THEN the fast-pace selection includes strictly more points than the
    //      slow-pace selection
    test('a longer requested distance selects more trailing points than a shorter one', () {
      const origin = LatLng(51.5, -0.1);
      final track = List.generate(10, (i) => offsetNorth(origin, i * 10.0));

      final slowTail = selectCometTailForDistance(track, 15.0); // ~ 1-2 segments
      final fastTail = selectCometTailForDistance(track, 70.0); // ~ 7 segments

      expect(fastTail.length, greaterThan(slowTail.length),
          reason: 'A larger pace-derived distance must select a longer trailing slice');
      // Both selections must end at the same head (most recent point).
      expect(slowTail.last, equals(track.last));
      expect(fastTail.last, equals(track.last));
    });

    // GIVEN a track with only 2 points
    // WHEN selecting a tail for any distance
    // THEN both points are returned without error (minimum visible segment)
    test('a track with only 2 points always returns both points', () {
      const origin = LatLng(51.5, -0.1);
      final track = [origin, offsetNorth(origin, 5.0)];

      final tail = selectCometTailForDistance(track, 1.0);

      expect(tail.length, equals(2));
    });
  });
}
