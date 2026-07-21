// test/run_replay_simulation_test.dart
//
// Behavioural coverage for the tester-only run replay simulation: the
// position-source isolation guarantee (a simulation must never leave the
// real GPS subscription open, and a real subscription must never be opened
// while a simulation is active), forced is_mocked on every written sample,
// the stop/finalize and abort/cancel paths, and that a closing loop still
// drives the same auto-claim callback a real run uses.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

Position _posAt(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 1.0,
      speedAccuracy: 0.0,
      isMocked: true,
    );

class _RunUpdateCapture {
  final List<({String sessionId, Map<String, dynamic> fields})> writes = [];
  Future<void> call(String sessionId, Map<String, dynamic> fields) async {
    writes.add((sessionId: sessionId, fields: fields));
  }
}

class _GpsFixCapture {
  final List<Map<String, dynamic>> writes = [];
  Future<void> call(Map<String, dynamic> sample) async {
    writes.add(sample);
  }
}

List<SimulationFixEvent> _straightLineFixture({required bool fixtureIsMocked}) {
  final base = DateTime.parse('2026-07-18T16:03:00.000Z');
  return [
    SimulationFixEvent(t: base, type: 'run_start', data: const {}),
    SimulationFixEvent(
      t: base.add(const Duration(seconds: 10)),
      type: 'gps_fix',
      data: {
        'lat': 34.700,
        'lng': 33.000,
        'speed_ms': 1.5,
        'is_mocked': fixtureIsMocked,
      },
    ),
    SimulationFixEvent(
      t: base.add(const Duration(seconds: 40)),
      type: 'claim_rejected',
      data: const {'area_sqm': 10.0, 'floor_sqm': 200.0, 'message': 'rejected'},
    ),
    SimulationFixEvent(
      t: base.add(const Duration(seconds: 80)),
      type: 'gps_fix',
      data: {
        'lat': 34.701,
        'lng': 33.001,
        'speed_ms': 1.6,
        'is_mocked': fixtureIsMocked,
      },
    ),
    SimulationFixEvent(
      t: base.add(const Duration(seconds: 120)),
      type: 'user_stop_pressed',
      data: const {},
    ),
  ];
}

// Same A-B-C-D-E crossing shape as auto_claim_test.dart's _figure8Path
// (already proven to clear all four geometric gates), fed as SimulationFixEvents
// with fixture timestamps at [offsets] seconds past [base]. Used by SPEC-0143
// scenarios 3 and 4 to prove the session-elapsed gate reads the fixture's own
// timeline instead of real wall-clock replay time.
List<SimulationFixEvent> _figure8SimFixture({
  required DateTime base,
  required List<int> offsets,
}) {
  const lats = [34.700, 34.700, 34.720, 34.720, 34.700];
  const lngs = [33.000, 33.020, 33.020, 33.000, 33.010];
  return List<SimulationFixEvent>.generate(
    offsets.length,
    (i) => SimulationFixEvent(
      t: base.add(Duration(seconds: offsets[i])),
      type: 'gps_fix',
      data: {'lat': lats[i], 'lng': lngs[i], 'speed_ms': 2.0},
    ),
  );
}

