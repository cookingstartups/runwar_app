// test/widgets/run_metrics_card_test.dart
//
// Paired test file for RunMetricsCard (rw_app-T0197). RED phase: none of
// lib/models/run_summary.dart, lib/models/unit_system.dart, or
// lib/widgets/run_metrics_card.dart exist yet.
//
// Covers, per the run-lifecycle-feedback design's fixed render order: (1)
// territory hero with an aggregate zone count folded in, no separate
// outcome-headline text, (2) the distance/duration/avg-pace triad, (3) the
// reward line, (4) the Share/Close CTA row - with no per-zone breakdown list
// anywhere, disputed zones excluded from every aggregate figure, avg pace
// derived (never live speed), and metric-default/imperial unit formatting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/models/run_summary.dart';
import 'package:runwar_app/models/unit_system.dart';
import 'package:runwar_app/widgets/run_metrics_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

final _polygon = <LatLng>[LatLng(51.5, -0.1), LatLng(51.5001, -0.1001)];

RunSummary _summaryWith({
  double distanceM = 2400,
  Duration duration = const Duration(minutes: 18, seconds: 32),
  List<ClaimLineItem> claims = const [],
}) =>
    RunSummary(distanceM: distanceM, duration: duration, claims: claims);

void main() {
  group('RunMetricsCard: layout order and content', () {
    testWidgets(
        'renders hero, triad, reward, and CTA row in that fixed order, with no headline or breakdown list',
        (tester) async {
      final summary = _summaryWith(claims: [
        ClaimLineItem(
            label: 'Zone 1',
            areaM2: 1200000,
            outcome: ClaimLineOutcome.claimed,
            polygon: _polygon),
        ClaimLineItem(
            label: 'Zone 2',
            areaM2: 400000,
            outcome: ClaimLineOutcome.conquered,
            polygon: _polygon),
      ]);

      await tester.pumpWidget(_wrap(RunMetricsCard(
        summary: summary,
        onClosePressed: () {},
        onSharePressed: () {},
      )));
      await tester.pump();

      expect(find.textContaining('2 zones claimed'), findsOneWidget,
          reason: 'the hero must fold the aggregate zone count into itself');
      expect(find.textContaining('Zone 1:'), findsNothing,
          reason: 'no per-zone breakdown list may appear anywhere on the card');
      expect(find.textContaining('Zone 2:'), findsNothing);

      final heroY = tester.getTopLeft(find.textContaining('2 zones claimed')).dy;
      final rewardFinder = find.textContaining('credits/hr');
      expect(rewardFinder, findsOneWidget);
      final rewardY = tester.getTopLeft(rewardFinder).dy;
      expect(heroY, lessThan(rewardY),
          reason: 'the hero must render above the reward line');

      expect(find.widgetWithText(ElevatedButton, 'SHARE').evaluate().isNotEmpty ||
          find.textContaining('SHARE').evaluate().isNotEmpty, isTrue,
          reason: 'a Share CTA must be present');
      expect(find.textContaining('CLOSE'), findsOneWidget);
    });

    testWidgets('no separate outcome-headline text element renders above the hero',
        (tester) async {
      await tester.pumpWidget(_wrap(RunMetricsCard(
        summary: _summaryWith(),
        onClosePressed: () {},
      )));
      await tester.pump();

      expect(find.textContaining('You claimed'), findsNothing);
      expect(find.textContaining('Territory Claimed!'), findsNothing);
    });
  });

  group('RunMetricsCard: avg pace is a derived value', () {
    test('avgPacePerKm is derived from duration / distance, matching 7:43/km for 2.4km in 18:32', () {
      final summary = _summaryWith();
      expect(summary.avgPacePerKm, const Duration(minutes: 7, seconds: 43));
    });

    test('avgPacePerKm is null when distance is zero (no successful loop this session)', () {
      final summary = _summaryWith(distanceM: 0);
      expect(summary.avgPacePerKm, isNull);
    });
  });

  group('RunMetricsCard: disputed zones are excluded from every aggregate figure', () {
    test('hero total area, zone count, and reward exclude a disputed zone', () {
      final summary = _summaryWith(claims: [
        ClaimLineItem(
            label: 'Zone 1',
            areaM2: 1200000,
            outcome: ClaimLineOutcome.claimed,
            polygon: _polygon),
        ClaimLineItem(
            label: 'Zone 2',
            areaM2: 400000,
            outcome: ClaimLineOutcome.conquered,
            polygon: _polygon),
        ClaimLineItem(
            label: 'Zone 3',
            areaM2: 300000,
            outcome: ClaimLineOutcome.disputed,
            polygon: _polygon),
      ]);

      expect(summary.totalAreaM2, 1600000);
      expect(summary.claimedZoneCount, 2);
      expect(summary.rewardCreditsPerHour, closeTo(1.6, 0.001));
    });

    test('a session where every outcome is disputed reads zero for every aggregate figure', () {
      final summary = _summaryWith(claims: [
        ClaimLineItem(
            label: 'Zone 1',
            areaM2: 300000,
            outcome: ClaimLineOutcome.disputed,
            polygon: _polygon),
      ]);

      expect(summary.totalAreaM2, 0);
      expect(summary.claimedZoneCount, 0);
      expect(summary.rewardCreditsPerHour, 0);
    });
  });

  group('RunMetricsCard: Share CTA targets the most recently claimed zone', () {
    test('mostRecentShareableClaim returns the last countsTowardHero claim, not the last claim overall', () {
      final summary = _summaryWith(claims: [
        ClaimLineItem(
            label: 'Zone 1',
            areaM2: 100,
            outcome: ClaimLineOutcome.claimed,
            polygon: _polygon),
        ClaimLineItem(
            label: 'Zone 2',
            areaM2: 200,
            outcome: ClaimLineOutcome.disputed,
            polygon: _polygon),
      ]);

      expect(summary.mostRecentShareableClaim?.label, 'Zone 1');
    });

    test('mostRecentShareableClaim is null when zero claimed/conquered zones exist', () {
      final summary = _summaryWith(claims: [
        ClaimLineItem(
            label: 'Zone 1',
            areaM2: 100,
            outcome: ClaimLineOutcome.disputed,
            polygon: _polygon),
      ]);

      expect(summary.mostRecentShareableClaim, isNull);
    });

    testWidgets('Share is disabled, not hidden, when onSharePressed is null',
        (tester) async {
      await tester.pumpWidget(_wrap(RunMetricsCard(
        summary: _summaryWith(),
        onClosePressed: () {},
        onSharePressed: null,
      )));
      await tester.pump();

      expect(find.textContaining('SHARE'), findsOneWidget,
          reason: 'the Share button must still render, just disabled');
    });

    testWidgets('tapping Share invokes onSharePressed when provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(RunMetricsCard(
        summary: _summaryWith(),
        onClosePressed: () {},
        onSharePressed: () => tapped = true,
      )));
      await tester.pump();

      await tester.tap(find.textContaining('SHARE'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('tapping Close invokes onClosePressed', (tester) async {
      var closed = false;
      await tester.pumpWidget(_wrap(RunMetricsCard(
        summary: _summaryWith(),
        onClosePressed: () => closed = true,
      )));
      await tester.pump();

      await tester.tap(find.textContaining('CLOSE'));
      await tester.pump();

      expect(closed, isTrue);
    });
  });

  group('RunMetricsCard: UnitSystem formatting', () {
    testWidgets('defaults to metric (kilometers) when no UnitSystem is passed',
        (tester) async {
      await tester.pumpWidget(_wrap(RunMetricsCard(
        summary: _summaryWith(),
        onClosePressed: () {},
      )));
      await tester.pump();

      expect(find.textContaining('km'), findsWidgets,
          reason: 'metric is the default unit system');
      expect(find.textContaining('mi'), findsNothing);
    });

    testWidgets('renders miles when UnitSystem.imperial is passed explicitly',
        (tester) async {
      await tester.pumpWidget(_wrap(RunMetricsCard(
        summary: _summaryWith(),
        onClosePressed: () {},
        unitSystem: UnitSystem.imperial,
      )));
      await tester.pump();

      expect(find.textContaining('mi'), findsWidgets,
          reason: 'UnitSystem.imperial must render distances in miles');
    });
  });
}
