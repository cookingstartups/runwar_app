// test/widgets/intro/intro_capture_map_test.dart
//
// RED phase — SDD Step 4 Test Engineer
// Each test maps to exactly one GIVEN/WHEN/THEN from:
//   infra/meta/specs/runwar/mvp/intro-slide-2-reset/requirements.md
//
// AC-1: t=0 render produces 3 orange inherited blocks (no pre-roll trace)
// AC-2: Blue attacker runs a GPS loop around kS1Block1; 6 user-supplied waypoints
// AC-3: _kDisputedArea and _kSharedTransferVertices each have >= 3 vertices
// AC-4: 3-phase VFX preserved — _kSharedTransferVertices >= 3 (ping guard)
// AC-5: Map centre is LatLng(39.4650, -0.3756), zoom 16.0 (shifted 50 m west)
// AC-6: No fortify-loop latitudes in route/lasso/disputed/transfer constants
// AC-7: _kPreRollRoute const, _preRollRoute field, preRollRoute painter param
//        absent from file (pre-roll deletion complete)
//
// Tests updated 2026-06-07: AC-2 and AC-5 revised to reflect new route geometry
// and westward camera shift.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'package:runwar_app/widgets/intro/intro_capture_map.dart';

// ---------------------------------------------------------------------------
// Static-analysis helpers — read the source file and inspect constant values
// without instantiating the widget (avoids FlutterMap tile-loading issues).
// ---------------------------------------------------------------------------

/// Reads intro_capture_map.dart as a string for static grep-style assertions.
String _sourceText() {
  final path = 'lib/widgets/intro/intro_capture_map.dart';
  final file = File(path);
  if (!file.existsSync()) {
    // Also try absolute path from project root
    final absPath = '/home/algif/repos/venture/runwar/runwar_app/$path';
    return File(absPath).readAsStringSync();
  }
  return file.readAsStringSync();
}

// ---------------------------------------------------------------------------
// Fortify-loop latitude sentinel values (AC-6)
// These are the five latitudes that must NOT appear in any route/lasso/
// disputed/transfer constant after the reset.
// ---------------------------------------------------------------------------
const _kFortifyLatitudes = [
  '39.45876687267654',
  '39.46217783167975',
  '39.460341182218244',
  '39.45912365004915',
  '39.460939442465346',
];

// ---------------------------------------------------------------------------
// kS1Block1 latitude range (A/B/C/D from intro_helpers.dart:599-604)
//   A = LatLng(39.462077, -0.375522)
//   B = LatLng(39.461576, -0.376751)
//   C = LatLng(39.462155, -0.377171)
//   D = LatLng(39.462671, -0.375937)
// ---------------------------------------------------------------------------
const double _kS1Block1MinLat = 39.461576;
const double _kS1Block1MaxLat = 39.462671;
const double _kS1Block1MinLng = -0.377171;
const double _kS1Block1MaxLng = -0.375522;

/// Returns true if the LatLng is within the kS1Block1 bounding box
/// (generous tolerance — confirms the route ends near the block).
bool _insideS1Block1Bbox(LatLng ll) {
  return ll.latitude >= _kS1Block1MinLat - 0.0005 &&
      ll.latitude <= _kS1Block1MaxLat + 0.0005 &&
      ll.longitude >= _kS1Block1MinLng - 0.0005 &&
      ll.longitude <= _kS1Block1MaxLng + 0.0005;
}

// ---------------------------------------------------------------------------
// Widget pump helper — wraps IntroCaptureMap in a minimal Material app.
// Uses a fixed 800×600 surface so the map renders without assertions.
// ---------------------------------------------------------------------------
Widget _pumpCaptureMap() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: IntroCaptureMap(accent: const Color(0xFFFF6B00)),
        ),
      ),
    );

// ===========================================================================
// Test suite
// ===========================================================================