void main() {
  group('run replay simulation - position source isolation', () {
    late RunRecorderService svc;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      svc.setActiveUser('tester-1');
      svc.onRunUpdate = (_, __) async {};
    });

    tearDown(() => svc.reset());

    test('beginSimulation never opens the real GPS subscription', () async {
      // Precondition mirrors a fresh recorder: no real subscription.
      expect(svc.hasRealGpsSubscriptionForTesting, isFalse);

      await svc.beginSimulation();

      // AC: the real subscription stays closed for the entire time a
      // simulation is active - beginSimulation must never call
      // Geolocator.getPositionStream, only cancel-and-null the existing one.
      expect(svc.hasRealGpsSubscriptionForTesting, isFalse);
      expect(svc.isSimulationActive, isTrue);
      expect(svc.trackLengthForTesting, 0,
          reason: '_track must be empty immediately after start, before the '
              'first simulated fix is processed');

      await svc.abortSimulation();
      expect(svc.hasRealGpsSubscriptionForTesting, isFalse,
          reason: 'ending a simulation must never reopen the real stream');
      expect(svc.isSimulationActive, isFalse);
    });

    test('a fresh session id is minted for the simulation session', () async {
      await svc.beginSimulation();
      expect(svc.currentSessionId, isNotNull);
      await svc.abortSimulation();
    });

    test('a real fix cannot be delivered while a simulation is active - '
        'injectSimulatedFix is the only path into _onPosition during a '
        'simulation and the real stream is never subscribed to feed it',
        () async {
      await svc.beginSimulation();
      // The isolation guarantee is structural: since hasRealGpsSubscriptionForTesting
      // is false throughout, there is no live subscription for the device's
      // real sensor to deliver a fix through in the first place.
      expect(svc.hasRealGpsSubscriptionForTesting, isFalse);
      await svc.abortSimulation();
    });
  });

  group('run replay simulation - forced is_mocked and stop path', () {
    late RunRecorderService svc;
    late _GpsFixCapture gpsCapture;
    late _RunUpdateCapture runCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      svc.setActiveUser('tester-1');
      gpsCapture = _GpsFixCapture();
      runCapture = _RunUpdateCapture();
      svc.onGpsFix = gpsCapture.call;
      svc.onRunUpdate = runCapture.call;
    });

    tearDown(() => svc.reset());

    test('every written sample is forced is_mocked true even when the '
        'fixture itself recorded is_mocked false', () async {
      await svc.beginSimulation();
      await svc.runSimulationSequence(
        _straightLineFixture(fixtureIsMocked: false),
        multiplier: 200.0,
      );

      expect(gpsCapture.writes, isNotEmpty);
      for (final row in gpsCapture.writes) {
        expect(row['is_mocked'], isTrue,
            reason: 'simulated writes must always be marked synthetic '
                'regardless of the fixture value');
      }
    });

    test('the runs row created by a simulation is marked is_simulated',
        () async {
      await svc.beginSimulation();

      final stub = runCapture.writes.first;
      expect(stub.fields['is_simulated'], isTrue,
          reason: 'a replay run must be distinguishable from a real run at '
              'the run level, not only through its gps samples');
      expect(stub.fields['status'], 'active');
    });

    test('the fixture user_stop_pressed event exercises the real '
        'stop/finalize path', () async {
      await svc.beginSimulation();
      await svc.runSimulationSequence(
        _straightLineFixture(fixtureIsMocked: false),
        multiplier: 200.0,
      );

      expect(svc.isSimulationActive, isFalse,
          reason: 'user_stop_pressed must end the simulation');
      final completedWrite = runCapture.writes.lastWhere(
        (w) => w.fields['status'] == 'completed',
        orElse: () => (sessionId: '', fields: const {}),
      );
      expect(completedWrite.fields['status'], 'completed',
          reason: 'stopRun() finalize write must fire exactly as it does '
              'for a real run');
      expect(completedWrite.fields['ended_at'], isNotNull);
    });

    test('claim_rejected fixture entries are not replayed as commands',
        () async {
      await svc.beginSimulation();
      // No exception and no onAutoClaim call is expected purely from the
      // historical claim_rejected entry in the fixture.
      var autoClaimCalls = 0;
      svc.onAutoClaim = (_) async {
        autoClaimCalls++;
      };
      await svc.runSimulationSequence(
        _straightLineFixture(fixtureIsMocked: false),
        multiplier: 200.0,
      );
      expect(autoClaimCalls, 0);
    });
  });

  group('run replay simulation - abort leaves no dangling claim', () {
    late RunRecorderService svc;
    late _RunUpdateCapture runCapture;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      svc.setActiveUser('tester-1');
      runCapture = _RunUpdateCapture();
      svc.onRunUpdate = runCapture.call;
    });

    tearDown(() => svc.reset());

    test('aborting mid-simulation cancels the timer, discards the track, '
        'and writes a cancelled status - no claim fires', () async {
      await svc.beginSimulation();
      svc.injectSimulatedFix(_posAt(34.700, 33.000));
      svc.injectSimulatedFix(_posAt(34.701, 33.001));
      expect(svc.trackLengthForTesting, greaterThan(0));

      var autoClaimCalls = 0;
      svc.onAutoClaim = (_) async => autoClaimCalls++;

      await svc.abortSimulation();

      expect(svc.isSimulationActive, isFalse);
      expect(autoClaimCalls, 0);
      final cancelledWrite = runCapture.writes.lastWhere(
        (w) => w.fields['status'] == 'cancelled',
        orElse: () => (sessionId: '', fields: const {}),
      );
      expect(cancelledWrite.fields['status'], 'cancelled');
    });
  });

  group('run replay simulation - real recording never auto-resumes', () {
    test('the recorder stays idle after a simulation ends until an '
        'explicit real startRun() call', () async {
      final svc = RunRecorderService.instanceForTesting();
      svc.setActiveUser('tester-1');
      svc.onRunUpdate = (_, __) async {};

      await svc.beginSimulation();
      await svc.abortSimulation();

      expect(svc.hasRealGpsSubscriptionForTesting, isFalse);
      svc.reset();
    });
  });

  group('run replay simulation - refuses observably instead of silently', () {
    late RunRecorderService svc;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      svc.setActiveUser('tester-1');
      svc.onRunUpdate = (_, __) async {};
    });

    tearDown(() => svc.reset());

    test('beginSimulation refuses and returns false while a real run is '
        'recording, instead of returning void and doing nothing', () async {
      // Drive the recorder into the exact state a live real run leaves it
      // in: stateNotifier == recording. beginSimulation() must not silently
      // no-op here - it must tell its caller it refused.
      svc.stateNotifier.value = RecorderState.recording;

      final started = await svc.beginSimulation();

      expect(started, isFalse,
          reason: 'a caller that gets past the UI guard must still be able '
              'to observe the refusal rather than a silent no-op');
      expect(svc.isSimulationActive, isFalse,
          reason: 'a refused beginSimulation must never flip _simActive');

      svc.stateNotifier.value = RecorderState.idle;
    });

    test('beginSimulation still succeeds normally from idle', () async {
      expect(svc.stateNotifier.value, RecorderState.idle);

      final started = await svc.beginSimulation();

      expect(started, isTrue);
      expect(svc.isSimulationActive, isTrue);

      await svc.abortSimulation();
    });
  });

  // =========================================================================
  // SPEC-0143 Part A: the session-elapsed gate reads the fixture's own
  // timeline during a simulation, not real wall-clock replay time. Scenarios
  // 3 and 4 below (and the mis-seed mirror-image) all call
  // beginSimulation(simulatedSessionStart: ...), which does not exist yet -
  // every test in this group fails to compile ("no named parameter") until
  // beginSimulation's signature change lands. That is expected: the two are
  // compile-coupled by design (design.md section 4).
  // =========================================================================

  group('simulated clock - the session-elapsed gate reads fixture time, not wall-clock replay time', () {
    late RunRecorderService svc;

    setUp(() {
      svc = RunRecorderService.instanceForTesting();
      svc.setActiveUser('tester-1');
      svc.onRunUpdate = (_, __) async {};
    });

    tearDown(() => svc.reset());

    // Scenario 3.
    test('a loop closing after 60s of fixture time claims, even though real wall-clock replay '
        'time is well under a second', () async {
      final base = DateTime.parse('2026-07-18T16:00:00.000Z');
      final events = _figure8SimFixture(base: base, offsets: [5, 10, 15, 20, 65]);
      var claims = 0;
      final started = await svc.beginSimulation(simulatedSessionStart: base);
      expect(started, isTrue);
      svc.onAutoClaim = (_) async => claims++;

      await svc.runSimulationSequence(events, multiplier: 200.0);

      expect(claims, 1,
          reason: 'The gate must read the fixture timeline (65s elapsed) rather than real '
              'wall-clock replay time, which stays under a second at this multiplier');
    });

    // Scenario 4. The numeric elapsed_sec assertion is mandatory, not
    // optional: a guard-tripped wall-clock fallback could also land near 0s
    // and reject, which would make this test pass for the wrong reason.
    test('a loop closing before 60s of fixture time is rejected, with elapsed_sec exactly '
        'matching the fixture clock', () async {
      final base = DateTime.parse('2026-07-18T16:00:00.000Z');
      final events = _figure8SimFixture(base: base, offsets: [5, 10, 15, 20, 30]);
      final rejections = <Map<String, dynamic>>[];
      var claims = 0;
      await svc.beginSimulation(simulatedSessionStart: base);
      svc.onAutoClaim = (_) async => claims++;
      svc.onGateRejected = (reason, details) async {
        if (reason == GateRejectionReason.sessionElapsed) rejections.add(details);
      };

      await svc.runSimulationSequence(events, multiplier: 200.0);

      expect(claims, 0);
      expect(rejections, hasLength(1));
      expect(rejections.first['elapsed_sec'], 30,
          reason: 'elapsed_sec must equal exactly the fixture-clock delta (30s), proving the '
              'gate read the fixture timeline and not a guard-tripped wall-clock fallback');
      expect(svc.clockGuardTripsForTesting, 0,
          reason: 'A correctly-seeded simulation must never trip the clock-domain guard');
    });

    // Mirror-image regression test for the primary failure mode itself: a
    // caller that forgets to pass simulatedSessionStart must not silently
    // claim from a mixed-domain elapsed computation.
    test('omitting simulatedSessionStart while fixture-dated fixes arrive trips the clock-domain guard', () async {
      final base = DateTime.parse('2026-07-18T16:00:00.000Z');
      final events = _figure8SimFixture(base: base, offsets: [5, 10, 15, 20, 65]);
      var claims = 0;
      await svc.beginSimulation();
      svc.onAutoClaim = (_) async => claims++;

      await svc.runSimulationSequence(events, multiplier: 200.0);

      expect(claims, 0,
          reason: 'A mis-seeded session (fixture-dated fixes, wall-clock-dated start) must '
              'never claim through the mixed-domain elapsed value');
      expect(svc.clockGuardTripsForTesting, greaterThan(0),
          reason: 'The guard must trip when the fix stamp and session start are on different '
              'timelines, which is exactly the primary failure mode this design defends against');
    });

    // Deliberate divergence lock: _startedAt must stay wall-clock-dated even
    // when _sessionStartTime becomes fixture-dated, so nobody "fixes" this
    // later and misdates runs.started_at days into the past.
    test('_startedAt stays wall-clock-dated even when the simulated session start is fixture-dated', () async {
      final fixtureStart = DateTime.now().subtract(const Duration(days: 3));
      final before = DateTime.now();
      await svc.beginSimulation(simulatedSessionStart: fixtureStart);
      final after = DateTime.now();

      expect(svc.sessionStartTimeForTesting, fixtureStart,
          reason: '_sessionStartTime must be seeded from the fixture reference');
      expect(
        svc.startedAt!.isAfter(before.subtract(const Duration(seconds: 5))) &&
            svc.startedAt!.isBefore(after.add(const Duration(seconds: 5))),
        isTrue,
        reason: '_startedAt must stay wall-clock-dated (near real now), never adopting the '
              'fixture-dated _sessionStartTime - the two fields deliberately diverge during a replay',
      );

      await svc.abortSimulation();
    });
  });

  // =========================================================================
  // SPEC-0143 Part C: comment correctness. Source-inspection lock, following
  // this repo's established house pattern for AC verification that maps
  // directly to source structure (flutter-test-patterns.md section on
  // routing-guard tests).
  // =========================================================================

  group('session-elapsed gate comment correctness', () {
    test('the stale "re-evaluates on the next fix" claim is gone from the gate comment', () {
      final src = File('lib/services/run_recorder_service.dart').readAsStringSync();
      expect(src, isNot(contains('re-evaluates on the next fix')),
          reason: 'The old comment claimed the crossing re-evaluates on the next fix, which is '
              'factually false - detectSelfIntersection only ever tests the newest segment, so '
              'once the trail advances past this point the same segment pair is never evaluated '
              'again on its own; the comment must describe the actual deferred-retention '
              'mechanism instead');
    });
  });
}
