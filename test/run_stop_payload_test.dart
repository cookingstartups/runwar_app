// test/run_stop_payload_test.dart
//
// Source-inspection tests that verify stopRun, cancelRun, and the
// auto-claim lasso linkage all include user_id in their run update payloads,
// and that the stop/cancel guards are extended to check _activeUserId.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns the substring of [src] starting at [marker] up to the first
/// occurrence of [closeSeq] after that point (inclusive). Returns null if
/// either anchor is not found.
String? _extractBlock(String src, String marker, String closeSeq) {
  final start = src.indexOf(marker);
  if (start == -1) return null;
  final end = src.indexOf(closeSeq, start + marker.length);
  if (end == -1) return null;
  return src.substring(start, end + closeSeq.length);
}

void main() {
  const servicePath = 'lib/services/run_recorder_service.dart';
  const providerPath = 'lib/providers/run_recorder_provider.dart';

  // ---------------------------------------------------------------------------
  // stopRun — completed payload includes user_id
  // ---------------------------------------------------------------------------
  group('stopRun completed payload includes user_id', () {
    late String stopBlock;

    setUp(() {
      final src = File(servicePath).readAsStringSync();
      // Anchor on the 'status': 'completed' string to locate the stopRun block.
      final block = _extractBlock(src, "'status': 'completed'", '});');
      expect(
        block,
        isNotNull,
        reason:
            "Could not find the 'status': 'completed' block in $servicePath. "
            'The stopRun runCb call must include this key.',
      );
      stopBlock = block!;
    });

    test('stopRun payload contains user_id key', () {
      expect(
        stopBlock,
        contains("'user_id':"),
        reason:
            'stopRun must include user_id in the completed-status payload '
            'so the runs upsert satisfies the RLS USING clause and does not '
            'raise Postgres error 42501.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // stopRun — guard includes _activeUserId null check
  // ---------------------------------------------------------------------------
  group('stopRun guard checks _activeUserId before invoking callback', () {
    test('stopRun guard condition references _activeUserId', () {
      final src = File(servicePath).readAsStringSync();
      // Find the if-guard that precedes the completed-status runCb call.
      // The guard must include an _activeUserId check (uid != null or direct).
      // Strategy: find the guard line(s) near 'status': 'completed'.
      final completedIdx = src.indexOf("'status': 'completed'");
      expect(
        completedIdx,
        greaterThan(-1),
        reason: "Could not find 'status': 'completed' in $servicePath.",
      );
      // Scan backwards up to 300 chars for the if ( guard.
      final guardRegion = src.substring(
        completedIdx > 300 ? completedIdx - 300 : 0,
        completedIdx,
      );
      expect(
        guardRegion,
        anyOf(contains('_activeUserId != null'), contains('uid != null')),
        reason:
            'The if-guard before the stopRun runCb call must check that '
            '_activeUserId (or its local alias uid) is non-null. '
            'Without this guard, a null user_id payload bypasses RLS.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // cancelRun — cancelled payload includes user_id
  // ---------------------------------------------------------------------------
  group('cancelRun cancelled payload includes user_id', () {
    late String cancelBlock;

    setUp(() {
      final src = File(servicePath).readAsStringSync();
      final block = _extractBlock(src, "'status': 'cancelled'", '});');
      expect(
        block,
        isNotNull,
        reason:
            "Could not find the 'status': 'cancelled' block in $servicePath. "
            'The cancelRun runCb call must include this key.',
      );
      cancelBlock = block!;
    });

    test('cancelRun payload contains user_id key', () {
      expect(
        cancelBlock,
        contains("'user_id':"),
        reason:
            'cancelRun must include user_id in the cancelled-status payload '
            'so the runs upsert satisfies the RLS USING clause and does not '
            'raise Postgres error 42501.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // cancelRun — guard includes _activeUserId null check
  // ---------------------------------------------------------------------------
  group('cancelRun guard checks _activeUserId before invoking callback', () {
    test('cancelRun guard condition references _activeUserId', () {
      final src = File(servicePath).readAsStringSync();
      final cancelledIdx = src.indexOf("'status': 'cancelled'");
      expect(
        cancelledIdx,
        greaterThan(-1),
        reason: "Could not find 'status': 'cancelled' in $servicePath.",
      );
      final guardRegion = src.substring(
        cancelledIdx > 300 ? cancelledIdx - 300 : 0,
        cancelledIdx,
      );
      expect(
        guardRegion,
        anyOf(contains('_activeUserId != null'), contains('uid != null')),
        reason:
            'The if-guard before the cancelRun runCb call must check that '
            '_activeUserId (or its local alias uid) is non-null. '
            'Without this guard, a null user_id payload bypasses RLS.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // confirmClaim lasso linkage — writeRunUpdate payload includes user_id
  // ---------------------------------------------------------------------------
  group('confirmClaim lasso linkage writeRunUpdate payload includes user_id', () {
    late String lassoBlock;

    setUp(() {
      final src = File(providerPath).readAsStringSync();
      final block = _extractBlock(src, "'lasso_id':", '},');
      expect(
        block,
        isNotNull,
        reason:
            "Could not find the 'lasso_id': block in $providerPath. "
            'The confirmClaim writeRunUpdate call must include this key.',
      );
      lassoBlock = block!;
    });

    test('lasso linkage payload contains user_id key', () {
      expect(
        lassoBlock,
        contains("'user_id':"),
        reason:
            'The writeRunUpdate call in confirmClaim must include user_id '
            'so the runs upsert satisfies the RLS USING clause and does not '
            'raise Postgres error 42501.',
      );
    });
  });
}
