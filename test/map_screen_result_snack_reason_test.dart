// test/map_screen_result_snack_reason_test.dart
//
// R3/R4: _onAutoClaimOutcome's TerritoryResult.failed branch must call the
// existing styled _showResultSnack path (not construct an ad hoc SnackBar
// inline and return early), and _showResultSnack must select reason-specific
// copy from outcome.reason, falling back to the current generic copy when
// reason is null/unrecognized. R4 confirms the mission1Claim/mission2Attack
// early returns can never fire for a failed outcome.
//
// Per flutter-test-patterns.md ("When NOT to use testWidgets for map
// tests"), this uses static source inspection rather than pumping
// MapScreen, matching test/map_screen_gate_toast_test.dart's own
// established convention for exactly this class of AC.
//
// Flutter SDK availability: NOT confirmed runnable in this environment at
// authoring time. Written to the same rigor as if runnable; NOT executed
// here. Run with: flutter test test/map_screen_result_snack_reason_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _path = 'lib/screens/map_screen.dart';

String _sliceToNextMember(String src, String startMarker, String endMarker) {
  final start = src.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0),
      reason: 'Landmark not found: "$startMarker" in $_path.');
  final end = src.indexOf(endMarker, start);
  expect(end, greaterThan(start),
      reason: 'Landmark not found after "$startMarker": "$endMarker" in $_path.');
  return src.substring(start, end);
}

void main() {
  group('R3: TerritoryResult.failed calls the styled _showResultSnack path, not an inline ad hoc SnackBar', () {
    test('the failed-outcome branch inside _onAutoClaimOutcome calls _showResultSnack(context, outcome)', () {
      final src = File(_path).readAsStringSync();
      final body = _sliceToNextMember(src, '_onAutoClaimOutcome', 'void _showResultSnack(BuildContext context, ClaimOutcome outcome) {');
      expect(body, contains('_showResultSnack(context, outcome)'),
          reason: 'the failed branch must call _showResultSnack(context, outcome) - the existing styled/haptic/icon presentation path - instead of the current inline ad hoc SnackBar-and-early-return. Today this call does not exist inside _onAutoClaimOutcome\'s failed branch, which is exactly the dead-code path this requirement replaces.');
    });

    test('ErrorLogService.logClientError is still called for a failed outcome (diagnostic call preserved, unchanged)', () {
      final src = File(_path).readAsStringSync();
      final body = _sliceToNextMember(src, '_onAutoClaimOutcome', 'void _showResultSnack(BuildContext context, ClaimOutcome outcome) {');
      expect(body, contains('ErrorLogService.logClientError'),
          reason: 'R3 requires the existing diagnostic call to be preserved unchanged - only the player-facing surface should change.');
    });
  });

  group('R3: _showResultSnack maps outcome.reason to reason-specific copy, with a generic fallback', () {
    test('_showResultSnack contains a reason-to-copy mapping keyed on outcome.reason', () {
      final src = File(_path).readAsStringSync();
      final body = _sliceToNextMember(src, 'void _showResultSnack(BuildContext context, ClaimOutcome outcome) {', '\n}');
      expect(body, contains('outcome.reason'),
          reason: '_showResultSnack must branch on outcome.reason to select player-facing copy (mirroring the existing _onGateRejected/GateRejectionReason mapping style, design.md R3) - today _showResultSnack never reads outcome.reason at all.');
    });

    test('a speed_violation reason produces reason-specific copy, not the generic fallback string', () {
      final src = File(_path).readAsStringSync();
      final body = _sliceToNextMember(src, 'void _showResultSnack(BuildContext context, ClaimOutcome outcome) {', '\n}');
      expect(body, contains("'speed_violation'"),
          reason: '_showResultSnack must recognize the speed_violation reason code and select distinct copy for it - today no reason-code switch exists in this function at all.');
    });

    test('the generic fallback copy ("Could not claim zone - try again") still exists for a null/unrecognized reason', () {
      final src = File(_path).readAsStringSync();
      expect(src, contains('Could not claim zone'),
          reason: 'the existing generic fallback copy must be preserved for a null or unrecognized reason (R3\'s IF/THEN unwanted-behaviour case) - if this fails, the fallback string itself was changed or removed rather than kept as the fallback.');
    });
  });

  group('R4: mission1Claim/mission2Attack early returns are still unreachable for a failed outcome (regression guard, no behavior change)', () {
    test('the failed-branch return precedes both mission1Claim and mission2Attack checks in source order', () {
      final src = File(_path).readAsStringSync();
      final body = _sliceToNextMember(src, '_onAutoClaimOutcome', 'void _showResultSnack(BuildContext context, ClaimOutcome outcome) {');
      final failedIdx = body.indexOf('TerritoryResult.failed');
      final mission1Idx = body.indexOf('mission1Claim');
      final mission2Idx = body.indexOf('mission2Attack');
      expect(failedIdx, greaterThanOrEqualTo(0),
          reason: 'a TerritoryResult.failed check must exist inside _onAutoClaimOutcome.');
      expect(mission1Idx, greaterThan(-1),
          reason: 'the mission1Claim branch must still exist inside _onAutoClaimOutcome.');
      expect(mission2Idx, greaterThan(-1),
          reason: 'the mission2Attack branch must still exist inside _onAutoClaimOutcome.');
      expect(failedIdx, lessThan(mission1Idx),
          reason: 'R4: the failed-outcome check must run BEFORE the mission1Claim branch, so a failed outcome can never reach it - if this fails, a future refactor reordered the branches and R4 is now violated.');
      expect(failedIdx, lessThan(mission2Idx),
          reason: 'R4: the failed-outcome check must run BEFORE the mission2Attack branch, so a failed outcome can never reach it.');
    });
  });
}