void main() {
  // -------------------------------------------------------------------------
  // AC-5: Map centre and zoom
  // -------------------------------------------------------------------------
  group('AC-5: Map centre is LatLng(39.4650, -0.3756) at zoom 16', () {
    // GIVEN  IntroCaptureMap is instantiated and buildIntroMap() is called
    // WHEN   the FlutterMap options are evaluated
    // THEN   initialCenter == LatLng(39.4650, -0.3756)
    test('source file contains initialCenter LatLng(39.4650, -0.3756)', () {
      final src = _sourceText();
      expect(
        src,
        contains('39.4650'),
        reason: 'AC-5: initialCenter latitude 39.4650 must appear in the file',
      );
      expect(
        src,
        contains('-0.3756'),
        reason: 'AC-5: initialCenter longitude -0.3756 must appear in the file',
      );
    });

    // GIVEN  IntroCaptureMap is instantiated
    // WHEN   the FlutterMap options are evaluated
    // THEN   the previous centre LatLng(39.4659, -0.3738) does not appear
    //   AND  the old longitude -0.3750 (pre-shift) does not appear as the centre
    test('old map centre 39.4659/-0.3738/-0.3750 is absent from source file', () {
      final src = _sourceText();
      expect(
        src,
        isNot(contains('39.4659')),
        reason: 'AC-5: Old centre latitude 39.4659 must be removed',
      );
      expect(
        src,
        isNot(contains('-0.3738')),
        reason: 'AC-5: Old centre longitude -0.3738 must be removed',
      );
      // The centre was shifted 50 m west from -0.3750 to -0.3756.
      // -0.3750 must no longer appear as the initialCenter value.
      // Note: we check in the buildIntroMap call specifically.
      final centerMatch = RegExp(
        r'center:\s*const\s+LatLng\([^)]+\)',
      ).firstMatch(src);
      expect(centerMatch, isNotNull,
          reason: 'AC-5: center: LatLng(...) must exist in source');
      expect(
        centerMatch!.group(0),
        isNot(contains('-0.3750')),
        reason: 'AC-5: Old centre longitude -0.3750 must be replaced with -0.3756',
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC-7: Pre-roll deletion — _kPreRollRoute, _preRollRoute, preRollRoute param
  // -------------------------------------------------------------------------
  group('AC-7: Pre-roll identifiers are absent from source file', () {
    // GIVEN  the pre-roll branch has been deleted
    // WHEN   the source file is searched for _kPreRollRoute
    // THEN   no occurrence exists
    test('_kPreRollRoute const is absent from source file', () {
      final src = _sourceText();
      expect(
        src,
        isNot(contains('_kPreRollRoute')),
        reason: 'AC-7: _kPreRollRoute const must be deleted',
      );
    });

    // GIVEN  the pre-roll branch has been deleted
    // WHEN   the source file is searched for _preRollRoute field
    // THEN   no occurrence exists
    test('_preRollRoute field is absent from source file', () {
      final src = _sourceText();
      expect(
        src,
        isNot(contains('_preRollRoute')),
        reason: 'AC-7: _preRollRoute List field must be deleted',
      );
    });

    // GIVEN  the pre-roll painter parameter has been removed
    // WHEN   the source file is searched for preRollRoute painter param
    // THEN   no occurrence exists
    test('preRollRoute painter parameter is absent from source file', () {
      final src = _sourceText();
      expect(
        src,
        isNot(contains('preRollRoute')),
        reason: 'AC-7: preRollRoute painter parameter must be deleted '
            '(shouldRepaint and constructor both updated)',
      );
    });

    // GIVEN  the t < 0.25 pre-roll branch has been deleted
    // WHEN   the source file is searched for the pre-roll time guard
    // THEN   no occurrence of "t < 0.25" exists
    test('t < 0.25 pre-roll branch is absent from source file', () {
      final src = _sourceText();
      expect(
        src,
        isNot(contains('t < 0.25')),
        reason: 'AC-7: The t < 0.25 pre-roll guard branch must be deleted',
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC-6: No fortify-loop latitudes remain in route/lasso/disputed/transfer
  // -------------------------------------------------------------------------
  group('AC-6: No fortify-loop coordinates remain', () {
    for (final lat in _kFortifyLatitudes) {
      // GIVEN  the modified file is committed
      // WHEN   a reviewer searches for the six original fortify latitude values
      // THEN   none appear in the file
      test('fortify-loop latitude $lat is absent from source file', () {
        final src = _sourceText();
        expect(
          src,
          isNot(contains(lat)),
          reason: 'AC-6: Fortify-loop latitude $lat must not appear '
              'in _kAttackerRoute, _kAttackerLasso, _kDisputedArea, or '
              '_kSharedTransferVertices after the reset',
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // AC-2: Attacker route is a GPS loop around kS1Block1 (6 user-supplied
  //       waypoints). The loop wraps the block — pt0 is NW of the block,
  //       pt2 is near the SW corner, pt3 near the SE corner, pt4 at the NE
  //       apex, and pt5 closes back near pt0.
  //       Updated 2026-06-07: new route is a closed lasso, not a south entry.
  // -------------------------------------------------------------------------
  group('AC-2: Attacker route is a closed GPS loop around kS1Block1', () {
    // GIVEN  _kAttackerRoute is the user-supplied 6-waypoint loop
    // WHEN   the route constant is inspected
    // THEN   it contains exactly 6 LatLng entries
    test('_kAttackerRoute contains exactly 6 waypoints', () {
      final src = _sourceText();
      final routeBlockMatch = RegExp(
        r'static const _kAttackerRoute\s*=\s*\[([\s\S]*?)\];',
      ).firstMatch(src);
      expect(
        routeBlockMatch,
        isNotNull,
        reason: 'AC-2: _kAttackerRoute constant must exist in source file',
      );
      final routeBlock = routeBlockMatch!.group(1)!;
      final latMatches =
          RegExp(r'LatLng\(\s*([\d.]+)').allMatches(routeBlock).toList();
      expect(
        latMatches.length,
        equals(6),
        reason: 'AC-2: _kAttackerRoute must have exactly 6 waypoints '
            '(user-supplied GPS loop). Found ${latMatches.length}.',
      );
    });

    // GIVEN  _kAttackerRoute is the user-supplied loop
    // WHEN   the first waypoint is inspected
    // THEN   it matches the expected NW entry coordinate (lat ≈ 39.46337)
    test('_kAttackerRoute first waypoint is the user-supplied NW entry', () {
      final src = _sourceText();
      final routeBlockMatch = RegExp(
        r'static const _kAttackerRoute\s*=\s*\[([\s\S]*?)\];',
      ).firstMatch(src);
      expect(routeBlockMatch, isNotNull,
          reason: 'AC-2: _kAttackerRoute must exist');
      final routeBlock = routeBlockMatch!.group(1)!;
      final latMatches =
          RegExp(r'LatLng\(\s*([\d.]+)').allMatches(routeBlock).toList();
      expect(latMatches, isNotEmpty,
          reason: 'AC-2: _kAttackerRoute must contain at least one LatLng');
      final firstLat = double.parse(latMatches.first.group(1)!);
      // New route pt0 is at lat ≈ 39.46337 (NW of kS1Block1).
      // The route is a closed loop, not a south-entry approach.
      expect(
        firstLat,
        inInclusiveRange(39.4630, 39.4640),
        reason: 'AC-2: First waypoint of the new _kAttackerRoute must be '
            'at lat ≈ 39.46337 (NW entry of the closed loop). '
            'Found $firstLat.',
      );
    });

    // GIVEN  _kAttackerRoute is a closed GPS loop around kS1Block1
    // WHEN   the terminal waypoint (pt5 — loop close) is inspected
    // THEN   it lies within 0.003° (~300 m) of kS1Block1 centre
    //        (the loop closes near pt0, NW of the block — not inside the block)
    test('_kAttackerRoute terminal waypoint is within 0.003 deg of kS1Block1 centre', () {
      final src = _sourceText();
      final routeBlockMatch = RegExp(
        r'static const _kAttackerRoute\s*=\s*\[([\s\S]*?)\];',
      ).firstMatch(src);
      expect(routeBlockMatch, isNotNull,
          reason: 'AC-2: _kAttackerRoute must exist');
      final routeBlock = routeBlockMatch!.group(1)!;
      final latMatches =
          RegExp(r'LatLng\(\s*([\d.]+)\s*,\s*(-[\d.]+)').allMatches(routeBlock).toList();
      expect(latMatches.length, greaterThanOrEqualTo(2),
          reason: 'AC-2: _kAttackerRoute needs at least 2 waypoints');
      final last = latMatches.last;
      final terminalLat = double.parse(last.group(1)!);
      final terminalLng = double.parse(last.group(2)!);
      // kS1Block1 centre ≈ (39.46202, -0.37659)
      const kS1Block1CentLat = 39.46202;
      const kS1Block1CentLng = -0.37659;
      const tolerance = 0.003;
      expect(
        (terminalLat - kS1Block1CentLat).abs() < tolerance &&
            (terminalLng - kS1Block1CentLng).abs() < tolerance,
        isTrue,
        reason: 'AC-2: Terminal waypoint LatLng($terminalLat, $terminalLng) '
            'must be within 0.003° of kS1Block1 centre '
            'LatLng($kS1Block1CentLat, $kS1Block1CentLng) — '
            'the loop closes near pt0 (NW), not inside the block',
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC-3: _kDisputedArea has >= 3 vertices AND targets kS1Block1
  // -------------------------------------------------------------------------
  group('AC-3: _kDisputedArea has >= 3 vertices targeting kS1Block1', () {
    // GIVEN  _kAttackerLasso overlaps kS1Block1 by >= 15%
    // WHEN   the Sutherland-Hodgman result is hardcoded
    // THEN   _kDisputedArea.length >= 3
    test('_kDisputedArea constant contains >= 3 LatLng vertices', () {
      final src = _sourceText();
      final match = RegExp(
        r'static const _kDisputedArea\s*=\s*\[([\s\S]*?)\];',
      ).firstMatch(src);
      expect(match, isNotNull,
          reason: 'AC-3: _kDisputedArea constant must exist');
      final block = match!.group(1)!;
      final count =
          RegExp(r'LatLng\(').allMatches(block).length;
      expect(
        count,
        greaterThanOrEqualTo(3),
        reason: 'AC-3: _kDisputedArea must have >= 3 vertices '
            '(Sutherland-Hodgman result of _kAttackerLasso ∩ kS1Block1). '
            'Found $count vertices.',
      );
    });

    // GIVEN  _kDisputedArea must be the clip of lasso ∩ kS1Block1 (not kS1Block2/3)
    // WHEN   the source comment describing the const is read
    // THEN   the comment must NOT say "kS1Block2" or "kS1Block3" as the clip target
    //
    // Current file comment explicitly states "intersection of _kAttackerLasso
    // with the union of defender blocks (kS1Block2 ∪ kS1Block3)" — this must
    // be replaced with the kS1Block1 intersection.
    test('_kDisputedArea comment does not describe kS1Block2 or kS1Block3 as clip target', () {
      final src = _sourceText();
      // Locate the _kDisputedArea constant block including its preceding comment.
      // The comment block spans from the first comment line before "static const _kDisputedArea"
      // to the closing "];".
      final match = RegExp(
        r'(// Disputed area[\s\S]*?static const _kDisputedArea\s*=\s*\[[\s\S]*?\];)',
      ).firstMatch(src);
      expect(match, isNotNull,
          reason: 'AC-3: Could not locate _kDisputedArea section in source');
      final section = match!.group(1)!;
      // The current comment says "kS1Block2 ∪ kS1Block3" — after the reset it
      // must describe kS1Block1 as the only clip target.
      expect(
        section,
        isNot(contains('kS1Block2 ∪ kS1Block3')),
        reason: 'AC-3: _kDisputedArea comment must not say "kS1Block2 ∪ kS1Block3" '
            '— after reset the disputed area is lasso ∩ kS1Block1 only',
      );
    });

    // GIVEN  _kDisputedArea must not contain kS1Block2 vertex E (39.461568, -0.375167)
    //   AND  must not contain kS1Block2 vertex F (39.460440, -0.375966)
    //   AND  must not contain the G shared vertex (39.461050, -0.376394)
    // WHEN   the constant is inspected
    // THEN   none of the old kS1Block2/kS1Block3 vertices appear
    //
    // These three coordinates are from the PRE-CHANGE _kDisputedArea targeting
    // kS1Block2 ∪ kS1Block3. After the reset they must not appear.
    test('_kDisputedArea does not contain old kS1Block2/kS1Block3 vertex coordinates', () {
      final src = _sourceText();
      final match = RegExp(
        r'static const _kDisputedArea\s*=\s*\[([\s\S]*?)\];',
      ).firstMatch(src);
      expect(match, isNotNull, reason: 'AC-3: _kDisputedArea must exist');
      final block = match!.group(1)!;
      // E — kS1Block2 vertex at (39.461568, -0.375167)
      expect(block, isNot(contains('39.461568000000000')),
          reason: 'AC-3: Pre-change kS1Block2 vertex E (39.461568) must be removed '
              'from _kDisputedArea — it is not a kS1Block1 vertex');
      // F — kS1Block2 vertex at (39.460440, -0.375966)
      expect(block, isNot(contains('39.460439999999998')),
          reason: 'AC-3: Pre-change kS1Block2 vertex F (39.460440) must be removed '
              'from _kDisputedArea — it is not a kS1Block1 vertex');
      // G — shared kS1Block2/kS1Block3 vertex at (39.461050, -0.376394)
      expect(block, isNot(contains('39.461050000000000')),
          reason: 'AC-3: Pre-change shared kS1Block2/kS1Block3 vertex G (39.461050) '
              'must be removed from _kDisputedArea');
    });
  });

  // -------------------------------------------------------------------------
  // AC-4: _kSharedTransferVertices has >= 3 entries (drawPings guard)
  //       and must reference kS1Block1 edge crossings (not kS1Block2/3)
  // -------------------------------------------------------------------------
  group('AC-4: _kSharedTransferVertices has >= 3 entries targeting kS1Block1', () {
    // GIVEN  hasGenuineDispute == true and _kSharedTransferVertices >= 3
    // WHEN   t advances to lasso-close phase
    // THEN   ping rings fire at _kSharedTransferVertices
    //        (drawPings guard: pts.length >= 3)
    test('_kSharedTransferVertices constant contains >= 3 LatLng vertices', () {
      final src = _sourceText();
      final match = RegExp(
        r'static const _kSharedTransferVertices\s*=\s*\[([\s\S]*?)\];',
      ).firstMatch(src);
      expect(match, isNotNull,
          reason: 'AC-4: _kSharedTransferVertices constant must exist');
      final block = match!.group(1)!;
      final count =
          RegExp(r'LatLng\(').allMatches(block).length;
      expect(
        count,
        greaterThanOrEqualTo(3),
        reason: 'AC-4: _kSharedTransferVertices must have >= 3 entries '
            'for drawPings guard (intro_helpers.dart:274) to fire. '
            'Found $count vertices.',
      );
    });

    // GIVEN  _kSharedTransferVertices must be derived from lasso ∩ kS1Block1 edges
    // WHEN   the constant is inspected for old kS1Block2/3 edge-crossing coordinates
    // THEN   the pre-change lasso ∩ kS1Block2/3 crossing points are absent
    //
    // Pre-change values (from current file lines 72–74):
    //   lasso (pt4→pt5) ∩ block edge A–E: 39.461583456798429
    //   lasso (pt3→pt4) ∩ block edge B–G: 39.461062095301116
    //   lasso (pt1→pt2) ∩ block edge I–G: 39.460375379397249
    // These were computed against the fortify-loop lasso and kS1Block2/3 geometry.
    test('_kSharedTransferVertices does not contain old lasso∩kS1Block2/3 crossing latitudes', () {
      final src = _sourceText();
      final match = RegExp(
        r'static const _kSharedTransferVertices\s*=\s*\[([\s\S]*?)\];',
      ).firstMatch(src);
      expect(match, isNotNull,
          reason: 'AC-4: _kSharedTransferVertices must exist');
      final block = match!.group(1)!;
      // Old crossing point from fortify-lasso ∩ kS1Block2 edge A–E
      expect(block, isNot(contains('39.461583456798429')),
          reason: 'AC-4: Old kS1Block2-edge crossing lat 39.461583456798429 '
              'must be replaced with kS1Block1 edge crossings');
      // Old crossing point from fortify-lasso ∩ kS1Block2/3 shared edge B–G
      expect(block, isNot(contains('39.461062095301116')),
          reason: 'AC-4: Old kS1Block2/3-edge crossing lat 39.461062095301116 '
              'must be replaced with kS1Block1 edge crossings');
      // Old crossing point from fortify-lasso ∩ kS1Block3 edge I–G
      expect(block, isNot(contains('39.460375379397249')),
          reason: 'AC-4: Old kS1Block3-edge crossing lat 39.460375379397249 '
              'must be replaced with kS1Block1 edge crossings');
    });
  });

  // -------------------------------------------------------------------------
  // AC-1: t=0 render produces 3 orange inherited blocks (widget-level)
  // -------------------------------------------------------------------------
  group('AC-1: t=0 frame shows 3 orange inherited blocks, no pre-roll', () {
    // GIVEN  the animation controller is at t=0 (first paint frame)
    //   AND  mapReady is reported
    // WHEN   the CustomPainter executes its paint() pass
    // THEN   drawInheritedBlocks is called with exactly 3 sub-lists
    //   AND  no pre-roll trace is visible (no preRollRoute path executed)
    //
    // We test this by verifying the source structure: after pre-roll deletion,
    // drawInheritedBlocks is called unconditionally in the else-branch at all
    // t < _kUnifyT when lasso not yet closed — which covers t=0.
    test('source calls drawInheritedBlocks outside any t < 0.25 guard', () {
      final src = _sourceText();
      // After deletion: drawInheritedBlocks must exist in the file
      expect(
        src,
        contains('drawInheritedBlocks'),
        reason: 'AC-1: drawInheritedBlocks call must remain in the file',
      );
      // And the t < 0.25 guard must be gone (already checked in AC-7 group,
      // but we repeat here for direct AC-1 traceability).
      expect(
        src,
        isNot(contains('t < 0.25')),
        reason: 'AC-1: Pre-roll t < 0.25 guard must be absent so '
            'drawInheritedBlocks executes at t=0',
      );
    });

    // GIVEN  IntroZones.kS1All contains exactly 3 sub-lists
    //   AND  _inheritedPts is built from kS1All
    // WHEN   t=0 paint() is called
    // THEN   inheritedPts has length 3 (one per Ruzafa block)
    //
    // Verified via source: _inheritedPts = IntroZones.kS1All.map(...).toList()
    test('_inheritedPts is populated from IntroZones.kS1All (3 blocks)', () {
      final src = _sourceText();
      expect(
        src,
        contains('IntroZones.kS1All'),
        reason: 'AC-1: _inheritedPts must be derived from IntroZones.kS1All '
            'to guarantee exactly 3 sub-lists at t=0',
      );
    });

    // GIVEN  IntroCaptureMap is pumped in a widget test
    // WHEN   the widget tree is inspected before mapReady fires
    // THEN   IntroCaptureMap renders without throwing at t=0
    testWidgets('IntroCaptureMap renders without exception at t=0',
        (tester) async {
      await tester.pumpWidget(_pumpCaptureMap());
      // One pump — animation starts at t=0; no map tiles needed for this check.
      await tester.pump();
      // If pre-roll code still runs and tries to access an empty _preRollRoute
      // that was removed, this would throw. Passing means the t=0 path is clean.
      expect(find.byType(IntroCaptureMap), findsOneWidget);
      // Dispose the widget then advance fake time 2 s so FlutterMap's internal
      // tile-debounce timers and any loopController Future.delayed that fired
      // during the pump are fully drained before the test framework checks for
      // pending timers (AutomatedTestWidgetsFlutterBinding._verifyInvariants).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  // -------------------------------------------------------------------------
  // AC-2 (supplemental): No fortify-loop latitudes in _kAttackerLasso
  // -------------------------------------------------------------------------
  group('AC-2 supplemental: _kAttackerLasso contains no fortify-loop latitudes', () {
    for (final lat in _kFortifyLatitudes) {
      test('_kAttackerLasso does not contain fortify-loop latitude $lat', () {
        final src = _sourceText();
        final match = RegExp(
          r'static const _kAttackerLasso\s*=\s*\[([\s\S]*?)\];',
        ).firstMatch(src);
        expect(match, isNotNull,
            reason: 'AC-2: _kAttackerLasso must exist in source file');
        final block = match!.group(1)!;
        expect(
          block,
          isNot(contains(lat)),
          reason: 'AC-2/AC-6: Fortify-loop latitude $lat must not appear '
              'in _kAttackerLasso after the reset',
        );
      });
    }
  });
}
