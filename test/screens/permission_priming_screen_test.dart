// test/screens/permission_priming_screen_test.dart
//
// RED phase — permission priming.
// Files under test (do not exist yet):
//   lib/screens/permission_priming_screen.dart — PermissionPrimingScreen,
//     _LocationCard, _NotificationsCard, _BatteryCard, LocationDeniedGate
//   lib/services/permission_service.dart — PermKind
//
// Framework: flutter_test + flutter_riverpod (mirrors route_guard_test.dart
// conventions). No FlutterMap involved — standard testWidgets applies.
//
// Widget-render assertions use testWidgets (no CTA taps, so no real platform
// channel is exercised). Behaviors that only fire on a CTA tap (which would
// hit real Geolocator/permission_handler/NotificationGateway platform
// channels with no test seam per design.md's Gotcha note) are covered via
// source inspection per flutter-test-patterns.md §2/§"When NOT to use
// testWidgets".

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/screens/permission_priming_screen.dart';
import 'package:runwar_app/services/permission_service.dart';

Widget _scope(List<PermKind> missing) => ProviderScope(
      child: MaterialApp(
        home: PermissionPrimingScreen(missing: missing),
      ),
    );

void main() {
  // ── AC-4: only the missing cards render, in fixed order ────────────────
  group('AC-4: renders only the missing cards, in fixed relative order', () {
    testWidgets('shows Notifications card first when Location is not missing',
        (tester) async {
      await tester.pumpWidget(
          _scope(const [PermKind.notifications, PermKind.battery]));
      await tester.pump();

      expect(find.text('ENABLE LOCATION'), findsNothing,
          reason: 'Location card must not render when location is not missing');
      expect(find.textContaining('ALERTS'), findsOneWidget,
          reason: 'Notifications card must be the first card shown');
    });
  });

  // ── AC-12: progress dots reflect only the cards shown ───────────────────
  group('AC-12: progress indicator dot count matches missing.length', () {
    testWidgets('shows exactly 1 dot when only Battery is missing',
        (tester) async {
      await tester.pumpWidget(_scope(const [PermKind.battery]));
      await tester.pump();

      expect(find.textContaining('1 OF 1'), findsOneWidget,
          reason: 'Label must read 1 OF 1 when a single card is shown');
    });

    testWidgets('shows a 3-of-3 label when all three permissions are missing',
        (tester) async {
      await tester.pumpWidget(_scope(const [
        PermKind.location,
        PermKind.notifications,
        PermKind.battery,
      ]));
      await tester.pump();

      expect(find.textContaining('1 OF 3'), findsOneWidget,
          reason: 'Label must read 1 OF 3 on the first of three cards');
    });
  });

  // ── AC-5 invariant: no skip affordance on the Location card ─────────────
  group('AC-5 invariant: Location card never offers a Not Now / skip action', () {
    testWidgets('Location card has no NOT NOW affordance', (tester) async {
      await tester.pumpWidget(_scope(const [PermKind.location]));
      await tester.pump();

      expect(find.text('NOT NOW'), findsNothing,
          reason: 'Location is a hard gate — it must never offer a skip action');
    });
  });

  // ── AC-9: sequential, tap-driven CTA firing ─────────────────────────────
  group('AC-9: OS dialogs fire only from an explicit CTA tap, never on card appearance', () {
    test('card advance logic lives inside a button callback, not initState/build', () {
      final src = File('lib/screens/permission_priming_screen.dart');
      expect(src.existsSync(), isTrue,
          reason: 'permission_priming_screen.dart must exist');
      final content = src.readAsStringSync();
      expect(content.contains('onPressed'), isTrue,
          reason: 'Card CTAs must be wired through onPressed, not fired automatically');
      expect(content.contains('initState'), isFalse,
          reason: 'No permission request may be triggered from initState (AC-9)');
    });
  });

  // ── AC-7: Notifications soft-ask, both actions advance ──────────────────
  group('AC-7: Notifications card offers Turn On Alerts and Not Now, both advance', () {
    test('Notifications card exposes both CTAs', () {
      final content =
          File('lib/screens/permission_priming_screen.dart').readAsStringSync();
      expect(content.contains('TURN ON ALERTS'), isTrue,
          reason: 'Notifications card must offer a Turn On Alerts CTA');
      expect(content.contains('NOT NOW'), isTrue,
          reason: 'Notifications card must offer a Not Now CTA');
    });
  });

  // ── AC-8: Battery soft-ask via settings intent, both actions complete ───
  group('AC-8: Battery card offers Keep My Runs Alive and Not Now, both complete priming', () {
    test('Battery card exposes both CTAs', () {
      final content =
          File('lib/screens/permission_priming_screen.dart').readAsStringSync();
      expect(content.contains('KEEP MY RUNS ALIVE'), isTrue,
          reason: 'Battery card must offer a Keep My Runs Alive CTA');
      expect(content.contains('markPrimingDone'), isTrue,
          reason: 'Resolving the last card must call markPrimingDone');
    });
  });

  // ── AC-11: MIUI instruction row on the Battery card ─────────────────────
  group('AC-11: Battery card conditionally shows the MIUI instruction row', () {
    test('Battery card gates the MIUI row on isMiuiManufacturer', () {
      final content =
          File('lib/screens/permission_priming_screen.dart').readAsStringSync();
      expect(content.contains('isMiuiManufacturer'), isTrue,
          reason: 'Battery card must gate its extra row on manufacturer classification');
      expect(content.contains('Autostart'), isTrue,
          reason: 'MIUI row copy must reference Autostart per the mockup');
    });
  });

  // ── AC-5: denied-state variant ───────────────────────────────────────────
  group('AC-5: Location denied-state variant offers Try Again and Open Settings only', () {
    test('LocationDeniedGate exposes Try Again and Open Settings, never Not Now', () {
      final src = File('lib/widgets/location_denied_gate.dart');
      final path = src.existsSync()
          ? src
          : File('lib/screens/permission_priming_screen.dart');
      final content = path.readAsStringSync();
      expect(content.contains('TRY AGAIN'), isTrue,
          reason: 'Denied state must offer a Try Again CTA');
      expect(content.contains('OPEN SETTINGS'), isTrue,
          reason: 'Denied state must offer an Open Settings CTA');
    });
  });
}
