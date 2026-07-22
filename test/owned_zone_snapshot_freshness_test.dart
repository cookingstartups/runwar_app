// test/owned_zone_snapshot_freshness_test.dart
//
// zonesProvider(city) is a StreamProvider.autoDispose. Riverpod's
// invalidate() only schedules a resubscription - it keeps serving the
// previous cached value until the resubscribed stream actually emits, which
// happens asynchronously. RunRecorderNotifier.confirmClaim invalidates
// zonesProvider right after a successful claim, so a synchronous read of it
// immediately afterwards - exactly what the next scan does through
// ownedZoneEdgesProvider - can still miss the zone that claim just produced.
//
// This test drives the real ownedZoneEdgesProvider closure and the real
// self-intersection scan (RunRecorderService), not just provider state, so
// it fails only when a lasso closed against the just-claimed edge is
// actually missed.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:runwar_app/providers/auth_provider.dart';
import 'package:runwar_app/providers/run_recorder_provider.dart';
import 'package:runwar_app/providers/zones_provider.dart';
import 'package:runwar_app/services/auth_service.dart';
import 'package:runwar_app/services/database/models/zone.dart';
import 'package:runwar_app/services/database/zones_repository.dart';
import 'package:runwar_app/services/run_recorder_service.dart';

import '_helpers/test_container.dart' show makeTestContainer;

const _kUserId = 'runner-1';
const _kCity = 'Valencia';
const _kZoneId = 'zone-just-claimed';

class MockZonesRepository extends Mock implements ZonesRepository {}

/// Same shape as run_recorder_provider.dart's own Ref requirement - a real
/// Ref is only obtainable through a provider, so this exposes one from the
/// test container.
final _refProvider = Provider<Ref>((ref) => ref);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier() : super(AuthService.instance) {
    state = const AuthState(user: {'id': _kUserId});
  }
}

// A midpoint of a->b, collinear with the segment it splits. Inserting one
// into a trail adds a point (and therefore a segment) without changing the
// resulting captured polygon's area, diagonal, compactness, or path length
// at all - used below to keep the wall-crossing trail at or above the
// consumed-span dedup gate's 4-segment floor (kMinNewLoopTrailSegments)
// while leaving every other measured property of the fixture untouched.
LatLng _mid(LatLng a, LatLng b) =>
    LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2);

// Same wall/trail geometry family used by
// rehydrated_owned_edge_closure_test.dart: a single-edge owned-zone wall
// plus a 4-point trail (r0, its midpoint with r1, r1, r2) whose newest
// segment crosses it, clearing every capture floor (area, diagonal,
// compactness, path length) on its own. The midpoint exists only to clear
// the consumed-span dedup gate's 4-segment floor; it does not change the
// captured polygon's geometry.
({List<LatLng> wall, List<LatLng> trail}) _wallCrossingFixture() {
  const originLat = 34.700000;
  const originLng = 33.000000;
  const wallOffsetLat = 0.0008141;
  const wallSpanLng = 0.0009832;
  const excursionLat = 0.0009950;
  const crossingLng = 0.0008739;

  const r0 = LatLng(originLat - wallOffsetLat, originLng);
  const r1 = LatLng(originLat - wallOffsetLat, originLng + wallSpanLng);
  const r2 = LatLng(originLat - wallOffsetLat + excursionLat, originLng + crossingLng);

  const wall = [
    LatLng(originLat, originLng),
    LatLng(originLat, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng + wallSpanLng),
    LatLng(originLat - 0.002, originLng),
  ];

  return (wall: wall, trail: [r0, _mid(r0, r1), r1, r2]);
}

class _AutoClaimCapture {
  final List<List<LatLng>> captured = [];
  Future<void> call(List<LatLng> polygon) async => captured.add(polygon);
}

