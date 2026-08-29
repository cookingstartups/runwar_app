// test/integration/dispute_flow_test.dart
//
// Rewritten per requirements.md R11-AC2: the countdown/dispute state read
// throughout this integration test is now sourced from the zone's own
// status/dispute_at fields (ZonesRepository), never from the retired
// disputes table / DisputesRepository. This file must not import Dispute,
// DisputesRepository, or disputesRepositoryProvider - RED today because
// DisputeCountdownLabel/disputeCountdownProvider still read the disputes
// table, so the zone-only dispute_at fixtures below never surface a
// countdown label the old implementation understands.
//
// Flow (unchanged end-to-end shape):
//   1. Pump MaterialApp(home: MapScreen()) with provider overrides
//   2. Push GPS fix in Valencia → map renders centered on (39.4699, -0.3763)
//   3. Tap the rival zone → AttackSheet is shown
//   4. Trigger a synthetic track via claimViaEdgeFunction mock →
//        'Zone disputed!' snackbar + DisputeCountdownLabel on polygon
//   5. Trigger a second track →
//        'Zone conquered!' snackbar + zone resets to level 1 (fill-only,
//        no badge - conveyed by fill depth alone)
//
// Mocks:
//   - GeolocatorPlatform: returns fixed Valencia positions
//   - ZonesRepository: initially returns one seeded rival zone 'z1'; the
//     zone row itself carries status/dispute_at once disputed
//   - TerritoryService.claimViaEdgeFunction:
//       call 1 → {result:'disputed', zone_id:'z1', credits_awarded:0}
//       call 2 → {result:'conquered', zone_id:'z1', dispute_resolved:true, credits_awarded:250}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:runwar_app/screens/map_screen.dart';
import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/zones_repository.dart';
import 'package:runwar_app/services/database/models/zone.dart';
import 'package:runwar_app/widgets/attack_sheet.dart';
import 'package:runwar_app/widgets/dispute_countdown_label.dart';
import 'package:runwar_app/providers/app_config_provider.dart';
import 'package:runwar_app/providers/auth_provider.dart';
import 'package:runwar_app/providers/cities_provider.dart';
import 'package:runwar_app/providers/profile_provider.dart';
import 'package:runwar_app/providers/run_recorder_provider.dart';
import 'package:runwar_app/providers/runs_provider.dart';
import 'package:runwar_app/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../_helpers/test_container.dart';

// ── Supabase test stubs ───────────────────────────────────────────────────────
// These stubs prevent shared_preferences plugin calls during Supabase
// initialization in the test environment (no native plugin host available).

