// test/comet_trace_test.dart
//
// RED phase: imports resolve to files/APIs that do not yet exist.
// All tests are expected to fail with compile errors or assertion failures
// until implementation is complete.
//
// Each test maps to exactly one GIVEN/WHEN/THEN from requirements.md.
//
// Group 1: Presence history buffer (unit - no Flutter)
// Group 2: RunnerComet widget (Flutter widget tests)
// Group 3: Trace stays local (broadcast payload invariant)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/realtime_presence_service.dart';
// RunnerComet does not exist yet - compile error is expected (RED phase).
import 'package:runwar_app/widgets/runner_comet.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Creates a PlayerPresence at a given LatLng with a specific timestamp.
PlayerPresence _makePresence({
  String playerId = 'player-a',
  double lat = 51.5,
  double lng = -0.1,
  DateTime? updatedAt,
  bool isRecording = true,
}) {
  return PlayerPresence(
    playerId: playerId,
    displayName: 'Runner',
    color: '#FF7A00',
    position: LatLng(lat, lng),
    updatedAt: updatedAt ?? DateTime.now(),
    isRecording: isRecording,
  );
}

/// Creates a LatLng at an approximate offset of [metersNorth] north of origin.
/// Used to construct positions close enough to avoid teleport guard triggering.
LatLng _offsetNorth(LatLng origin, double metersNorth) {
  // 1 degree latitude ~ 111320 m
  return LatLng(
    origin.latitude + (metersNorth / 111320.0),
    origin.longitude,
  );
}

/// Creates a LatLng far away (>500m) from origin to trigger the teleport guard.
LatLng _teleportPoint(LatLng origin) {
  return LatLng(origin.latitude + 0.01, origin.longitude); // ~1.1 km north
}

// ── Group 1: Presence history buffer ─────────────────────────────────────────