void main() {
  group('owned-zone snapshot freshness - claim then immediately close', () {
    late MockZonesRepository zonesRepo;
    late ProviderContainer container;
    late RunRecorderNotifier notifier;
    late _AutoClaimCapture claimCapture;
    final svc = RunRecorderService.instance;

    setUp(() {
      zonesRepo = MockZonesRepository();
      // The zones stream never emits the just-claimed zone during this test -
      // this is the worst case of the real race: invalidate() is fired, but
      // the resubscribed stream has not produced a fresh event yet. A
      // correct implementation must not depend on that emission ever
      // arriving in order to see the claim.
      when(() => zonesRepo.watchByCity(_kCity))
          .thenAnswer((_) => const Stream<List<Zone>>.empty());

      container = makeTestContainer(
        zonesRepo: zonesRepo,
        overrides: [
          authProvider.overrideWith((_) => _FixedAuthNotifier()),
        ],
      );
      // Subscribe zonesProvider(_kCity) once, the same way the app does
      // before any claim happens, so its (empty-forever) cache is seeded.
      container.listen(zonesProvider(_kCity), (_, __) {});

      notifier = RunRecorderNotifier(container.read(_refProvider));

      claimCapture = _AutoClaimCapture();
      svc.onAutoClaim = claimCapture.call;
      svc.activeCity = _kCity;
      svc.injectSessionStartTime(DateTime.now().subtract(const Duration(seconds: 90)));
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
      notifier.dispose();
      container.dispose();
    });

    test(
      'a lasso closed against a zone claimed moments earlier is detected',
      () async {
        final fixture = _wallCrossingFixture();

        // Mirrors exactly what confirmClaim does right after a successful
        // claim: register the outline so the next scan can see it, without
        // waiting on zonesProvider's invalidated stream to re-emit (which,
        // per the stub above, never happens in this test).
        notifier.debugRegisterPendingOwnedZoneEdge(_kZoneId, fixture.wall);

        svc.injectTrackForTesting(fixture.trail);
        svc.runScanForAutoClaimForTesting();
        await Future<void>.delayed(Duration.zero);

        expect(
          claimCapture.captured,
          hasLength(1),
          reason: 'The scan must see a zone the instant it is claimed, not '
              'only after zonesProvider happens to re-emit',
        );
      },
    );
  });

  group('owned-zone snapshot freshness - pending entry pruning', () {
    late MockZonesRepository zonesRepo;
    late StreamController<List<Zone>> zonesController;
    late ProviderContainer container;
    late RunRecorderNotifier notifier;
    final svc = RunRecorderService.instance;

    setUp(() {
      zonesRepo = MockZonesRepository();
      zonesController = StreamController<List<Zone>>.broadcast();
      when(() => zonesRepo.watchByCity(_kCity))
          .thenAnswer((_) => zonesController.stream);

      container = makeTestContainer(
        zonesRepo: zonesRepo,
        overrides: [
          authProvider.overrideWith((_) => _FixedAuthNotifier()),
        ],
      );
      container.listen(zonesProvider(_kCity), (_, __) {});

      notifier = RunRecorderNotifier(container.read(_refProvider));
      svc.activeCity = _kCity;
    });

    tearDown(() async {
      svc.reset();
      notifier.dispose();
      await zonesController.close();
      container.dispose();
    });

    test(
      'a pending entry is dropped once the fresh snapshot reports the same zone owned',
      () async {
        final fixture = _wallCrossingFixture();

        notifier.debugRegisterPendingOwnedZoneEdge(_kZoneId, fixture.wall);
        expect(notifier.debugPendingOwnedZoneEdgeCount, 1);

        // Read the merged edges once while the fresh snapshot still has
        // nothing - the pending entry must be the only source and must
        // survive, exactly like the claim-then-close test above.
        svc.injectTrackForTesting(const []);
        svc.runScanForAutoClaimForTesting();
        expect(notifier.debugPendingOwnedZoneEdgeCount, 1);

        // Now the real snapshot catches up and reports the same zone id as
        // owned by this runner - the fresh snapshot has superseded the
        // pending guess, so it must be pruned on the very next scan.
        zonesController.add([
          Zone(
            id: _kZoneId,
            ownerId: _kUserId,
            city: _kCity,
            influenceLevel: 1,
            status: ZoneStatus.owned,
            points: fixture.wall,
          ),
        ]);
        // Let the stream emission propagate into zonesProvider's state.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        svc.runScanForAutoClaimForTesting();

        expect(
          notifier.debugPendingOwnedZoneEdgeCount,
          0,
          reason: 'A pending entry must be pruned once the fresh zones '
              'snapshot reports the same zone id as owned, so it never '
              'serves a stale shape and never grows unbounded across a run',
        );
      },
    );
  });
}
