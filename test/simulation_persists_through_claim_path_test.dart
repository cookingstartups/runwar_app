// test/simulation_persists_through_claim_path_test.dart
//
// Verifies that a finished on-device replay simulation drives the exact same
// claim entry point a real GPS run uses: RunRecorderNotifier.confirmClaim,
// reached through onAutoClaim -> _handleAutoClaim, with no simulation-only
// short-circuit anywhere in between.
//
// The wiring under test (RunRecorderNotifier's constructor sets
// svc.onAutoClaim = _handleAutoClaim unconditionally, and _handleAutoClaim
// resolves user/city and calls confirmClaim unconditionally) is exercised
// for real. Only confirmClaim's own body is replaced in a subclass so the
// test never reaches the network or a live backend - the assertion is that
// the call happens with the simulated polygon, not that the edge function
// call succeeds.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/providers/auth_provider.dart';
import 'package:runwar_app/providers/cities_provider.dart';
import 'package:runwar_app/providers/connectivity_provider.dart';
import 'package:runwar_app/providers/run_recorder_provider.dart';
import 'package:runwar_app/services/auth_service.dart';
import 'package:runwar_app/services/run_recorder_service.dart';
import 'package:runwar_app/services/territory_service.dart';

import '_helpers/test_container.dart' show makeTestContainer;

const _kUserId = 'runner-1';
const _kCity = 'valencia';

// Same Ref-extraction trick used by owned_zone_snapshot_freshness_test.dart:
// RunRecorderNotifier needs a real Ref, which is only obtainable from a
// provider read.
final _refProvider = Provider<Ref>((ref) => ref);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier() : super(AuthService.instance) {
    state = const AuthState(user: {'id': _kUserId});
  }
}

/// Records every confirmClaim invocation instead of delegating to
/// TerritoryService, so the test proves the call happens - with the right
/// arguments - without touching the network or a live backend.
class _ClaimCapturingRunRecorderNotifier extends RunRecorderNotifier {
  _ClaimCapturingRunRecorderNotifier(super.ref);

  final List<({String userId, String city, List<LatLng> polygon})> calls = [];

  @override
  Future<ClaimOutcome> confirmClaim(
    String userId,
    String city,
    List<LatLng> capturedPolygon,
  ) async {
    calls.add((userId: userId, city: city, polygon: List<LatLng>.from(capturedPolygon)));
    return const ClaimOutcome(TerritoryResult.claimed, 'zone-fake');
  }
}

// Same closing-loop shape as run_replay_simulation_test.dart's
// _figure8SimFixture (proven to clear every geometric capture gate and to
// close after 65s of fixture-clock time, past the 60s session-elapsed gate),
// terminated by user_stop_pressed exactly as every bundled fixture is - the
// production launcher never plays a fixture that omits it.
List<SimulationFixEvent> _closingLoopFixture({
  required DateTime base,
  required List<int> offsets,
}) {
  const lats = [34.700, 34.700, 34.720, 34.720, 34.700];
  const lngs = [33.000, 33.020, 33.020, 33.000, 33.010];
  return [
    ...List<SimulationFixEvent>.generate(
      offsets.length,
      (i) => SimulationFixEvent(
        t: base.add(Duration(seconds: offsets[i])),
        type: 'gps_fix',
        data: {'lat': lats[i], 'lng': lngs[i], 'speed_ms': 2.0},
      ),
    ),
    SimulationFixEvent(
      t: base.add(Duration(seconds: offsets.last + 5)),
      type: 'user_stop_pressed',
      data: const {},
    ),
  ];
}

void main() {
  group('a finished simulation reaches the real claim path', () {
    late ProviderContainer container;
    late _ClaimCapturingRunRecorderNotifier notifier;
    final svc = RunRecorderService.instance;

    setUp(() {
      container = makeTestContainer(
        overrides: [
          authProvider.overrideWith((_) => _FixedAuthNotifier()),
          joinedCitySlugsProvider(_kUserId).overrideWith((_) async => const [_kCity]),
          // Avoids a real platform-channel call to connectivity_plus, which
          // has no plugin host in this test environment.
          connectivityProvider.overrideWith((_) => Stream.value(true)),
        ],
      );
      notifier = _ClaimCapturingRunRecorderNotifier(container.read(_refProvider));
      svc.setActiveUser(_kUserId);
      svc.activeCity = _kCity;
    });

    tearDown(() {
      svc.reset();
      notifier.dispose();
      container.dispose();
    });

    test(
      'a closing loop replayed through beginSimulation/runSimulationSequence '
      'invokes confirmClaim with the simulated polygon',
      () async {
        // Resolve joinedCitySlugsProvider before the claim fires - _handleAutoClaim
        // reads it synchronously via .valueOrNull.
        await container.read(joinedCitySlugsProvider(_kUserId).future);

        final base = DateTime.parse('2026-07-18T16:00:00.000Z');
        final events = _closingLoopFixture(base: base, offsets: [5, 10, 15, 20, 65]);

        final started = await svc.beginSimulation(simulatedSessionStart: base);
        expect(started, isTrue);

        await svc.runSimulationSequence(events, multiplier: 200.0);

        expect(notifier.calls, hasLength(1),
            reason: 'a genuine closing loop replayed via the real simulation entry '
                'points must reach RunRecorderNotifier.confirmClaim exactly once, '
                'through the same onAutoClaim wiring a real GPS run uses');
        expect(notifier.calls.single.userId, _kUserId);
        expect(notifier.calls.single.city, 'Valencia');
        expect(notifier.calls.single.polygon.length, greaterThanOrEqualTo(3));
      },
    );

    test(
      'a second simulation run over the same ground reaches confirmClaim again, '
      'the client-side precondition the shipped level-up rule depends on',
      () async {
        await container.read(joinedCitySlugsProvider(_kUserId).future);

        final base = DateTime.parse('2026-07-18T16:00:00.000Z');
        final events = _closingLoopFixture(base: base, offsets: [5, 10, 15, 20, 65]);

        await svc.beginSimulation(simulatedSessionStart: base);
        await svc.runSimulationSequence(events, multiplier: 200.0);
        expect(notifier.calls, hasLength(1));

        // stopRun() (fired by the fixture's own user_stop_pressed event) sets
        // _simActive false synchronously but idles stateNotifier through
        // further awaited steps - mirrors the real gap between a fixture
        // ending and an operator tapping START again.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Same ground, a fresh simulation session.
        final secondBase = base.add(const Duration(minutes: 10));
        final secondEvents = _closingLoopFixture(base: secondBase, offsets: [5, 10, 15, 20, 65]);
        final startedAgain = await svc.beginSimulation(simulatedSessionStart: secondBase);
        expect(startedAgain, isTrue);
        await svc.runSimulationSequence(secondEvents, multiplier: 200.0);

        expect(notifier.calls, hasLength(2),
            reason: 'a repeat simulated run over the same ground must reach '
                'confirmClaim again - nothing in beginSimulation caps a second '
                'pass, so the already-shipped level-cap-only repeat-run rule '
                'applies to it exactly as it does to a real run');
      },
    );
  });
}
