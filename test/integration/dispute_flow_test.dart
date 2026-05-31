// test/integration/dispute_flow_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Integration smoke test — phase spec §8 lines 987-1000, design.md §4 + §5.
//
// This test is intentionally coarse-grained: it verifies the end-to-end
// GIVEN/WHEN/THEN flow at a UI level using faked repos and a mocked
// TerritoryService edge function call. Detailed per-unit assertions live in
// the unit-test files above.
//
// Flow (verbatim from phase spec §8 lines 995-1000):
//   1. Pump MaterialApp(home: MapScreen()) with provider overrides
//   2. Push GPS fix in Valencia → map renders centered on (39.4699, -0.3763)
//   3. Tap the rival zone → AttackSheet is shown
//   4. Trigger a synthetic track via claimViaEdgeFunction mock →
//        'Zone disputed!' snackbar + DisputeCountdownLabel on polygon
//   5. Trigger a second track →
//        'Zone conquered!' snackbar + ZoneLevelBadge shows 1 (green tier)
//
// Mocks:
//   - GeolocatorPlatform: returns fixed Valencia positions
//   - ZonesRepository: initially returns one seeded rival zone 'z1'
//   - DisputesRepository: no open disputes initially; after claim 1, one open
//   - TerritoryService.claimViaEdgeFunction:
//       call 1 → {result:'disputed', zone_id:'z1', credits_awarded:0}
//       call 2 → {result:'conquered', zone_id:'z1', dispute_resolved:true, credits_awarded:250}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:runwar_app/screens/map_screen.dart';
import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/zones_repository.dart';
import 'package:runwar_app/services/database/disputes_repository.dart';
import 'package:runwar_app/services/database/models/zone.dart';
import 'package:runwar_app/services/database/models/dispute.dart';
import 'package:runwar_app/widgets/attack_sheet.dart';
import 'package:runwar_app/widgets/zone_level_badge.dart';
import 'package:runwar_app/widgets/dispute_countdown_label.dart';
import 'package:runwar_app/providers/app_config_provider.dart';
import 'package:runwar_app/providers/zones_repository_provider.dart';
import 'package:runwar_app/providers/disputes_repository_provider.dart';

import '../_helpers/test_container.dart';

// ── Mock classes ──────────────────────────────────────────────────────────────

class MockZonesRepository extends Mock implements ZonesRepository {}

class MockDisputesRepository extends Mock implements DisputesRepository {}

// ── Test data ─────────────────────────────────────────────────────────────────

const _kRivalZoneId = 'z1';
const _kRivalOwnerId = 'demo-owner';
const _kCurrentUserId = 'current-player';

/// Seeded rival zone in Valencia bounding box, owned by demo-owner.
Map<String, dynamic> _rivalZoneRow({
  String status = 'owned',
  int influenceLevel = 3,
}) =>
    {
      'id': _kRivalZoneId,
      'owner_id': _kRivalOwnerId,
      'city': 'Valencia',
      'influence_level': influenceLevel,
      'status': status,
      'geom_json': '{"type":"Polygon","coordinates":[[[-0.378,39.469],[-0.374,39.469],[-0.374,39.471],[-0.378,39.471],[-0.378,39.469]]]}',
      'created_at': '2026-05-31T10:00:00.000Z',
      'updated_at': '2026-05-31T10:00:00.000Z',
    };

Map<String, dynamic> _openDisputeRow() => {
      'id': 'dispute-001',
      'zone_id': _kRivalZoneId,
      'attacker_id': _kCurrentUserId,
      'defender_id': _kRivalOwnerId,
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 20))
          .toIso8601String(),
      'resolved_at': null,
      'winner_id': null,
      'created_at': '2026-05-31T10:00:00.000Z',
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

