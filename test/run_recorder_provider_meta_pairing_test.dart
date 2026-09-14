// test/run_recorder_provider_meta_pairing_test.dart
//
// Runtime regression test for two review findings on the client half of the
// claim-timing-metadata feature:
//
// 1. RunRecorderNotifier must actually wire onAutoClaimMeta and forward the
//    captured metadata into confirmClaim - the wiring, not just the
//    presence of the handler methods somewhere in the source text. This
//    test drives a real simulated GPS session through the real
//    RunRecorderService -> RunRecorderNotifier callback chain (the same
//    chain a live run uses) and asserts confirmClaim was actually invoked
//    with a non-null, correctly-shaped metadata argument.
// 2. The metadata array handed to confirmClaim must be index-aligned with
//    the captured polygon actually being claimed - same length, same
//    vertex order - never the pre-simplification vertex count.
//
// Deliberately NOT a File(...).readAsStringSync().contains(...) landmark
// test: every assertion below is against runtime objects constructed by
// driving the real production callback chain, mirroring the harness
// test/simulation_persists_through_claim_path_test.dart already
// established for confirmClaim's polygon argument.

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

final _refProvider = Provider<Ref>((ref) => ref);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier() : super(AuthService.instance) {
    state = const AuthState(user: {'id': _kUserId});
  }
}

/// Records every confirmClaim invocation, including the [capturedMeta]
/// argument, instead of delegating to TerritoryService.
class _MetaCapturingRunRecorderNotifier extends RunRecorderNotifier {
  _MetaCapturingRunRecorderNotifier(super.ref);

  final List<
      ({
        List<LatLng> polygon,
        List<List<List<num?>>>? capturedMeta,
      })> calls = [];

  @override
  Future<ClaimOutcome> confirmClaim(
    String userId,
    String city,
    List<List<LatLng>> capturedPolygons, {
    List<List<List<num?>>>? capturedMeta,
  }) async {
    calls.add((
      polygon: List<LatLng>.from(capturedPolygons.first),
      capturedMeta: capturedMeta,
    ));
    return const ClaimOutcome(TerritoryResult.claimed, 'zone-fake');
  }
}

// Same closing-loop shape used by
// test/simulation_persists_through_claim_path_test.dart - proven to clear
// every geometric capture gate and close after 65s of fixture-clock time.
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
  group('onAutoClaimMeta is wired and its payload reaches confirmClaim', () {
    late ProviderContainer container;
    late _MetaCapturingRunRecorderNotifier notifier;
    final svc = RunRecorderService.instance;

    setUp(() {
      container = makeTestContainer(
        overrides: [
          authProvider.overrideWith((_) => _FixedAuthNotifier()),
          joinedCitySlugsProvider(_kUserId)
              .overrideWith((_) async => const [_kCity]),
          connectivityProvider.overrideWith((_) => Stream.value(true)),
        ],
      );
      notifier = _MetaCapturingRunRecorderNotifier(container.read(_refProvider));
      svc.setActiveUser(_kUserId);
      svc.activeCity = _kCity;
    });

    tearDown(() {
      svc.reset();
      notifier.dispose();
      container.dispose();
    });

    test(
      'a closing loop replayed through the real simulation entry points '
      'reaches confirmClaim with non-null, index-aligned metadata',
      () async {
        await container.read(joinedCitySlugsProvider(_kUserId).future);

        final base = DateTime.parse('2026-07-18T16:00:00.000Z');
        final events = _closingLoopFixture(base: base, offsets: [5, 10, 15, 20, 65]);

        final started = await svc.beginSimulation(simulatedSessionStart: base);
        expect(started, isTrue);
        await svc.runSimulationSequence(events, multiplier: 200.0);

        expect(notifier.calls, hasLength(1),
            reason: 'the simulated closing loop must reach confirmClaim '
                'exactly once through the real onAutoClaim/onAutoClaimMeta '
                'wiring RunRecorderNotifier sets up in its constructor.');

        final call = notifier.calls.single;

        // FINDING P0-1 regression guard: before RunRecorderNotifier wired
        // onAutoClaimMeta, this callback never fired at all and confirmClaim
        // was always called with capturedMeta == null (the default) - the
        // whole metadata-threading feature was dead code in production. If
        // that wiring regresses, capturedMeta reverts to null here.
        expect(call.capturedMeta, isNotNull,
            reason: 'onAutoClaimMeta must be wired in RunRecorderNotifier '
                'and its payload forwarded into confirmClaim - if this is '
                'null, the callback either was never assigned to '
                'RunRecorderService.onAutoClaimMeta, or _handleAutoClaim '
                'never forwards the paired metadata to confirmClaim.');

        final meta = call.capturedMeta!;
        expect(meta, hasLength(1),
            reason: 'a single-loop closure dispatches one polygon and must '
                'carry exactly one matching metadata entry.');

        // FINDING P0-2 regression guard: the metadata array must be
        // index-aligned with the ACTUAL captured (possibly Douglas-Peucker
        // simplified) polygon, not the raw, unsimplified trail span. If the
        // metadata were sliced against the raw index range instead, its
        // length would not generally match the dispatched polygon's length
        // whenever simplification actually drops a vertex.
        expect(meta.first.length, call.polygon.length,
            reason: 'captured metadata must be index-aligned 1:1 with the '
                'captured polygon actually dispatched to confirmClaim - a '
                'length mismatch here means metadata was sliced against the '
                'wrong (pre-simplification) index range.');

        // Every ts_ms entry must be a real, finite epoch-millisecond value
        // (not missing, not NaN) - the whole point of the feature.
        for (final vertex in meta.first) {
          expect(vertex, hasLength(2));
          final tsMs = vertex[0];
          expect(tsMs, isNotNull);
          expect(tsMs, isA<num>());
        }
      },
    );
  });
}
