// test/services/database/zones_repository_supabase_debounced_teardown_test.dart
//
// Source-inspection test (this repository has no live-client test seam, per
// the precedent in test/services/database/zones_repository_test.dart's own
// header) for:
//   - AC-B1: a resubscribe within 300ms of the last unsubscribe reuses the
//     existing StreamController instead of tearing it down and recreating
//     it (deferred-close Timer).
//   - AC-D1: a single bounded 2-second retry runs before _fetchAndEmit
//     surfaces an error via addError.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sourceOf(String relativePath) =>
    File(relativePath).readAsStringSync();

String _sliceMethodBody(String src, String methodOrCallbackSignature) {
  final start = src.indexOf(methodOrCallbackSignature);
  expect(start, greaterThanOrEqualTo(0),
      reason: 'Landmark not found: "$methodOrCallbackSignature" - '
          'zones_repository_supabase.dart\'s structure moved, or this member does not exist yet (expected RED)');
  final braceStart = src.indexOf('{', start);
  var depth = 0;
  var i = braceStart;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return src.substring(start, i + 1);
}

void main() {
  const path = 'lib/services/database/zones_repository_supabase.dart';

  group('AC-B1: deferred controller teardown', () {
    test('onCancel defers teardown via a Timer instead of closing synchronously', () {
      final src = _sourceOf(path);
      final body = _sliceMethodBody(src, 'onCancel: () {');

      expect(body, contains('Timer('),
          reason: 'onCancel must schedule a deferred-close Timer, not close the controller synchronously');
      expect(body, contains('_pendingClose[city] ='),
          reason: 'the deferred-close Timer must be keyed by city in _pendingClose so a resubscribe can cancel it');
    });

    test('watchByCity cancels any pending close before the containsKey resubscribe check', () {
      final src = _sourceOf(path);
      final body = _sliceMethodBody(src, 'Stream<List<Zone>> watchByCity(String city) {');

      final cancelIdx = body.indexOf('_pendingClose.remove(city)?.cancel()');
      final containsKeyIdx = body.indexOf('_controllers.containsKey(city)');

      expect(cancelIdx, greaterThanOrEqualTo(0),
          reason: 'watchByCity must cancel any pending close for this city (_pendingClose.remove(city)?.cancel())');
      expect(containsKeyIdx, greaterThan(cancelIdx),
          reason: 'the pending-close cancel must happen BEFORE the containsKey resubscribe branch, so a '
              'resubscribe that hits that branch (not onListen) still cancels the pending teardown');
    });

    test('dispose cancels all outstanding pending-close timers', () {
      final src = _sourceOf(path);
      final body = _sliceMethodBody(src, 'Future<void> dispose() async {');

      expect(body, contains('_pendingClose'),
          reason: 'dispose must iterate and cancel outstanding _pendingClose timers before closing controllers');
      expect(body, contains('.cancel()'),
          reason: 'dispose must call .cancel() on each outstanding pending-close timer');
    });
  });

  group('AC-D1: single bounded retry before addError', () {
    test('_fetchAndEmit declares an isRetry parameter and schedules a Timer-based retry on Err', () {
      final src = _sourceOf(path);
      final body = _sliceMethodBody(src, '_fetchAndEmit(String city');

      expect(body, contains('isRetry'),
          reason: '_fetchAndEmit must accept a named isRetry parameter to distinguish a retry from an original attempt');
      expect(body, contains('Timer('),
          reason: '_fetchAndEmit must schedule a Timer-based retry on the first Err before surfacing addError');
    });

    test('a non-retry Err returns early (via if (!isRetry) { ...; return; }) before ever reaching addError', () {
      final src = _sourceOf(path);
      final body = _sliceMethodBody(src, '_fetchAndEmit(String city');

      final errCaseIdx = body.indexOf('case Err<List<Zone>>');
      expect(errCaseIdx, greaterThanOrEqualTo(0),
          reason: 'the Err case of the fetch result switch must exist');
      final errBlock = body.substring(errCaseIdx);

      final guardIdx = errBlock.indexOf('if (!isRetry)');
      expect(guardIdx, greaterThanOrEqualTo(0),
          reason: 'the Err branch must guard the retry scheduling with if (!isRetry)');

      final guardCloseIdx = errBlock.indexOf('}', guardIdx);
      expect(guardCloseIdx, greaterThan(guardIdx));
      final guardBody = errBlock.substring(guardIdx, guardCloseIdx);

      expect(guardBody, contains('return;'),
          reason: 'the if (!isRetry) block must return early after scheduling the retry Timer, so a non-retry '
              'failure never falls through to addError on the same invocation - without this early return, '
              'addError would still fire immediately alongside the scheduled retry, defeating AC-D1\'s '
              '"one retry before surfacing an error" contract');

      final addErrorIdx = errBlock.indexOf('.addError(');
      expect(addErrorIdx, greaterThan(guardCloseIdx),
          reason: 'addError must be textually placed after the if (!isRetry) { ...; return; } guard, so it is '
              'only reached once that block has already returned on a non-retry failure (i.e. only reached on '
              'the retry attempt\'s own failure)');
    });
  });
}
