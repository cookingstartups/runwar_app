// test/run_recorder_completion_durability_test.dart
//
// rw_app-T0606: the runs-row completion write used to be dispatched via
// `onRunUpdate(...).catchError((_) {})` and never awaited by stopRun() - a
// process death (hot-restart, app kill, crash) in the narrow window between
// "user tapped Stop" and that write landing left the row stuck at
// status:'active' forever, with no record anywhere that a Stop had even
// been requested (37 real stuck rows confirmed in production).
//
// This file covers the client-side durability fix:
//   1. stopRun() awaits the terminal write instead of firing it and moving on.
//   2. A bounded retry (3 attempts) runs before giving up, and a failure is
//      logged, never silently swallowed.
//   3. A "closing intent" flag is persisted to SharedPreferences BEFORE the
//      write is attempted, and cleared only once the write succeeds - so a
//      death mid-write leaves proof-of-intent behind for RunRecoveryService
//      to replay on next launch (see recovery_gate_pending_close_test.dart).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runwar_app/services/run_recorder_service.dart';
import 'package:runwar_app/services/run_recovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rw_app-T0606: stopRun terminal-write durability', () {
    late RunRecorderService svc;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      svc = RunRecorderService.instanceForTesting();
      svc.setActiveUser('user-durability');
      svc.injectState(RecorderState.recording);
    });

    tearDown(() {
      svc.reset();
    });

    test(
        'stopRun awaits the terminal write before returning - not fire-and-forget',
        () async {
      final order = <String>[];
      svc.onRunUpdate = (sid, fields) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        order.add('write-done');
      };

      await svc.stopRun();
      order.add('stop-returned');

      expect(
        order,
        ['write-done', 'stop-returned'],
        reason:
            'stopRun() must not return before the terminal write completes',
      );
    });

    test(
        'a failing write retries up to the bound and never throws out of stopRun',
        () async {
      var callCount = 0;
      svc.onRunUpdate = (sid, fields) async {
        callCount++;
        throw Exception('simulated write failure');
      };

      // Must not throw - stopRun() swallows the exhausted-retry case after
      // logging it, so the stop flow always completes cleanly for the user.
      await svc.stopRun();

      expect(
        callCount,
        3,
        reason: 'the write must be retried up to the 3-attempt bound before '
            'stopRun gives up',
      );
    });

    test('a write that succeeds on the second attempt is not retried further',
        () async {
      var callCount = 0;
      svc.onRunUpdate = (sid, fields) async {
        callCount++;
        if (callCount < 2) throw Exception('transient failure');
      };

      await svc.stopRun();

      expect(callCount, 2,
          reason: 'the retry loop must stop as soon as an attempt succeeds');
    });

    test(
        'closing-intent flag is persisted before the write is attempted, and cleared once it succeeds',
        () async {
      String? seenDuringWrite;
      svc.onRunUpdate = (sid, fields) async {
        final prefs = await SharedPreferences.getInstance();
        seenDuringWrite =
            prefs.getString(RunRecorderService.kClosingIntentPrefsKey);
      };

      await svc.stopRun();

      expect(
        seenDuringWrite,
        isNotNull,
        reason:
            'the closing-intent flag must already be on disk before the write '
            'is attempted, so a death mid-write still leaves proof of intent',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(RunRecorderService.kClosingIntentPrefsKey),
        isNull,
        reason: 'the flag must be cleared once the write actually succeeds',
      );
    });

    test('closing-intent flag survives when every write attempt fails',
        () async {
      svc.onRunUpdate = (sid, fields) async {
        throw Exception('simulated write failure');
      };

      await svc.stopRun();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(RunRecorderService.kClosingIntentPrefsKey),
        isNotNull,
        reason:
            'if the write never lands, the flag must stay so a future launch '
            'can finish the write instead of the run staying stuck active',
      );
    });

    test(
        'persisted closing-intent payload carries the same terminal fields '
        'the write itself sends', () async {
      Map<String, dynamic>? capturedFields;
      svc.onRunUpdate = (sid, fields) async {
        final prefs = await SharedPreferences.getInstance();
        final raw =
            prefs.getString(RunRecorderService.kClosingIntentPrefsKey);
        expect(raw, isNotNull,
            reason: 'the flag must be on disk while the write is in flight');
        capturedFields = fields;
      };

      await svc.stopRun();

      expect(capturedFields, isNotNull);
      expect(capturedFields!['status'], 'completed');
      expect(capturedFields!.containsKey('closed_at'), isTrue);
      expect(capturedFields!.containsKey('ended_at'), isTrue);
      expect(capturedFields!.containsKey('distance_m'), isTrue);
      expect(capturedFields!.containsKey('finalized_at'), isTrue);
      expect(capturedFields!['user_id'], 'user-durability');
    });
  });

  group('rw_app-T0606: RunRecoveryService.detectPendingClosingIntent', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns null when no closing-intent flag is on disk', () async {
      final result = await RunRecoveryService.instance
          .detectPendingClosingIntent('user-1');
      expect(result, isNull);
    });

    test('returns the persisted fields when a flag exists for this user',
        () async {
      SharedPreferences.setMockInitialValues({
        RunRecorderService.kClosingIntentPrefsKey: jsonEncode({
          'session_id': 'sess-abc',
          'user_id': 'user-1',
          'status': 'completed',
          'distance_m': 1234.5,
        }),
      });

      final result = await RunRecoveryService.instance
          .detectPendingClosingIntent('user-1');

      expect(result, isNotNull);
      expect(result!['session_id'], 'sess-abc');
      expect(result['status'], 'completed');
      expect(result['distance_m'], 1234.5);
    });

    test('returns null when the persisted flag belongs to a different user',
        () async {
      SharedPreferences.setMockInitialValues({
        RunRecorderService.kClosingIntentPrefsKey: jsonEncode({
          'session_id': 'sess-abc',
          'user_id': 'someone-else',
          'status': 'completed',
        }),
      });

      final result = await RunRecoveryService.instance
          .detectPendingClosingIntent('user-1');

      expect(result, isNull,
          reason:
              'a stale/foreign flag must never be applied to a different signed-in user');
    });

    test('fails closed (returns null) on malformed JSON instead of throwing',
        () async {
      SharedPreferences.setMockInitialValues({
        RunRecorderService.kClosingIntentPrefsKey: 'not-valid-json{{{',
      });

      final result = await RunRecoveryService.instance
          .detectPendingClosingIntent('user-1');

      expect(result, isNull);
    });
  });
}
