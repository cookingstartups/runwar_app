// test/widgets/zone_level_badge_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Each test maps to one GIVEN/WHEN/THEN from design.md §4 + phase spec §8
// (lines 983-985). Phase spec lines 866-872 (grey/green/blue/purple/gold) are
// SUPERSEDED by the Team Lead brief's 5-tier palette encoded in design.md §4.
// Tests use design.md §4 colors exclusively.
//
// Design contract (design.md §4 ZoneLevelBadge):
//   5-tier color map:
//     Tier 0: levels 1-3  → green  0xFF4CAF50
//     Tier 1: levels 4-6  → lime   0xFFCDDC39
//     Tier 2: levels 7-9  → amber  0xFFFFC107
//     Tier 3: levels 10-12→ orange 0xFFFF9800
//     Tier 4: levels 13-15→ red    0xFFF44336
//   Formula: final idx = ((level.clamp(1, 15) - 1) ~/ 3).clamp(0, 4)
//   Out-of-range (e.g. level=16) clamps to level=15 → tier 4 (red)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/widgets/zone_level_badge.dart';

// ── Color constants (design.md §4) ───────────────────────────────────────────

const Color kTier0Green  = Color(0xFF4CAF50); // levels 1-3
const Color kTier1Lime   = Color(0xFFCDDC39); // levels 4-6
const Color kTier2Amber  = Color(0xFFFFC107); // levels 7-9
const Color kTier3Orange = Color(0xFFFF9800); // levels 10-12
const Color kTier4Red    = Color(0xFFF44336); // levels 13-15

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _pump(int level) =>
    MaterialApp(home: Scaffold(body: ZoneLevelBadge(level: level)));

/// Finds the [Container] or [DecoratedBox] in [ZoneLevelBadge] that carries
/// the background color and returns its effective [Color].
Color _badgeColor(WidgetTester tester) {
  // ZoneLevelBadge is specified as a 24×24 circle. We look for a Container
  // whose decoration carries a BoxDecoration with a color matching a tier.
  final containers = tester.widgetList<Container>(find.byType(Container));
  for (final c in containers) {
    final deco = c.decoration;
    if (deco is BoxDecoration && deco.color != null) {
      return deco.color!;
    }
  }
  // Fallback: check DecoratedBox.
  final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
  for (final b in boxes) {
    if (b.decoration is BoxDecoration) {
      final color = (b.decoration as BoxDecoration).color;
      if (color != null) return color;
    }
  }
  throw TestFailure('Could not find a colored Container or DecoratedBox in ZoneLevelBadge');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ZoneLevelBadge colors (design.md §4 5-tier palette)', () {
    // GIVEN level=1 (tier 0)
    // WHEN ZoneLevelBadge is rendered
    // THEN background color is green 0xFF4CAF50
    testWidgets('level 1 renders green (tier 0: 0xFF4CAF50)', (tester) async {
      await tester.pumpWidget(_pump(1));
      expect(_badgeColor(tester), equals(kTier0Green),
          reason: 'Level 1 is in tier 0 → green 0xFF4CAF50');
    });

    // GIVEN level=6 (boundary of tier 1)
    // WHEN ZoneLevelBadge is rendered
    // THEN background color is lime 0xFFCDDC39
    testWidgets('level 6 renders lime (tier 1: 0xFFCDDC39)', (tester) async {
      await tester.pumpWidget(_pump(6));
      expect(_badgeColor(tester), equals(kTier1Lime),
          reason: 'Level 6 is in tier 1 → lime 0xFFCDDC39');
    });

    // GIVEN level=9 (boundary of tier 2)
    // WHEN ZoneLevelBadge is rendered
    // THEN background color is amber 0xFFFFC107
    testWidgets('level 9 renders amber (tier 2: 0xFFFFC107)', (tester) async {
      await tester.pumpWidget(_pump(9));
      expect(_badgeColor(tester), equals(kTier2Amber),
          reason: 'Level 9 is in tier 2 → amber 0xFFFFC107');
    });

    // GIVEN level=12 (boundary of tier 3)
    // WHEN ZoneLevelBadge is rendered
    // THEN background color is orange 0xFFFF9800
    testWidgets('level 12 renders orange (tier 3: 0xFFFF9800)', (tester) async {
      await tester.pumpWidget(_pump(12));
      expect(_badgeColor(tester), equals(kTier3Orange),
          reason: 'Level 12 is in tier 3 → orange 0xFFFF9800');
    });

    // GIVEN level=15 (tier 4, maximum in-range)
    // WHEN ZoneLevelBadge is rendered
    // THEN background color is red 0xFFF44336
    testWidgets('level 15 renders red (tier 4: 0xFFF44336)', (tester) async {
      await tester.pumpWidget(_pump(15));
      expect(_badgeColor(tester), equals(kTier4Red),
          reason: 'Level 15 is in tier 4 → red 0xFFF44336');
    });

    // GIVEN level=16 (out-of-range, above max)
    // WHEN ZoneLevelBadge is rendered
    // THEN clamps to 15 → tier 4 (red 0xFFF44336)
    testWidgets('level 16 (out-of-range) renders red — clamped to level 15', (tester) async {
      await tester.pumpWidget(_pump(16));
      expect(_badgeColor(tester), equals(kTier4Red),
          reason: 'Level 16 must clamp to 15 → tier 4 (red 0xFFF44336)');
    });

    // Additional boundary verification: level 3 (last of tier 0) and level 4
    // (first of tier 1) must differ — validates the formula at the boundary.
    testWidgets('level 3 is green (tier 0) and level 4 is lime (tier 1) — boundary correct', (tester) async {
      await tester.pumpWidget(_pump(3));
      final color3 = _badgeColor(tester);

      await tester.pumpWidget(_pump(4));
      final color4 = _badgeColor(tester);

      expect(color3, equals(kTier0Green),
          reason: 'Level 3 must be green (tier 0)');
      expect(color4, equals(kTier1Lime),
          reason: 'Level 4 must be lime (tier 1)');
      expect(color3, isNot(equals(color4)),
          reason: 'Tier boundary at level 3→4 must produce different colors');
    });
  });
}
