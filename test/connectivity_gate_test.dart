import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/providers/connectivity_provider.dart';
import 'package:runwar_app/widgets/offline_overlay.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps a minimal widget tree that exercises [OfflineOverlay] via the
/// [MaterialApp.builder] wiring described in design.md.
///
/// The real [connectivityProvider] is overridden with a controllable stream
/// so no [MissingPluginException] fires from the platform channel (R-T1).
Widget _buildTree({
  required Stream<bool> stream,
  Widget child = const Text('CHILD'),
}) {
  return ProviderScope(
    overrides: [
      connectivityProvider.overrideWith((ref) => stream),
    ],
    child: MaterialApp(
      builder: (context, routerChild) =>
          OfflineOverlay(child: routerChild ?? const SizedBox.shrink()),
      home: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('offline overlay - stream-driven visibility', () {
    // -----------------------------------------------------------------------
    // GIVEN the connectivity provider emits false (offline)
    // WHEN the widget tree is built
    // THEN the offline gate screen is visible and shows "NO CONNECTION" text
    // -----------------------------------------------------------------------
    testWidgets('shows NO CONNECTION screen when provider emits offline', (tester) async {
      final controller = StreamController<bool>();
      addTearDown(controller.close);

      await tester.pumpWidget(_buildTree(stream: controller.stream));

      controller.add(false);
      await tester.pump();

      // OfflineOverlay uses a Stack: the child is always mounted but the
      // _OfflineScreen paints over it via Positioned.fill. The meaningful
      // assertion is that the gate widget is present in the tree.
      expect(find.text('NO CONNECTION'), findsOneWidget,
          reason: 'Offline gate must be visible when connectivity emits false');
    });

    // -----------------------------------------------------------------------
    // GIVEN the connectivity provider emits true (online)
    // WHEN the widget tree is built
    // THEN the child widget is visible and the offline gate is absent
    // -----------------------------------------------------------------------
    testWidgets('shows child widget and no offline screen when provider emits online', (tester) async {
      final controller = StreamController<bool>();
      addTearDown(controller.close);

      await tester.pumpWidget(_buildTree(stream: controller.stream));

      controller.add(true);
      await tester.pump();

      expect(find.text('CHILD'), findsOneWidget,
          reason: 'Child widget must be visible when connectivity emits true');
      expect(find.text('NO CONNECTION'), findsNothing,
          reason: 'Offline gate must not appear when online');
    });

    // -----------------------------------------------------------------------
    // GIVEN the connectivity provider is in AsyncLoading state (no emission yet)
    // WHEN the first frame is drawn
    // THEN the offline gate overlay is visible (loading defaults to offline)
    // -----------------------------------------------------------------------
    testWidgets('shows offline gate on loading state before first emission', (tester) async {
      // A stream that never emits — provider stays in AsyncLoading.
      final controller = StreamController<bool>();
      addTearDown(controller.close);

      await tester.pumpWidget(_buildTree(stream: controller.stream));
      // Do NOT emit anything — loading state persists.
      await tester.pump();

      expect(find.text('NO CONNECTION'), findsOneWidget,
          reason: 'Loading state must paint the offline gate (treat unknown as offline)');
      expect(find.text('CHILD'), findsNothing,
          reason: 'Child must not be visible while loading');
    });

    // -----------------------------------------------------------------------
    // GIVEN the offline gate is currently showing (provider emitted false)
    //   AND the device then regains connectivity (provider emits true)
    // WHEN the stream fires the new value
    // THEN the offline gate is dismissed without any user interaction
    // -----------------------------------------------------------------------
    testWidgets('dismisses offline gate automatically when connectivity is restored', (tester) async {
      final controller = StreamController<bool>();
      addTearDown(controller.close);

      await tester.pumpWidget(_buildTree(stream: controller.stream));

      // Go offline first.
      controller.add(false);
      await tester.pump();

      expect(find.text('NO CONNECTION'), findsOneWidget,
          reason: 'Precondition: gate must be visible after offline emission');

      // Regain connectivity.
      controller.add(true);
      await tester.pump();

      expect(find.text('NO CONNECTION'), findsNothing,
          reason: 'Gate must dismiss automatically when connectivity is restored');
      expect(find.text('CHILD'), findsOneWidget,
          reason: 'Child must be visible again after reconnect');
    });
  });
}
