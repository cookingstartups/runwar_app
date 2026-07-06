// test/widgets/attack_sheet_test.dart
//
// Each test maps to one GIVEN/WHEN/THEN from design.md §4 + phase spec §8
// (lines 974-977).
//
// Design contract (design.md §4 AttackSheet):
//   - ConsumerWidget taking Zone zone and an onStartRun callback
//   - Reads owner name via profileCacheProvider(zone.ownerId)
//   - Window copy: "Level ${level} zone — attack window will be ${level * 20} minutes"
//   - Primary CTA "Start a run": calls Navigator.pop then invokes onStartRun —
//     the caller (MapScreen) routes this through the same guarded start path
//     as the FAB, never straight into runRecorderProvider.notifier.start().
//   - Shows DisputeCountdownLabel when zone.status == disputed

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/widgets/attack_sheet.dart';
import 'package:runwar_app/widgets/dispute_countdown_label.dart';
import 'package:runwar_app/services/database/models/zone.dart';
import 'package:runwar_app/providers/zones_provider.dart';

import '../_helpers/test_container.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Zone _makeZone({
  String id = 'zone-001',
  String ownerId = 'owner-abc',
  int influenceLevel = 3,
  String status = 'owned',
}) =>
    Zone.fromGeoJsonRow({
      'id': id,
      'owner_id': ownerId,
      'city': 'Valencia',
      'influence_level': influenceLevel,
      'status': status,
      'geom_json': '{"type":"Polygon","coordinates":[[[-0.38,39.46],[-0.36,39.46],[-0.36,39.48],[-0.38,39.48],[-0.38,39.46]]]}',
      'created_at': '2026-05-31T10:00:00.000Z',
      'updated_at': '2026-05-31T10:00:00.000Z',
    });

Widget _wrap(Widget child, {required ProviderContainer container}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // No mocktail fallback values needed — StubRunRecorderNotifier is used
    // instead of a Mock for RunRecorderNotifier.
  });

  group('AttackSheet', () {
    // GIVEN a zone owned by 'owner-abc' whose profile name is 'Alpha Runner'
    // WHEN AttackSheet is pumped
    // THEN renders the owner's display name from profileCacheProvider
    testWidgets('renders owner display name from profileCacheProvider', (tester) async {
      final zone = _makeZone(ownerId: 'owner-abc');

      final container = makeTestContainer(overrides: [
        profileCacheProvider('owner-abc').overrideWith(
          (_) async => {'display_name': 'Alpha Runner', 'id': 'owner-abc'},
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(
        AttackSheet(zone: zone, onStartRun: () {}),
        container: container,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Alpha Runner'), findsOneWidget);
    });

    // GIVEN a zone with influenceLevel=3
    // WHEN AttackSheet is rendered
    // THEN shows "60 min window" (level × 20 min = 3 × 20 = 60)
    testWidgets('shows "level × 20 min" window string: level=3 → "60 min"', (tester) async {
      final zone = _makeZone(influenceLevel: 3);

      final container = makeTestContainer(overrides: [
        profileCacheProvider(zone.ownerId).overrideWith(
          (_) async => {'display_name': 'Beta Runner', 'id': zone.ownerId},
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(
        AttackSheet(zone: zone, onStartRun: () {}),
        container: container,
      ));
      await tester.pumpAndSettle();

      // The sheet must render "60 min" (level 3 × 20 = 60).
      expect(find.textContaining('60 min'), findsAtLeastNWidgets(1),
          reason: 'Level 3 attack window should show 60 min (3 × 20)');
    });

    // GIVEN the user taps "Start a run"
    // WHEN AttackSheet is displayed
    // THEN invokes the onStartRun callback (the caller's guarded start path)
    testWidgets('"Start a run" button invokes onStartRun', (tester) async {
      final zone = _makeZone();
      var startCalled = false;

      final container = makeTestContainer(overrides: [
        profileCacheProvider(zone.ownerId).overrideWith(
          (_) async => {'display_name': 'Test Owner', 'id': zone.ownerId},
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(
        AttackSheet(zone: zone, onStartRun: () => startCalled = true),
        container: container,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start a run'));
      await tester.pumpAndSettle();

      expect(startCalled, isTrue,
          reason: '"Start a run" must invoke the onStartRun callback');
    });

    // GIVEN a zone with status='disputed'
    // WHEN AttackSheet is pumped
    // THEN DisputeCountdownLabel is rendered on the sheet
    testWidgets('shows DisputeCountdownLabel when zone has open dispute (status=disputed)', (tester) async {
      final zone = _makeZone(status: 'disputed');

      final container = makeTestContainer(overrides: [
        profileCacheProvider(zone.ownerId).overrideWith(
          (_) async => {'display_name': 'Owner In Dispute', 'id': zone.ownerId},
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(
        AttackSheet(zone: zone, onStartRun: () {}),
        container: container,
      ));
      await tester.pumpAndSettle();

      // DisputeCountdownLabel must be present in the widget tree.
      expect(
        find.byType(DisputeCountdownLabel),
        findsOneWidget,
        reason: 'AttackSheet must render DisputeCountdownLabel when zone is disputed',
      );
    });
  });
}
