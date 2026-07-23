// test/widgets/zone_level_badge_test.dart
//
// Fortification ring badge — covers:
//   1. Tier color per level band (core/arc color).
//   2. Arc progress fraction within a tier (0..1 of the 3-level band).
//   3. Crown replaces the arc only at the Citadel tier (L13-15).
//   4. No numeric text is rendered on the map badge (moved to tap-sheet).
//
// Design contract (widget source, lib/widgets/zone_level_badge.dart):
//   5-tier color map:
//     Tier 0: levels 1-3   → green  0xFF4CAF50 (Outpost)
//     Tier 1: levels 4-6   → lime   0xFFCDDC39 (Stronghold)
//     Tier 2: levels 7-9   → amber  0xFFFFC107 (Fortress)
//     Tier 3: levels 10-12 → orange 0xFFFF9800 (Bastion)
//     Tier 4: levels 13-15 → red    0xFFF44336 (Citadel)
//   Formula: idx = ((level.clamp(1, 15) - 1) ~/ 3).clamp(0, 4)
//   Progress fraction: (((level.clamp(1,15)-1) % 3) + 1) / 3
//   Out-of-range (e.g. level=16) clamps to level=15 → tier 4 (red, crown)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/widgets/zone_level_badge.dart';

// ── Color constants ──────────────────────────────────────────────────────────

const Color kTier0Green  = Color(0xFF4CAF50); // levels 1-3
const Color kTier1Lime   = Color(0xFFCDDC39); // levels 4-6
const Color kTier2Amber  = Color(0xFFFFC107); // levels 7-9
const Color kTier3Orange = Color(0xFFFF9800); // levels 10-12
const Color kTier4Red    = Color(0xFFF44336); // levels 13-15

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _pump(int level) =>
    MaterialApp(home: Scaffold(body: ZoneLevelBadge(level: level)));

FortificationRingPainter _painter(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
  return customPaint.painter as FortificationRingPainter;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ZoneLevelBadge tier color', () {
    testWidgets('level 1 renders green core/arc (tier 0)', (tester) async {
      await tester.pumpWidget(_pump(1));
      expect(_painter(tester).color, equals(kTier0Green));
    });

    testWidgets('level 6 renders lime core/arc (tier 1)', (tester) async {
      await tester.pumpWidget(_pump(6));
      expect(_painter(tester).color, equals(kTier1Lime));
    });

    testWidgets('level 9 renders amber core/arc (tier 2)', (tester) async {
      await tester.pumpWidget(_pump(9));
      expect(_painter(tester).color, equals(kTier2Amber));
    });

    testWidgets('level 12 renders orange core/arc (tier 3)', (tester) async {
      await tester.pumpWidget(_pump(12));
      expect(_painter(tester).color, equals(kTier3Orange));
    });

    testWidgets('level 15 renders red core/arc (tier 4)', (tester) async {
      await tester.pumpWidget(_pump(15));
      expect(_painter(tester).color, equals(kTier4Red));
    });

    testWidgets('level 16 (out-of-range) clamps to red (tier 4)',
        (tester) async {
      await tester.pumpWidget(_pump(16));
      expect(_painter(tester).color, equals(kTier4Red));
    });

    testWidgets('level 3 is green and level 4 is lime — boundary correct',
        (tester) async {
      await tester.pumpWidget(_pump(3));
      final color3 = _painter(tester).color;

      await tester.pumpWidget(_pump(4));
      final color4 = _painter(tester).color;

      expect(color3, equals(kTier0Green));
      expect(color4, equals(kTier1Lime));
      expect(color3, isNot(equals(color4)));
    });
  });

  group('ZoneLevelBadge arc progress within tier', () {
    testWidgets('level 4 (first of Stronghold) → progress 1/3',
        (tester) async {
      await tester.pumpWidget(_pump(4));
      expect(_painter(tester).progress, closeTo(1 / 3, 0.0001));
    });

    testWidgets('level 5 (mid of Stronghold) → progress 2/3',
        (tester) async {
      await tester.pumpWidget(_pump(5));
      expect(_painter(tester).progress, closeTo(2 / 3, 0.0001));
    });

    testWidgets('level 6 (last of Stronghold) → progress 3/3 (full ring)',
        (tester) async {
      await tester.pumpWidget(_pump(6));
      expect(_painter(tester).progress, closeTo(1.0, 0.0001));
    });

    testWidgets('level 7 (first of Fortress) resets progress to 1/3',
        (tester) async {
      await tester.pumpWidget(_pump(7));
      expect(_painter(tester).progress, closeTo(1 / 3, 0.0001));
    });
  });

  group('ZoneLevelBadge crown at Citadel (max tier)', () {
    testWidgets('level 12 (Bastion, not max) has no crown', (tester) async {
      await tester.pumpWidget(_pump(12));
      expect(_painter(tester).showCrown, isFalse);
    });

    testWidgets('level 13 (first of Citadel) shows crown', (tester) async {
      await tester.pumpWidget(_pump(13));
      expect(_painter(tester).showCrown, isTrue);
    });

    testWidgets('level 14 (mid Citadel) shows crown', (tester) async {
      await tester.pumpWidget(_pump(14));
      expect(_painter(tester).showCrown, isTrue);
    });

    testWidgets('level 15 (max) shows crown with full progress',
        (tester) async {
      await tester.pumpWidget(_pump(15));
      final painter = _painter(tester);
      expect(painter.showCrown, isTrue);
      expect(painter.progress, equals(1.0));
    });

    testWidgets('level 16 (out-of-range) clamps into Citadel → crown',
        (tester) async {
      await tester.pumpWidget(_pump(16));
      expect(_painter(tester).showCrown, isTrue);
    });
  });

  group('ZoneLevelBadge renders no raw number on the map', () {
    testWidgets('no Text widget shows the numeric level', (tester) async {
      await tester.pumpWidget(_pump(7));
      expect(find.text('7'), findsNothing);
      expect(find.byType(Text), findsNothing);
    });
  });
}
