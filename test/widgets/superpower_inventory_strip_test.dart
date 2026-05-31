// test/widgets/superpower_inventory_strip_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Each test maps to one GIVEN/WHEN/THEN from design.md §6.1/§6.3 + spec §6.5.
//
// Design contract (design.md §6.3 — READ-ONLY by Phase 2 contract):
//   SuperpowerInventoryStrip — ConsumerWidget — watches activeGrantsProvider(playerId)
//   - Renders Chip(label: Text(g.powerType)) for each active grant
//   - Shows Tooltip(message: 'Earned via ${g.source}. Charges left: ${g.chargesRemaining}')
//   - MUST NOT have an onTap handler that opens any dialog or screen
//
// The no-onTap contract is enforced here by asserting there is no GestureDetector
// wrapping the chips with a tap handler registered.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/widgets/superpower_inventory_strip.dart';
import 'package:runwar_app/providers/superpowers/active_grants_provider.dart';
import 'package:runwar_app/services/database/superpowers_repository.dart';

import '../_helpers/test_container.dart';

// ── Fake ─────────────────────────────────────────────────────────────────────

class _FakeSuperpowersRepo implements SuperpowersRepository {
  final List<SuperpowerGrant> _grants;

  _FakeSuperpowersRepo(this._grants);

  @override
  Stream<List<SuperpowerGrant>> watchActiveGrants(String playerId) =>
      Stream.value(_grants);

  @override
  Future<EarnResult> reportEvent(EarnEvent event) async =>
      EarnResult(granted: false);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {required ProviderContainer container}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );

SuperpowerGrant _grant({
  String id = 'g1',
  String powerType = 'RUSH',
  int charges = 1,
  int chargesUsed = 0,
  String source = 'run_end',
}) =>
    SuperpowerGrant(
      id: id,
      playerId: 'player-1',
      powerType: powerType,
      charges: charges,
      chargesUsed: chargesUsed,
      source: source,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SuperpowerInventoryStrip', () {
    // GIVEN activeGrantsProvider resolved with [RUSH, SHIELD]
    // WHEN SuperpowerInventoryStrip(playerId: 'player-1') is rendered
    // THEN shows a Chip for 'RUSH' and a Chip for 'SHIELD'
    testWidgets('renders a Chip for each active grant', (tester) async {
      final grants = [
        _grant(id: 'g1', powerType: 'RUSH'),
        _grant(id: 'g2', powerType: 'SHIELD'),
      ];
      final container = makeTestContainer(
        superpowersRepo: _FakeSuperpowersRepo(grants),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          const SuperpowerInventoryStrip(playerId: 'player-1'),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RUSH'), findsOneWidget,
          reason: 'Must render Chip for RUSH grant');
      expect(find.text('SHIELD'), findsOneWidget,
          reason: 'Must render Chip for SHIELD grant');
    });

    // GIVEN activeGrantsProvider resolved with one GHOST_RUN grant (source='run_end', charges=3, chargesUsed=1)
    // WHEN SuperpowerInventoryStrip is rendered
    // THEN a Tooltip with "Earned via run_end. Charges left: 2" is present
    //
    // IMPLEMENTATION NOTE: The production widget abbreviates power-type names to
    // at most 6 chars for display (e.g. 'GHOST_RUN' → 'GHOST_R'), so we must
    // find the tile via Tooltip widget type, not via text('GHOST_RUN').
    // The Tooltip.message must still contain the full source + chargesRemaining
    // per design.md §6.3.
    testWidgets('Tile has Tooltip with source and charges remaining', (tester) async {
      final grants = [
        _grant(id: 'g1', powerType: 'GHOST_RUN', charges: 3, chargesUsed: 1, source: 'run_end'),
      ];
      final container = makeTestContainer(
        superpowersRepo: _FakeSuperpowersRepo(grants),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          const SuperpowerInventoryStrip(playerId: 'player-1'),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Find the Tooltip widget and verify its message directly.
      // chargesRemaining = 3 - 1 = 2
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip).first);
      expect(tooltip.message, contains('Charges left: 2'),
          reason: 'Tooltip must show chargesRemaining');
      expect(tooltip.message, contains('run_end'),
          reason: 'Tooltip must include the earn event source');
    });

    // GIVEN SuperpowerInventoryStrip is rendered with grants
    // WHEN user taps a chip
    // THEN no dialog or navigation is pushed (read-only contract)
    testWidgets('tapping a chip does NOT open any dialog (read-only contract)',
        (tester) async {
      final grants = [_grant(id: 'g1', powerType: 'RUSH')];
      final container = makeTestContainer(
        superpowersRepo: _FakeSuperpowersRepo(grants),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          const SuperpowerInventoryStrip(playerId: 'player-1'),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('RUSH'));
      await tester.pumpAndSettle();

      // No dialog should be present after tapping.
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'READ-ONLY contract: tapping a chip must not open AlertDialog');
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'READ-ONLY contract: tapping a chip must not open BottomSheet');
    });

    // GIVEN no active grants
    // WHEN SuperpowerInventoryStrip is rendered
    // THEN renders nothing (no tiles, no error)
    testWidgets('renders empty strip when there are no active grants', (tester) async {
      final container = makeTestContainer(
        superpowersRepo: _FakeSuperpowersRepo([]),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          const SuperpowerInventoryStrip(playerId: 'player-1'),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // No Tooltip widgets means no tiles rendered.
      expect(find.byType(Tooltip), findsNothing,
          reason: 'Empty grant list must render no power tiles');
    });
  });
}
