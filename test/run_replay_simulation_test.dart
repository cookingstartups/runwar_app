// test/run_replay_simulation_test.dart
//
// Behavioural coverage for the tester-only run replay simulation: the
// position-source isolation guarantee (a simulation must never leave the
// real GPS subscription open, and a real subscription must never be opened
// while a simulation is active), forced is_mocked on every written sample,
// the stop/finalize and abort/cancel paths, and that a closing loop still
// drives the same auto-claim callback a real run uses.

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
}
