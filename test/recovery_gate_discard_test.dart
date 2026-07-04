// test/recovery_gate_discard_test.dart
//
// RED phase - R5-AC1, R5-AC2: discarding an orphaned run with a known
// sessionId must close the server-side runs row via
// OutboxAwareWriter.writeRunUpdate; discarding with no sessionId must
// degrade gracefully (no server call attempted). _onDiscard is a private
// method on a private ConsumerState, and the write path goes through the
// OutboxAwareWriter singleton (which itself wraps OutboxService/Supabase),
// so exercising this at runtime would require mocking a chain of 3+
// singletons for no behavioral gain over reading the source directly
// (flutter-test-patterns.md: prefer source inspection when the AC maps
// directly to source structure). This mirrors the existing precedent in
// test/connectivity_gate_outbox_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R5-AC1: discard with a known sessionId closes the server runs row', () {
    test('_onDiscard calls OutboxAwareWriter.instance.writeRunUpdate', () {
      final src = File('lib/screens/recovery_gate.dart').readAsStringSync();
      final idx = src.indexOf('_onDiscard(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = src.substring(idx, (idx + 900).clamp(0, src.length));
      expect(body, contains('OutboxAwareWriter'),
          reason: '_onDiscard must write a server-side runs update via OutboxAwareWriter');
      expect(body, contains('writeRunUpdate'),
          reason: '_onDiscard must call writeRunUpdate for the orphaned sessionId');
    });

    test('the discard write shape matches cancelRun (status cancelled + closed_at)', () {
      final src = File('lib/screens/recovery_gate.dart').readAsStringSync();
      final idx = src.indexOf('_onDiscard(');
      final body = src.substring(idx, (idx + 900).clamp(0, src.length));
      expect(body, contains("'cancelled'"),
          reason: 'Discard must set status to the terminal value used by cancelRun()');
      expect(body, contains('closed_at'),
          reason: 'Discard must stamp closed_at, mirroring cancelRun()\'s write shape');
    });

    test('_onDiscard still clears local run_scratch unconditionally (existing behavior)', () {
      final src = File('lib/screens/recovery_gate.dart').readAsStringSync();
      final idx = src.indexOf('_onDiscard(');
      final body = src.substring(idx, (idx + 900).clamp(0, src.length));
      expect(body, contains('clearScratch'),
          reason: 'The existing clearScratch(widget.userId) call must be preserved alongside the new server write');
    });
  });

  group('R5-AC2: discard with no known sessionId degrades gracefully', () {
    test('the server write is guarded by a sessionId != null check', () {
      final src = File('lib/screens/recovery_gate.dart').readAsStringSync();
      final idx = src.indexOf('_onDiscard(');
      final body = src.substring(idx, (idx + 900).clamp(0, src.length));
      final guardIdx = body.indexOf('sessionId != null');
      final writeIdx = body.indexOf('writeRunUpdate');
      expect(guardIdx, greaterThanOrEqualTo(0),
          reason: 'A null-sessionId guard must exist so no server update is attempted without one');
      expect(writeIdx, greaterThan(guardIdx),
          reason: 'writeRunUpdate must be nested inside the sessionId != null guard, not called unconditionally');
    });
  });
}