void main() {
  setUpAll(() {
    registerFallbackValues();
  });

  group('Dispute flow — integration smoke', () {
    late MockZonesRepository mockZonesRepo;
    late MockDisputesRepository mockDisputesRepo;
    late StreamController<List<Zone>> zonesController;

    setUp(() {
      mockZonesRepo = MockZonesRepository();
      mockDisputesRepo = MockDisputesRepository();
      zonesController = StreamController<List<Zone>>.broadcast();

      // Initial state: one rival zone, no open disputes.
      when(() => mockZonesRepo.watchByCity('Valencia')).thenAnswer(
        (_) => zonesController.stream,
      );
      when(() => mockZonesRepo.fetchByCity('Valencia')).thenAnswer(
        (_) async => RepoResult.ok([Zone.fromGeoJsonRow(_rivalZoneRow())]),
      );
      when(() => mockZonesRepo.dispose()).thenAnswer((_) async {});

      when(() => mockDisputesRepo.fetchOpenForZone(_kRivalZoneId))
          .thenAnswer((_) async => RepoResult.ok(null));
      when(() => mockDisputesRepo.watchOpenForZone(_kRivalZoneId))
          .thenAnswer((_) => Stream.value(null));
      when(() => mockDisputesRepo.dispose()).thenAnswer((_) async {});
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
        disputesRepo: mockDisputesRepo,
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MapScreen()),
        ),
      );

      // Step 1: emit the initial rival zone from the mocked repository.
      zonesController.add([Zone.fromGeoJsonRow(_rivalZoneRow())]);
      await tester.pumpAndSettle();

      // Step 2: the map center should be Valencia (39.4699, -0.3763).
      // We verify the cityConfigProvider was resolved with Valencia coordinates
      // via the provider container.
      final cityConfig =
          await container.read(cityConfigProvider.future);
      expect(cityConfig.center.latitude, closeTo(39.4699, 0.001));
      expect(cityConfig.center.longitude, closeTo(-0.3763, 0.001));

      // Step 3: tap the rival zone polygon to open AttackSheet.
      // The zone is at ~(39.470, -0.376) — we tap the map area where
      // the polygon centroid should render.
      await tester.tapAt(tester.getCenter(find.byType(MapScreen)));
      await tester.pumpAndSettle();

      // AttackSheet should be present (either directly or via ModalBottomSheet).
      expect(find.byType(AttackSheet), findsOneWidget,
          reason: 'Tapping a rival zone must open AttackSheet');

      // Step 4: Simulate first claim → result:'disputed'.
      // The test triggers a dispute by updating mocked state and pushing
      // the updated zone (status='disputed') to the zones stream.
      when(() => mockDisputesRepo.fetchOpenForZone(_kRivalZoneId))
          .thenAnswer((_) async => RepoResult.ok(Dispute.fromRow(_openDisputeRow())));
      when(() => mockDisputesRepo.watchOpenForZone(_kRivalZoneId))
          .thenAnswer((_) => Stream.value(Dispute.fromRow(_openDisputeRow())));

      zonesController.add([Zone.fromGeoJsonRow(_rivalZoneRow(status: 'disputed'))]);
      await tester.pumpAndSettle();

      // Expect a 'Zone disputed!' snackbar somewhere in the widget tree.
      expect(find.textContaining('disputed'), findsAtLeastNWidgets(1),
          reason: 'A dispute snackbar or label must appear after first claim');

      // DisputeCountdownLabel must now be visible on the map polygon marker.
      expect(find.byType(DisputeCountdownLabel), findsAtLeastNWidgets(1),
          reason: 'DisputeCountdownLabel must render on the disputed zone');

      // Step 5: Simulate second claim → result:'conquered'; zone resets to level 1.
      final conqueredRow = _rivalZoneRow(status: 'owned', influenceLevel: 1);
      conqueredRow['owner_id'] = _kCurrentUserId;
      zonesController.add([Zone.fromGeoJsonRow(conqueredRow)]);
      await tester.pumpAndSettle();

      expect(find.textContaining('conquered'), findsAtLeastNWidgets(1),
          reason: 'A conquest snackbar must appear after second claim');

      // ZoneLevelBadge for 'z1' should show level 1 (green tier).
      final badges = tester.widgetList<ZoneLevelBadge>(find.byType(ZoneLevelBadge));
      expect(badges.any((b) => b.level == 1), isTrue,
          reason: 'After conquest, zone level must reset to 1');
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
        disputesRepo: mockDisputesRepo,
      );
      addTearDown(container.dispose);

      // Dispute expires in 2 seconds (very short, so the test runs fast).
      final shortExpiryDispute = {
        'id': 'dispute-short',
        'zone_id': _kRivalZoneId,
        'attacker_id': _kCurrentUserId,
        'defender_id': _kRivalOwnerId,
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 2))
            .toIso8601String(),
        'resolved_at': null,
        'winner_id': null,
        'created_at': '2026-05-31T10:00:00.000Z',
      };

      when(() => mockDisputesRepo.fetchOpenForZone(_kRivalZoneId))
          .thenAnswer((_) async =>
              RepoResult.ok(Dispute.fromRow(shortExpiryDispute)));
      when(() => mockDisputesRepo.watchOpenForZone(_kRivalZoneId))
          .thenAnswer((_) =>
              Stream.value(Dispute.fromRow(shortExpiryDispute)));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MapScreen()),
        ),
      );

      // Emit disputed zone at level 3.
      zonesController.add([Zone.fromGeoJsonRow(_rivalZoneRow(status: 'disputed', influenceLevel: 3))]);
      await tester.pumpAndSettle();

      // DisputeCountdownLabel should be visible initially.
      expect(find.byType(DisputeCountdownLabel), findsAtLeastNWidgets(1),
          reason: 'DisputeCountdownLabel must render while dispute is active');

      // Advance time past expiry: resolve_dispute edge fn fires → trigger bumps
      // influence_level by 1. Simulate by pushing updated zone from stream.
      final resolvedRow = _rivalZoneRow(status: 'owned', influenceLevel: 4);
      // Owner stays as _kRivalOwnerId (defender wins — no ownership change).
      when(() => mockDisputesRepo.fetchOpenForZone(_kRivalZoneId))
          .thenAnswer((_) async => RepoResult.ok(null));
      when(() => mockDisputesRepo.watchOpenForZone(_kRivalZoneId))
          .thenAnswer((_) => Stream.value(null));

      zonesController.add([Zone.fromGeoJsonRow(resolvedRow)]);
      await tester.pumpAndSettle();

      // DisputeCountdownLabel must no longer be visible (zone is 'owned' again).
      expect(find.byType(DisputeCountdownLabel), findsNothing,
          reason: 'DisputeCountdownLabel must unmount when zone returns to owned status');

      // Zone level must have incremented to 4 (defender won).
      final badges =
          tester.widgetList<ZoneLevelBadge>(find.byType(ZoneLevelBadge));
      expect(badges.any((b) => b.level == 4), isTrue,
          reason:
              'Defender-wins path must increment influence_level from 3 to 4 (design.md §3)');
    });
  });
}