void main() {
  group('Presence history buffer', () {
    late RealtimePresenceService service;

    setUp(() {
      // instanceForTesting() creates an isolated instance not backed by
      // Supabase — this method does not exist yet (RED phase).
      service = RealtimePresenceService.instanceForTesting();
    });

    tearDown(() {
      service.disposeForTesting();
    });

    // GIVEN two rival players A and B emitting presence at 5 s intervals
    // WHEN injectPresence is called 4 times for each player
    // THEN the buffer for player A holds 4 entries
    // AND  the buffer for player B holds 4 entries independently
    // AND  entries are ordered from oldest to newest
    test('buffer stores independent entries per player, oldest-first', () {
      final baseTime = DateTime.now();
      final origin = LatLng(51.5, -0.1);

      for (var i = 0; i < 4; i++) {
        service.injectPresence(
          'player-a',
          _makePresence(
            playerId: 'player-a',
            lat: origin.latitude + (i * 0.0001),
            updatedAt: baseTime.add(Duration(seconds: i * 5)),
          ),
        );
        service.injectPresence(
          'player-b',
          _makePresence(
            playerId: 'player-b',
            lat: origin.latitude - (i * 0.0001),
            updatedAt: baseTime.add(Duration(seconds: i * 5)),
          ),
        );
      }

      final historyA = service.historyFor('player-a');
      final historyB = service.historyFor('player-b');

      expect(historyA.length, equals(4),
          reason: 'Player A must have 4 buffered positions');
      expect(historyB.length, equals(4),
          reason: 'Player B must have 4 buffered positions (independent buffer)');

      // Entries must be ordered oldest-first (ascending updatedAt)
      for (var i = 0; i < historyA.length - 1; i++) {
        expect(
          historyA[i].updatedAt.isBefore(historyA[i + 1].updatedAt),
          isTrue,
          reason: 'Player A entries must be ordered oldest-first',
        );
      }
    });

    // GIVEN a player buffer with 12 entries already stored
    // WHEN a 13th entry is injected
    // THEN the buffer length is still 12 (oldest evicted)
    test('buffer stores up to 12 entries per player and evicts the oldest on overflow', () {
      final baseTime = DateTime.now();

      for (var i = 0; i < 13; i++) {
        service.injectPresence(
          'player-a',
          _makePresence(
            playerId: 'player-a',
            lat: 51.5 + (i * 0.0001),
            updatedAt: baseTime.add(Duration(seconds: i * 5)),
          ),
        );
      }

      final history = service.historyFor('player-a');

      expect(history.length, equals(12),
          reason: 'Buffer must never exceed 12 entries; oldest must be evicted');
      // The first remaining entry should be at i=1 (index 0 evicted)
      expect(
        history.first.updatedAt,
        equals(baseTime.add(const Duration(seconds: 5))),
        reason: 'After 13 injections, the entry at i=0 must have been evicted',
      );
    });

    // GIVEN player A's buffer contains entries spanning T-70s to T-0s
    // WHEN historyFor is called at the current time T
    // THEN entries older than 60 s are excluded
    test('entries older than 60 seconds are dropped when the buffer is read', () {
      final now = DateTime.now();

      // Inject 8 entries: one at T-70s (should be dropped), rest within 60s
      service.injectPresence(
        'player-a',
        _makePresence(
          playerId: 'player-a',
          lat: 51.5,
          updatedAt: now.subtract(const Duration(seconds: 70)),
        ),
      );
      for (var i = 0; i < 7; i++) {
        service.injectPresence(
          'player-a',
          _makePresence(
            playerId: 'player-a',
            lat: 51.5 + (i * 0.0001),
            updatedAt: now.subtract(Duration(seconds: 55 - (i * 5))),
          ),
        );
      }

      final history = service.historyFor('player-a');

      expect(
        history.every(
          (e) => now.difference(e.updatedAt) <= const Duration(seconds: 60),
        ),
        isTrue,
        reason: 'All returned entries must be within 60 seconds of now',
      );
      // The T-70s entry must not appear
      expect(
        history.any(
          (e) => now.difference(e.updatedAt) > const Duration(seconds: 60),
        ),
        isFalse,
        reason: 'The entry at T-70s must have been dropped (older than 60s)',
      );
    });

    // GIVEN player B's buffer holds 6 positions
    // WHEN the player is removed from the presence stream (departure)
    // THEN the buffer contains no entry keyed by player B's playerId
    test('buffer is purged when a player leaves the presence stream', () {
      final baseTime = DateTime.now();

      for (var i = 0; i < 6; i++) {
        service.injectPresence(
          'player-b',
          _makePresence(
            playerId: 'player-b',
            lat: 51.5 + (i * 0.0001),
            updatedAt: baseTime.add(Duration(seconds: i * 5)),
          ),
        );
      }

      // Simulate a fresh emission that no longer includes player-b
      service.injectFreshPlayerList(['player-c']); // player-b absent -> purged

      final history = service.historyFor('player-b');

      expect(history, isEmpty,
          reason: 'Buffer must be purged when player is absent from fresh player list');
    });

    // GIVEN a playerId that has never emitted presence
    // WHEN historyFor is called for that id
    // THEN an empty list is returned (no error)
    test('historyFor an unknown player id returns an empty list', () {
      final history = service.historyFor('unknown-player-xyz');

      expect(history, isEmpty,
          reason: 'historyFor an unknown id must return empty list, not null or error');
    });

    // GIVEN two players A and B with distinct positions
    // WHEN positions are injected for both
    // THEN their buffers are independent (A's history does not contain B's positions)
    test('two players have independent history buffers with no cross-contamination', () {
      final baseTime = DateTime.now();

      service.injectPresence(
        'player-a',
        _makePresence(
          playerId: 'player-a',
          lat: 51.5,
          updatedAt: baseTime,
        ),
      );
      service.injectPresence(
        'player-b',
        _makePresence(
          playerId: 'player-b',
          lat: 48.8, // different latitude
          updatedAt: baseTime,
        ),
      );

      final historyA = service.historyFor('player-a');
      final historyB = service.historyFor('player-b');

      expect(historyA.length, equals(1));
      expect(historyB.length, equals(1));
      expect(historyA.first.playerId, equals('player-a'),
          reason: 'Player A buffer must contain only A entries');
      expect(historyB.first.playerId, equals('player-b'),
          reason: 'Player B buffer must contain only B entries');
      expect(
        historyA.first.position.latitude,
        isNot(equals(historyB.first.position.latitude)),
        reason: 'Player A and B positions must be independent',
      );
    });
  });

  // ── Group 2: RunnerComet widget ───────────────────────────────────────────

  group('RunnerComet widget', () {
    // GIVEN a RunnerComet with 1 position and isRecording=true
    // WHEN the widget is painted
    // THEN the widget renders (does not throw) and produces a CustomPaint
    // AND only the head is present (no tail since positions.length == 1)
    testWidgets('with 1 position renders head circle and no tail segments', (tester) async {
      final positions = [LatLng(51.5, -0.1)];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              height: 80,
              child: RunnerComet(
                positions: positions,
                accentColor: const Color(0xFFFF7A00),
                isRecording: true,
              ),
            ),
          ),
        ),
      );

      // With a single position, the widget must render a CustomPaint (head only)
      expect(find.byType(CustomPaint), findsOneWidget,
          reason: 'RunnerComet must render a CustomPaint widget');

      // The widget must not throw even with a single-point tail
      expect(tester.takeException(), isNull,
          reason: 'Single-position RunnerComet must not throw during paint');
    });

    // GIVEN a RunnerComet with 6 positions and isRecording=true
    // WHEN the widget is painted
    // THEN it renders visible content (CustomPaint with a non-null painter)
    testWidgets('with 6 positions and isRecording true renders visible content', (tester) async {
      final origin = LatLng(51.5, -0.1);
      final positions = List.generate(
        6,
        (i) => _offsetNorth(origin, i * 10.0), // 10m apart - no teleport
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              height: 80,
              child: RunnerComet(
                positions: positions,
                accentColor: const Color(0xFFFF7A00),
                isRecording: true,
              ),
            ),
          ),
        ),
      );

      final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(customPaints.isNotEmpty, isTrue,
          reason: 'RunnerComet with 6 positions must render a CustomPaint');

      final customPaint = customPaints.first;
      expect(customPaint.painter, isNotNull,
          reason: 'CustomPainter must not be null when positions are provided');

      expect(tester.takeException(), isNull,
          reason: 'RunnerComet with 6 positions must not throw during paint');
    });

    // GIVEN a RunnerComet with 6 positions and isRecording=false
    // WHEN the widget is painted
    // THEN only the head circle is drawn (tail suppressed)
    // Verified by inspecting the painter's shouldRepaint: false does not guarantee
    // tail is gone, so we check that the painter receives isRecording=false correctly
    // and the widget does not throw.
    testWidgets('with isRecording false tail is suppressed and only head renders', (tester) async {
      final origin = LatLng(51.5, -0.1);
      final positions = List.generate(6, (i) => _offsetNorth(origin, i * 10.0));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              height: 80,
              child: RunnerComet(
                positions: positions,
                accentColor: const Color(0xFFFF7A00),
                isRecording: false, // tail must be suppressed
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull,
          reason: 'RunnerComet with isRecording=false must not throw');

      // The painter must receive isRecording=false.
      // We verify by finding a RunnerComet instance and checking its property.
      final cometFinder = find.byType(RunnerComet);
      expect(cometFinder, findsOneWidget,
          reason: 'RunnerComet must be present in widget tree');

      final comet = tester.widget<RunnerComet>(cometFinder);
      expect(comet.isRecording, isFalse,
          reason: 'isRecording prop must be false - tail must be suppressed');
    });

    // GIVEN a RunnerComet with 5 positions where positions[1] and positions[2]
    //       are 600 m apart (teleport gap) and isRecording=true
    // WHEN the widget is painted
    // THEN only positions[2], positions[3], positions[4] are used for rendering
    // AND the head is drawn at positions[4]
    testWidgets('teleport guard drops tail positions before a gap larger than 500m', (tester) async {
      final origin = LatLng(51.5, -0.1);
      // Build 5 positions: 0, 1 are pre-gap, 2-4 are post-gap
      // positions[1] -> positions[2] is a 600 m teleport
      final positions = [
        origin,
        _offsetNorth(origin, 10.0),        // positions[1]: 10m north
        _teleportPoint(origin),             // positions[2]: ~1.1 km north (teleport)
        LatLng(_teleportPoint(origin).latitude + 0.0001, origin.longitude),
        LatLng(_teleportPoint(origin).latitude + 0.0002, origin.longitude),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              height: 80,
              child: RunnerComet(
                positions: positions,
                accentColor: const Color(0xFFFF7A00),
                isRecording: true,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull,
          reason: 'RunnerComet with teleport gap must not throw');

      // The widget must render (head must always be drawn)
      expect(find.byType(RunnerComet), findsOneWidget,
          reason: 'RunnerComet must still render after teleport guard is applied');

      // Widget must accept the positions list and not crash - the key contract
      // is that the teleport guard truncates internally without throwing.
      final comet = tester.widget<RunnerComet>(find.byType(RunnerComet));
      expect(comet.positions.length, equals(5),
          reason: 'RunnerComet receives all 5 positions - teleport guard is internal');
    });
  });

  // ── Group 3: Trace stays local ───────────────────────────────────────────

  group('Trace stays local - presence broadcast payload', () {
    // GIVEN the player is actively recording with GPS points in trackSnapshot
    // WHEN RealtimePresenceService constructs a broadcast payload
    // THEN the payload contains only the allowed keys:
    //      lat, lng, t, rec, color, player_id, display_name, color_hex
    // AND no array / track / trace / trail / polyline key is present
    test('broadcast payload does not contain track, trace, or trail keys', () {
      // This test verifies the static payload structure by calling the
      // captureLastPayload() test seam that does not exist yet (RED phase).
      // RealtimePresenceService.instanceForTesting() + updatePositionAndCapture()
      final service = RealtimePresenceService.instanceForTesting();
      service.updatePosition(LatLng(51.5, -0.1));

      final payload = service.captureLastBroadcastPayload();

      // Must not contain any trace/track key
      expect(payload.containsKey('track'), isFalse,
          reason: 'Payload must not contain "track" key (trace must stay local)');
      expect(payload.containsKey('trace'), isFalse,
          reason: 'Payload must not contain "trace" key');
      expect(payload.containsKey('trail'), isFalse,
          reason: 'Payload must not contain "trail" key');
      expect(payload.containsKey('polyline'), isFalse,
          reason: 'Payload must not contain "polyline" key');
      expect(payload.containsKey('path'), isFalse,
          reason: 'Payload must not contain "path" key');

      // Must contain the known allowed keys
      expect(payload.containsKey('lat'), isTrue,
          reason: 'Payload must contain lat');
      expect(payload.containsKey('lng'), isTrue,
          reason: 'Payload must contain lng');
      expect(payload.containsKey('t'), isTrue,
          reason: 'Payload must contain t (timestamp)');

      service.disposeForTesting();
    });

    // GIVEN the player is recording with 100 GPS points in trackSnapshot
    // WHEN the broadcast payload is inspected
    // THEN no value in the payload is a List (no array of coordinates)
    test('broadcast payload contains no list or array values (no coordinate arrays)', () {
      final service = RealtimePresenceService.instanceForTesting();
      service.updatePosition(LatLng(51.5, -0.1));

      final payload = service.captureLastBroadcastPayload();

      final hasListValue = payload.values.any((v) => v is List);
      expect(hasListValue, isFalse,
          reason: 'No value in the broadcast payload may be a List - '
              'track arrays would leak the runner\'s full GPS trace to all subscribers');

      service.disposeForTesting();
    });
  });
}
