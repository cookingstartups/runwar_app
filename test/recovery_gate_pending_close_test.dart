// test/recovery_gate_pending_close_test.dart
//
// rw_app-T0606: RecoveryGate must finish a run whose Stop was already
// decided but whose completion write may not have landed before the
// process died - silently, with no Resume/Discard prompt, because the
// user's intent (stop, not resume) is already known from the persisted
// closing-intent flag. This mirrors the source-inspection precedent in
// test/recovery_gate_discard_test.dart: _check/_finishPendingClose are
// private members on a private ConsumerState reaching through
// OutboxAwareWriter/RunRecoveryService singletons, so exercising this at
// runtime would require mocking a chain of 3+ singletons for no behavioral
// gain over reading the source directly (flutter-test-patterns.md).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sliceToNextMember(String src, String startMarker, String endMarker) {
  final start = src.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0),
      reason:
          'Landmark not found: "$startMarker". recovery_gate.dart\'s structure moved - update this anchor, do not delete the check.');
  final end = src.indexOf(endMarker, start);
  expect(end, greaterThan(start),
      reason:
          'Landmark not found after "$startMarker": "$endMarker". recovery_gate.dart\'s structure moved - update this anchor, do not delete the check.');
  return src.substring(start, end);
}

String _checkBody(String src) =>
    _sliceToNextMember(src, 'Future<void> _check(', '_onResume(');

String _finishPendingCloseBody(String src) =>
    _sliceToNextMember(src, '_finishPendingClose(', '_onResume(');

void main() {
  group('rw_app-T0606: pending closing intent is checked before the orphan '
      'prompt', () {
    test('_check queries detectPendingClosingIntent before detectOrphan', () {
      final src = File('lib/screens/recovery_gate.dart').readAsStringSync();
      final body = _checkBody(src);
      final pendingIdx = body.indexOf('detectPendingClosingIntent');
      final orphanIdx = body.indexOf('detectOrphan(widget.userId)');
      expect(pendingIdx, greaterThanOrEqualTo(0),
          reason:
              '_check must query RunRecoveryService.detectPendingClosingIntent');
      expect(orphanIdx, greaterThan(pendingIdx),
          reason:
              'the pending-closing-intent check must run before the ambiguous orphan check, so a known Stop intent always wins');
    });

    test('a pending closing intent is finished without ever setting '
        '_orphan to a non-null value', () {
      final src = File('lib/screens/recovery_gate.dart').readAsStringSync();
      final body = _checkBody(src);
      final pendingBranchStart = body.indexOf('if (pendingClose != null)');
      expect(pendingBranchStart, greaterThanOrEqualTo(0));
      final pendingBranch = body.substring(
          pendingBranchStart, body.indexOf('final orphan ='));
      expect(pendingBranch, contains('_finishPendingClose'),
          reason:
              'a detected pending close must be resolved via _finishPendingClose');
      expect(pendingBranch, contains('_orphan = null'),
          reason:
              'the orphan dialog must never be shown when a closing intent is present');
      expect(pendingBranch, contains('_decisionMade = true'),
          reason:
              'a pending close must set _decisionMade so build() proceeds straight to widget.child with no prompt');
    });

    test('_finishPendingClose writes via OutboxAwareWriter, guarded by a '
        'null sessionId check', () {
      final src = File('lib/screens/recovery_gate.dart').readAsStringSync();
      final body = _finishPendingCloseBody(src);
      final guardIdx = body.indexOf('sessionId != null');
      final writeIdx = body.indexOf('writeRunUpdate');
      expect(guardIdx, greaterThanOrEqualTo(0),
          reason: 'a null-sessionId guard must exist before writing');
      expect(writeIdx, greaterThan(guardIdx),
          reason:
              'writeRunUpdate must be nested inside the sessionId != null guard');
      expect(body, contains('OutboxAwareWriter'),
          reason:
              '_finishPendingClose must reuse the same durable write path as the rest of the recovery flow');
    });

    test('_finishPendingClose clears both run_scratch and the persisted '
        'closing-intent flag', () {
      final src = File('lib/screens/recovery_gate.dart').readAsStringSync();
      final body = _finishPendingCloseBody(src);
      expect(body, contains('clearScratch'),
          reason:
              'local run_scratch must be cleared so a future launch does not re-detect an orphan for this same session');
      expect(body, contains('clearPersistedClosingIntent'),
          reason:
              'the closing-intent flag must be cleared once the write has been reissued, or every future launch would re-finish the same session');
    });
  });
}