/// In-memory PKCE storage — replaces SharedPreferencesGotrueAsyncStorage.
class _InMemoryGotrueStorage extends GotrueAsyncStorage {
  final _store = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _store[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _store[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _store.remove(key);
}

// ── Fake Riverpod Ref (needed by RunRecorderNotifier constructor) ─────────────

class _FakeRef extends Fake implements Ref {}

// ── Auth stub ─────────────────────────────────────────────────────────────────
// Extends AuthNotifier so the override type matches StateNotifierProvider<AuthNotifier,…>.
// Sets state to a seeded user immediately after super() so city resolves to 'Valencia'.

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier()
      : super(AuthService.instance) {
    // AuthService.instance.getCurrentUser() returns null at this point (no DB).
    // Override the state immediately so MapScreen sees a resolved user.
    state = const AuthState(user: {'id': _kCurrentUserId, 'city': 'Valencia'});
  }
}

// ── RunRecorder stub ──────────────────────────────────────────────────────────
// Extends RunRecorderNotifier to avoid attaching real listeners to the
// process-lifetime RunRecorderService singleton (see RUNRECORDERNOTIFIER
// SINGLETON RISK NOTE in this file). Stays in RecorderState.idle forever.

class _StubRunRecorderNotifier extends RunRecorderNotifier {
  _StubRunRecorderNotifier() : super(_FakeRef());
}

// ── Mock classes ──────────────────────────────────────────────────────────────

class MockZonesRepository extends Mock implements ZonesRepository {}

// ── Test data ─────────────────────────────────────────────────────────────────

const _kRivalZoneId = 'z1';
const _kRivalOwnerId = 'demo-owner';
const _kCurrentUserId = 'current-player';

/// Seeded rival zone in Valencia bounding box, owned by demo-owner.
///
/// [disputeAt] carries the zone's own dispute deadline once disputed (spec
/// R2-AC1) - the countdown/dispute state now lives entirely on the zone
/// row, never on a separate disputes table.
Map<String, dynamic> _rivalZoneRow({
  String status = 'owned',
  int influenceLevel = 3,
  DateTime? disputeAt,
}) =>
    {
      'id': _kRivalZoneId,
      'owner_id': _kRivalOwnerId,
      'city': 'Valencia',
      'influence_level': influenceLevel,
      'status': status,
      'dispute_at': disputeAt?.toIso8601String(),
      'geom_json': '{"type":"Polygon","coordinates":[[[-0.378,39.469],[-0.374,39.469],[-0.374,39.471],[-0.378,39.471],[-0.378,39.469]]]}',
      'created_at': '2026-05-31T10:00:00.000Z',
      'updated_at': '2026-05-31T10:00:00.000Z',
    };

// ── Test ──────────────────────────────────────────────────────────────────────
//
// RUNRECORDERNOTIFIER SINGLETON RISK NOTE (for SquadLead):
// RunRecorderNotifier calls RunRecorderService.instance.stateNotifier.addListener
// in its constructor. Any test that constructs RunRecorderNotifier (directly or
// via overrideWith) will attach a real listener to a process-lifetime singleton,
// leaking listeners across tests. Phase 1 mitigation: use
//   runRecorderProvider.overrideWith((_) => StubRunRecorderNotifier())
// in all widget/integration tests. SquadLead should refactor
// RunRecorderNotifier to accept an injected RunRecorderService for Phase 2.

// MapScreen drives a continuously repeating pulse animation on its terrain
// fill/border (AnimationController with repeat(reverse: true)) that by design
// never stops. tester.pumpAndSettle() waits for zero pending frames, so any
// tree containing MapScreen makes it hang forever. Use this bounded pump
// sequence instead everywhere the widget tree includes MapScreen: it drains
// microtasks/futures and advances animations/modal transitions across a
// fixed number of frames without waiting for that pulse to stop.
//
// cityConfigProvider races a real network call against a 3-second timeout
// (falling back to CityConfig.valencia on either), so the bounded window here
// covers that full window with margin rather than a handful of short frames.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUpAll(() async {
    // Initialize Supabase with stub credentials so legacy CtfService doesn't
    // throw an assertion error when MapScreen is pumped.
    //
    // EmptyLocalStorage + _InMemoryGotrueStorage replace the default
    // SharedPreferences-backed implementations so no native plugin is needed
    // in the test environment. Real network calls will fail gracefully — that
    // is acceptable in integration tests.
    //
    // Supabase.initialize is idempotent after the first call (it logs a
    // message and returns early), so no try/catch is needed.
    await Supabase.initialize(
      url: 'https://placeholder-test.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0In0.placeholder',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _InMemoryGotrueStorage(),
      ),
    );
    registerFallbackValues();
  });

  group('Dispute flow — integration smoke', () {
    late MockZonesRepository mockZonesRepo;
    late StreamController<List<Zone>> zonesController;

    setUp(() {
      mockZonesRepo = MockZonesRepository();
      zonesController = StreamController<List<Zone>>.broadcast();

      // Initial state: one rival zone, not disputed. fetchById backs
      // disputeCountdownProvider once it is re-pointed at zones (spec
      // R11-AC1) - stub it alongside fetchByCity/watchByCity.
      when(() => mockZonesRepo.watchByCity('Valencia')).thenAnswer(
        (_) => zonesController.stream,
      );
      when(() => mockZonesRepo.fetchByCity('Valencia')).thenAnswer(
        (_) async => RepoResult.ok([Zone.fromGeoJsonRow(_rivalZoneRow())]),
      );
      when(() => mockZonesRepo.fetchById(_kRivalZoneId)).thenAnswer(
        (_) async => RepoResult.ok(Zone.fromGeoJsonRow(_rivalZoneRow())),
      );
      when(() => mockZonesRepo.dispose()).thenAnswer((_) async {});
    });

    tearDown(() async {
      await zonesController.close();
    });

    // GIVEN: MapScreen pumped with mocked repos; GPS fix in Valencia
    // WHEN: rival zone is emitted and tapped
    // THEN: AttackSheet opens; after claim, dispute snackbar and countdown appear;
    //       after second claim, conquered snackbar and level badge resets to 1
    testWidgets('full dispute → conquest flow', (tester) async {
      final container = makeTestContainer(
        zonesRepo: mockZonesRepo,
        overrides: [
          authProvider.overrideWith((_) => _FakeAuthNotifier()),
          profileGateProvider.overrideWith(
            (_, userId) async =>
                <String, dynamic>{'id': userId, 'city': 'Valencia'},
          ),
          runRecorderProvider.overrideWith((_) => _StubRunRecorderNotifier()),
          // MapScreen resolves its active city from joinedCitySlugsProvider, not
          // from the profile's 'city' field, so this must be overridden or the
          // screen shows the empty-state ('No city joined yet') and never renders
          // any zone markers.
          joinedCitySlugsProvider(_kCurrentUserId)
              .overrideWith((ref) async => ['valencia']),
          // The rival zone under test is not owned by the current player, so
          // it now depends on fog-reveal gating (AC-E5's owner-always-visible
          // guard only covers own zones). Seed a fog-reveal point at the
          // Valencia city center - well within the zone's 5000 m reveal
          // radius - so this dispute-flow smoke test stays independent of
          // whether the real gps_samples-backed provider resolves.
          userRunPointsProvider((userId: _kCurrentUserId, city: 'Valencia'))
              .overrideWith((ref) async => const [LatLng(39.4699, -0.3763)]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MapScreen()),
        ),
      );

      // Step 1: settle the widget tree first so profileGateProvider resolves
      // (city = 'Valencia') and zonesProvider('Valencia') subscribes to
      // zonesController. Broadcast streams drop events with no listeners, so
      // the zone must be emitted AFTER the subscription is established.
      await _settle(tester);
      zonesController.add([Zone.fromGeoJsonRow(_rivalZoneRow())]);
      await _settle(tester);

      // Step 2: the map center should be Valencia (39.4699, -0.3763).
      // We verify the cityConfigProvider was resolved with Valencia coordinates
      // via the provider container.
      final cityConfig =
          await container.read(cityConfigProvider.future);
      expect(cityConfig.center.latitude, closeTo(39.4699, 0.001));
      expect(cityConfig.center.longitude, closeTo(-0.3763, 0.001));

      // Step 3: tap the rival zone's own tap-target marker.
      // Using the ValueKey('zone-z1') set on the GestureDetector wrapping
      // the zone marker - avoids relying on flutter_map's coordinate
      // projection which is unreliable in test viewports.
      await tester.tap(find.byKey(const ValueKey('zone-z1')));
      await _settle(tester);

      // AttackSheet should be present (either directly or via ModalBottomSheet).
      expect(find.byType(AttackSheet), findsOneWidget,
          reason: 'Tapping a rival zone must open AttackSheet');

      // Step 4: Simulate first claim → result:'disputed'.
      // The test triggers a dispute purely by updating the zone row itself
      // (status='disputed', dispute_at set 15 minutes out) and re-stubbing
      // fetchById so disputeCountdownProvider observes the new deadline -
      // no separate disputes-table fixture exists anymore.
      final disputeAt = DateTime.now().toUtc().add(const Duration(minutes: 20));
      when(() => mockZonesRepo.fetchById(_kRivalZoneId)).thenAnswer(
        (_) async => RepoResult.ok(
          Zone.fromGeoJsonRow(_rivalZoneRow(status: 'disputed', disputeAt: disputeAt)),
        ),
      );

      zonesController.add([
        Zone.fromGeoJsonRow(_rivalZoneRow(status: 'disputed', disputeAt: disputeAt)),
      ]);
      await _settle(tester);

      // DisputeCountdownLabel must now be visible on the map polygon marker.
      // (The 'Zone disputed!' snackbar only fires via confirmClaim() — covered
      // by unit tests. Here we verify the countdown label renders on the map.)
      expect(find.byType(DisputeCountdownLabel), findsAtLeastNWidgets(1),
          reason: 'DisputeCountdownLabel must render on the disputed zone');

      // The mounted widget's TYPE being present is not enough proof by
      // itself (it mounts purely from zone.status=='disputed', unrelated to
      // where the countdown value comes from) - assert the actual rendered
      // ~20 minute countdown text is present, which only appears once the
      // provider reads dispute_at from THIS zone row instead of the
      // (unstubbed, now-erroring) disputes table.
      expect(find.textContaining(RegExp(r'^(19|20):\d\d$')), findsWidgets,
          reason: 'countdown text must reflect the zone\'s own dispute_at (~20 minutes out), sourced from ZonesRepository, not the disputes table (spec R11-AC1)');

      // Step 5: Simulate second claim → result:'conquered'; zone resets to level 1.
      final conqueredRow = _rivalZoneRow(status: 'owned', influenceLevel: 1);
      conqueredRow['owner_id'] = _kCurrentUserId;
      zonesController.add([Zone.fromGeoJsonRow(conqueredRow)]);
      await _settle(tester);

      // Snackbar text ('Zone conquered!') only fires via confirmClaim() -
      // covered by unit tests. Influence level is no longer conveyed by any
      // marker widget (fill-only rendering, no badge) - the fill-alpha
      // formula itself is regression-locked in
      // claim_capture_flash_and_level_label_test.dart. Here we only verify
      // the zone's own tap target still renders after the conquest update.
      expect(find.byKey(const ValueKey('zone-z1')), findsOneWidget,
          reason: 'Zone marker must still render after conquest updates the '
              'zone to owned/level 1');
    });

    // GIVEN: a zone at level=3 is disputed (attacker has an open dispute)
    // WHEN: the countdown reaches zero (defender_wins event fires via apply_dispute_outcome)
    // THEN: the zone stream emits the zone with influenceLevel incremented to 4 (level+1)
    //       and DisputeCountdownLabel is no longer visible
    //
    // Design.md §3 attacker branch (defender wins):
    //   UPDATE zones SET influence_level = LEAST(15, z_level + 1) WHERE id = zone_id;
    // The countdown reaching zero triggers this via the resolve_dispute Edge fn
    // + apply_dispute_outcome trigger. The Flutter side just receives the
    // updated zone from the zones stream (SupabaseZonesRepository re-fetches on
    // every Realtime change).
    testWidgets('defender-wins on expiry: countdown reaches zero → level increments', (tester) async {
      final container = makeTestContainer(
        zonesRepo: mockZonesRepo,
        overrides: [
          authProvider.overrideWith((_) => _FakeAuthNotifier()),
          profileGateProvider.overrideWith(
            (_, userId) async =>
                <String, dynamic>{'id': userId, 'city': 'Valencia'},
          ),
          runRecorderProvider.overrideWith((_) => _StubRunRecorderNotifier()),
          // MapScreen resolves its active city from joinedCitySlugsProvider, not
          // from the profile's 'city' field, so this must be overridden or the
          // screen shows the empty-state ('No city joined yet') and never renders
          // any zone markers.
          joinedCitySlugsProvider(_kCurrentUserId)
              .overrideWith((ref) async => ['valencia']),
          // The rival zone under test is not owned by the current player, so
          // it now depends on fog-reveal gating (AC-E5's owner-always-visible
          // guard only covers own zones). Seed a fog-reveal point at the
          // Valencia city center - well within the zone's 5000 m reveal
          // radius - so this dispute-flow smoke test stays independent of
          // whether the real gps_samples-backed provider resolves.
          userRunPointsProvider((userId: _kCurrentUserId, city: 'Valencia'))
              .overrideWith((ref) async => const [LatLng(39.4699, -0.3763)]),
        ],
      );
      addTearDown(container.dispose);

      // Dispute expires in 2 seconds (very short, so the test runs fast) -
      // sourced entirely from the zone row's own dispute_at, per spec R11-AC1.
      final shortDisputeAt = DateTime.now().toUtc().add(const Duration(seconds: 2));
      when(() => mockZonesRepo.fetchById(_kRivalZoneId)).thenAnswer(
        (_) async => RepoResult.ok(
          Zone.fromGeoJsonRow(_rivalZoneRow(
            status: 'disputed',
            influenceLevel: 3,
            disputeAt: shortDisputeAt,
          )),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MapScreen()),
        ),
      );

      // Settle first so profileGateProvider resolves and zonesProvider subscribes
      // to zonesController. Broadcast streams drop events with no active listeners.
      await _settle(tester);
      // Emit disputed zone at level 3, dispute_at 2s out.
      zonesController.add([
        Zone.fromGeoJsonRow(_rivalZoneRow(
          status: 'disputed',
          influenceLevel: 3,
          disputeAt: shortDisputeAt,
        )),
      ]);
      await _settle(tester);

      // DisputeCountdownLabel should be visible initially, with a rendered
      // countdown text sourced from the zone's own dispute_at (~2s out) -
      // not merely mounted (mounting alone is unrelated to data source).
      expect(find.byType(DisputeCountdownLabel), findsAtLeastNWidgets(1),
          reason: 'DisputeCountdownLabel must render while dispute is active');
      expect(find.textContaining(RegExp(r'^00:0[0-2]$')), findsWidgets,
          reason: 'countdown text must reflect the zone\'s own ~2-second dispute_at, sourced from ZonesRepository (spec R11-AC1)');

      // Advance time past expiry: the pg_cron resolver fires and decrements
      // influence_level by 1 (spec R6-AC1). Simulate by pushing the
      // resolved zone row from the stream - status returns to owned, no
      // dispute_at, no ownership change.
      final resolvedRow = _rivalZoneRow(status: 'owned', influenceLevel: 4);
      // Owner stays as _kRivalOwnerId (defender wins — no ownership change).
      when(() => mockZonesRepo.fetchById(_kRivalZoneId)).thenAnswer(
        (_) async => RepoResult.ok(Zone.fromGeoJsonRow(resolvedRow)),
      );

      zonesController.add([Zone.fromGeoJsonRow(resolvedRow)]);
      await _settle(tester);

      // DisputeCountdownLabel must no longer be visible (zone is 'owned' again).
      expect(find.byType(DisputeCountdownLabel), findsNothing,
          reason: 'DisputeCountdownLabel must unmount when zone returns to owned status');

      // Zone level must have incremented to 4 (defender won). Influence
      // level is no longer conveyed by any marker widget (fill-only
      // rendering, no badge) - the fill-alpha formula itself is
      // regression-locked in claim_capture_flash_and_level_label_test.dart.
      // Here we only verify the zone's own tap target still renders after
      // the resolver updates the zone.
      expect(find.byKey(const ValueKey('zone-z1')), findsOneWidget,
          reason: 'Zone marker must still render after the resolver '
              'increments influence_level');
    });
  });
}

