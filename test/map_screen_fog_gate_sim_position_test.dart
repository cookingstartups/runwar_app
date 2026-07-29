// test/map_screen_fog_gate_sim_position_test.dart
//
// rw_app-T0615 RED phase.
//
// Why this test exists: commit 8586193 ("fix(map): fog-of-war reveal follows
// simulated GPS position", 2026-07-24) migrated the _FogLayer call site to
// the sim-aware _simOrRealOwnPosition() helper, and its own commit message
// said it was "matching the other 3 call sites" - it knew several call sites
// needed the same migration. The fogCenters block that feeds visibleZones
// (the persistent territory render gate) and CTF pin filtering was never
// migrated and still reads the raw real-device GPS field _currentPosition.
// The pre-existing regression lock in
// test/map_screen_animation_fallback_test.dart (SPEC-0145 item 1) only
// asserts on the one _FogLayer(...) call site that was already fixed - it
// says nothing about fogCenters, visibleZones, or _isRevealedByFog gating -
// so this exact sibling call site stayed broken for months and silently
// dropped claimed zones from the map whenever a simulation run's replayed
// coordinates diverged from the tester's real physical GPS position.
//
// This test asserts directly on the fogCenters construction, not on
// _FogLayer, so it cannot be satisfied by re-fixing the already-fixed call
// site. It also enumerates every _currentPosition-reading fog/visibility
// call site in the file's build() region so the next sibling regression of
// this same class is caught too, not just this one instance.
//
// Uses static source inspection (matching the house style in
// map_screen_animation_fallback_test.dart) rather than pumping widgets,
// since MapScreen carries a FlutterMap and throws tile-fetch exceptions
// under widget-test pumping.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Slices from [startMarker] up to (not including) the next occurrence of
/// [endMarker] after it - the real boundary of the member being inspected,
/// not a guessed character count. Fails loudly, with the missing landmark
/// named, instead of silently reading whatever text happens to sit at a
/// fixed offset. [endMarker] is normally the next sibling member's own
/// signature, so the slice tracks the real method body regardless of how
/// much the method itself grows or shrinks.
String _sliceToNextMember(String src, String startMarker, String endMarker) {
  final start = src.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0),
      reason: 'Landmark not found: "$startMarker". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  final end = src.indexOf(endMarker, start);
  expect(end, greaterThan(start),
      reason: 'Landmark not found after "$startMarker": "$endMarker". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  return src.substring(start, end);
}

/// Isolates the fogCenters list-literal construction: from the
/// `final fogCenters` declaration up to the closing `];` of that list
/// literal. This is a targeted slice, not the whole build() method, so an
/// assertion here cannot be accidentally satisfied by an unrelated part of
/// the file (e.g. the already-fixed _FogLayer call site further down).
String _extractFogCentersBlock(String src) {
  final declIdx = src.indexOf('final fogCenters');
  expect(declIdx, greaterThanOrEqualTo(0),
      reason: 'Landmark not found: "final fogCenters". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  final closeIdx = src.indexOf('];', declIdx);
  expect(closeIdx, greaterThan(declIdx),
      reason: 'Landmark not found: the closing "];" of the fogCenters list literal.');
  return src.substring(declIdx, closeIdx + 2);
}

void main() {
  group('rw_app-T0615: fogCenters must gate on the sim-aware own position, not raw real GPS', () {
    test('the fogCenters list literal does not reference the raw _currentPosition field', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final block = _extractFogCentersBlock(src);
      expect(block, isNot(contains('_currentPosition')),
          reason: 'fogCenters must never read the raw real-device GPS field _currentPosition directly - '
              'during a simulation run this diverges from the replayed claim coordinates and silently '
              'excludes the just-claimed zone from visibleZones, even though it exists correctly '
              'server-side (rw_app-T0615 root cause)');
    });

    test('the fogCenters list literal calls the shared sim-aware derivation _simOrRealOwnPosition()', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final block = _extractFogCentersBlock(src);
      expect(block, contains('_simOrRealOwnPosition()'),
          reason: 'fogCenters must derive its live-position fog circle from the shared '
              '_simOrRealOwnPosition() helper (map_screen.dart:304-314), matching the sibling '
              '_FogLayer call site that commit 8586193 already fixed, so the persistent zone render '
              'gate (visibleZones) and CTF pin filtering track a simulated/replayed position instead '
              'of the tester\'s unrelated real physical location');
    });

    test('no fog/visibility-gating call site in the zones-render build region reads raw _currentPosition', () {
      // Broader guard against the next sibling: isolate the whole method
      // body that builds visibleZones and _buildPolygons(...) from
      // fogCenters, and assert none of it reads the raw field anywhere,
      // not only inside the fogCenters literal itself. This is what would
      // have caught fogCenters even if its shape had drifted from today's
      // exact list-literal form.
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(
          src, 'final visibleZones = fogCenters.isEmpty', '_buildPolygons(visibleZones, pulse)');
      expect(body, isNot(contains('_currentPosition')),
          reason: 'the visibleZones fog-gating region (which decides which zones and CTF pins render '
              'after a claim) must never read the raw real-device GPS field _currentPosition - every '
              'position read here must go through the shared sim-aware _simOrRealOwnPosition() '
              'derivation so simulation runs are gated correctly');
    });
  });
}
