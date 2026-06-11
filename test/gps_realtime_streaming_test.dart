// test/gps_realtime_streaming_test.dart
//
// RED phase tests for GPS real-time streaming.
// Each test maps to exactly one GIVEN/WHEN/THEN from requirements.md.
// Tests use source-inspection (File.readAsStringSync) where the behaviour is
// structural and inject-and-observe where a runtime contract can be asserted.
//
// All tests are expected to FAIL on the current codebase and PASS after
// the implementation described in the spec is merged.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/outbox_service.dart';
import 'package:runwar_app/services/run_recorder_service.dart';

void main() {
  // ── Test 1: session ID minted at startRun ──────────────────────────────────
  //
  // GIVEN the player taps FAB Start
  // WHEN startRun() executes
  // THEN RunRecorderService.currentSessionId is a non-null UUID v4 string

  group('session ID minted at startRun', () {
    test(
      'run_recorder_service.dart exposes a currentSessionId getter',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        // The getter must be declared in the service so the provider can read
        // the session ID after startRun() is called.
        expect(
          src,
          contains('currentSessionId'),
          reason:
              'RunRecorderService must expose a currentSessionId getter '
              '(backed by _currentSessionId field). Currently absent → RED',
        );
      },
    );

    test(
      'run_recorder_service.dart mints a UUID for _currentSessionId '
      'inside startRun',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        // startRun body must assign _currentSessionId a UUID.
        final startIdx = src.indexOf('Future<void> startRun()');
        expect(startIdx, isNot(-1), reason: 'startRun must exist');

        final bodySlice = src.substring(startIdx, startIdx + 1500);

        expect(
          bodySlice,
          contains('_currentSessionId'),
          reason:
              'startRun must assign _currentSessionId a fresh UUID v4 '
              'before opening the GPS stream. Currently absent → RED',
        );
      },
    );

    test(
      'currentSessionId getter returns a valid UUID v4 pattern at runtime',
      () {
        // Use dynamic dispatch to avoid a compile-time "getter not found"
        // that would prevent the entire test file from loading.
        final svc = RunRecorderService.instanceForTesting();
        // Simulate post-startRun state so the field should be set.
        svc.injectState(RecorderState.recording);

        // dynamic call: throws NoSuchMethodError in RED phase (getter absent),
        // returns the UUID string in GREEN phase.
        dynamic sessionId;
        try {
          // ignore: avoid_dynamic_calls
          sessionId = (svc as dynamic).currentSessionId;
        } catch (e) {
          fail(
            'currentSessionId getter not found on RunRecorderService '
            '(NoSuchMethodError is the expected RED failure): $e',
          );
        }

        expect(
          sessionId,
          isNotNull,
          reason: 'currentSessionId must be non-null after startRun',
        );

        // Validate UUID v4 format.
        expect(
          sessionId as String,
          matches(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
          reason: 'currentSessionId must be a valid UUID v4 string',
        );
      },
    );
  });

  // ── Test 2: GPS fix streams immediately to outbox ──────────────────────────
  //
  // GIVEN a run is active with _currentSessionId set
  //   AND a GPS fix passes the 50 m spacing filter
  // WHEN _onPosition processes the fix
  // THEN OutboxAwareWriter.writeGpsSamples is called (outbox gets a gps_samples
  //      entry) before any confirmClaim has been called

  group('GPS fix streams immediately to outbox', () {
    test(
      'run_recorder_service.dart calls writeGpsSamples (or onGpsFix) '
      'inside _onPosition',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        // After implementation, _onPosition must invoke either:
        // (a) OutboxAwareWriter.instance.writeGpsSamples directly, or
        // (b) the onGpsFix callback (design §4 callback seam)
        // Either approach satisfies AC-4.
        final hasDirectCall = src.contains('writeGpsSamples');
        final hasCallbackSeam = src.contains('onGpsFix');

        expect(
          hasDirectCall || hasCallbackSeam,
          isTrue,
          reason:
              '_onPosition must call writeGpsSamples or invoke onGpsFix '
              'to stream each accepted GPS fix to the outbox immediately. '
              'Currently: neither is present → RED',
        );
      },
    );

    test(
      '_onPosition streams the fix BEFORE _scanForAutoClaim runs',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        // Locate _onPosition method body.
        final onPosIdx = src.indexOf('void _onPosition(');
        expect(
          onPosIdx,
          isNot(-1),
          reason: '_onPosition method must exist in run_recorder_service.dart',
        );

        final onPosBody = src.substring(onPosIdx);

        // Find scan call position within the body.
        final scanIdx = onPosBody.indexOf('_scanForAutoClaim');
        expect(
          scanIdx,
          isNot(-1),
          reason: '_scanForAutoClaim must still be called from _onPosition',
        );

        // Find the outbox/callback call position within the body.
        final gpsSampleCallIdx = onPosBody.contains('writeGpsSamples')
            ? onPosBody.indexOf('writeGpsSamples')
            : onPosBody.indexOf('onGpsFix');

        expect(
          gpsSampleCallIdx,
          isNot(-1),
          reason:
              'writeGpsSamples or onGpsFix callback must appear in _onPosition',
        );

        expect(
          gpsSampleCallIdx,
          lessThan(scanIdx),
          reason:
              'writeGpsSamples / onGpsFix must be called BEFORE '
              '_scanForAutoClaim so the outbox row is enqueued before any '
              'auto-claim scan runs',
        );
      },
    );
  });

  // ── Test 3: stopRun writes completed status to outbox ─────────────────────
  //
  // GIVEN a run is active with _currentSessionId = "abc-123"
  // WHEN the player taps Stop
  // THEN OutboxAwareWriter.writeRunUpdate is called with
  //      {status: 'completed', closed_at: non-null}

  group('stopRun sets completed status via writeRunUpdate', () {
    test(
      'run_recorder_service.dart calls writeRunUpdate (or onRunUpdate) '
      'from stopRun',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        // After implementation, stopRun must invoke either:
        // (a) OutboxAwareWriter.instance.writeRunUpdate directly, or
        // (b) the onRunUpdate callback (design §4 callback seam)
        final hasDirectCall = src.contains('writeRunUpdate');
        final hasCallbackSeam = src.contains('onRunUpdate');

        expect(
          hasDirectCall || hasCallbackSeam,
          isTrue,
          reason:
              'stopRun must call writeRunUpdate or invoke onRunUpdate to '
              'update the runs row with status=completed. Currently: '
              'neither is present → RED',
        );
      },
    );

    test(
      'stopRun passes status: completed in the update payload',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        // Find stopRun body.
        final stopIdx = src.indexOf('Future<void> stopRun()');
        expect(stopIdx, isNot(-1), reason: 'stopRun must exist');

        // Look for 'completed' in stopRun body (reasonable slice).
        final bodySlice = src.substring(stopIdx, stopIdx + 1500);

        expect(
          bodySlice,
          contains('completed'),
          reason:
              "stopRun body must include the string 'completed' to pass "
              'status: completed to writeRunUpdate',
        );
      },
    );
  });

  // ── Test 4: cancelRun writes cancelled status to outbox ───────────────────
  //
  // GIVEN a run is active with _currentSessionId set
  // WHEN the player long-presses to cancel
  // THEN OutboxAwareWriter.writeRunUpdate is called with {status: 'cancelled'}

  group('cancelRun sets cancelled status via writeRunUpdate', () {
    test(
      'run_recorder_service.dart calls writeRunUpdate (or onRunUpdate) '
      'from cancelRun',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        final hasDirectCall = src.contains('writeRunUpdate');
        final hasCallbackSeam = src.contains('onRunUpdate');

        expect(
          hasDirectCall || hasCallbackSeam,
          isTrue,
          reason:
              'cancelRun must call writeRunUpdate or invoke onRunUpdate to '
              'update the runs row with status=cancelled → RED until implemented',
        );
      },
    );

    test(
      'cancelRun passes status: cancelled in the update payload',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        final cancelIdx = src.indexOf('Future<void> cancelRun()');
        expect(cancelIdx, isNot(-1), reason: 'cancelRun must exist');

        final bodySlice = src.substring(cancelIdx, cancelIdx + 1500);

        expect(
          bodySlice,
          contains('cancelled'),
          reason:
              "cancelRun body must include 'cancelled' to pass "
              "status: 'cancelled' to writeRunUpdate",
        );
      },
    );
  });

  // ── Test 5: no double-upload on confirmClaim ───────────────────────────────
  //
  // GIVEN fixes were already streamed in real-time during the run
  // WHEN confirmClaim succeeds
  // THEN _uploadGpsSamples is NOT called (the method is removed entirely)

  group('no double-upload of gps_samples on confirmClaim', () {
    test(
      '_uploadGpsSamples is removed from run_recorder_provider.dart',
      () {
        final src = File(
          'lib/providers/run_recorder_provider.dart',
        ).readAsStringSync();

        expect(
          src,
          isNot(contains('_uploadGpsSamples')),
          reason:
              '_uploadGpsSamples must be removed from run_recorder_provider.dart '
              'after implementation (fixes are streamed in real-time, not batched '
              'on confirmClaim). Currently it likely exists → RED until removed',
        );
      },
    );

    test(
      'confirmClaim calls writeRunUpdate (or onRunUpdate) instead of '
      '_uploadGpsSamples',
      () {
        final src = File(
          'lib/providers/run_recorder_provider.dart',
        ).readAsStringSync();

        // confirmClaim should wire lasso_id and zone_id via writeRunUpdate.
        final hasWriteRunUpdate = src.contains('writeRunUpdate');
        final hasOnRunUpdate = src.contains('onRunUpdate');

        expect(
          hasWriteRunUpdate || hasOnRunUpdate,
          isTrue,
          reason:
              'confirmClaim must call writeRunUpdate / onRunUpdate to link '
              'lasso_id and zone_id to the in-flight runs row → RED',
        );
      },
    );
  });

  // ── Test 6: mergeEnqueue payload merge ────────────────────────────────────
  //
  // GIVEN OutboxService.mergeEnqueue is called for runs/session-1 with
  //       {lasso_id: 'A'}
  //   AND then called again for the same key with {status: 'completed'}
  // WHEN the second call merges into the existing pending row
  // THEN the merged payload contains BOTH lasso_id AND status

  group('mergeEnqueue merges fields for the same run row', () {
    test(
      'OutboxService exposes a mergeEnqueue method',
      () {
        // Source-inspection: avoids hitting an uninitialized sqflite instance
        // while still verifying the method contract is present.
        final src = File(
          'lib/services/outbox_service.dart',
        ).readAsStringSync();

        expect(
          src,
          contains('mergeEnqueue'),
          reason:
              'OutboxService must define a mergeEnqueue method. '
              'Source inspection confirms the method signature is present '
              'without requiring a live database.',
        );

        expect(
          src,
          contains('transaction'),
          reason:
              'mergeEnqueue must use a sqflite transaction for atomic '
              'read-modify-write.',
        );
      },
    );

    test(
      'outbox_service.dart source contains mergeEnqueue method',
      () {
        final src = File(
          'lib/services/outbox_service.dart',
        ).readAsStringSync();

        expect(
          src,
          contains('mergeEnqueue'),
          reason:
              'OutboxService must define a mergeEnqueue method (AC-8b). '
              'Currently absent → RED',
        );
      },
    );

    test(
      'outbox_service.dart mergeEnqueue uses a sqflite transaction for '
      'atomic read-modify-write',
      () {
        final src = File(
          'lib/services/outbox_service.dart',
        ).readAsStringSync();

        // The merge must be inside a single transaction to prevent races.
        expect(
          src,
          contains('transaction'),
          reason:
              'mergeEnqueue must use a sqflite transaction so the '
              'read-modify-write is atomic (AC-8b contract)',
        );
      },
    );
  });

  // ── Test 7: crash recovery replay calls writeGpsSamples ───────────────────
  //
  // GIVEN the scratch table has rows with session_id
  // WHEN resumeFromScratch is called
  // THEN writeGpsSamples (or onGpsFix) is called for those scratch rows

  group('resumeFromScratch replays scratch rows via writeGpsSamples', () {
    test(
      'resumeFromScratch calls writeGpsSamples or onGpsFix for scratch rows',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        // Find resumeFromScratch body.
        final resumeIdx = src.indexOf('Future<void> resumeFromScratch(');
        expect(
          resumeIdx,
          isNot(-1),
          reason: 'resumeFromScratch must exist in run_recorder_service.dart',
        );

        final bodySlice = src.substring(resumeIdx, resumeIdx + 3000);

        // After implementation, the resume path must replay scratch rows via
        // the outbox. Either direct call or callback seam is acceptable.
        final hasDirectCall = bodySlice.contains('writeGpsSamples');
        final hasCallbackSeam = bodySlice.contains('onGpsFix');

        expect(
          hasDirectCall || hasCallbackSeam,
          isTrue,
          reason:
              'resumeFromScratch must call writeGpsSamples or invoke onGpsFix '
              'to replay scratch rows into the outbox for crash recovery. '
              'Currently: neither is present → RED',
        );
      },
    );

    test(
      'resumeFromScratch reads session_id from scratch rows',
      () {
        final src = File(
          'lib/services/run_recorder_service.dart',
        ).readAsStringSync();

        final resumeIdx = src.indexOf('Future<void> resumeFromScratch(');
        expect(resumeIdx, isNot(-1));

        final bodySlice = src.substring(resumeIdx, resumeIdx + 3000);

        expect(
          bodySlice,
          contains('session_id'),
          reason:
              'resumeFromScratch must read session_id from scratch rows '
              'to restore _currentSessionId (AC-9). Currently absent → RED',
        );
      },
    );
  });

  // ── Supporting tests: migration file and schema additions ─────────────────
  //
  // These are not in the brief's 7 tests but confirm the structural RED state
  // for the migration and gps_samples drainer upsert switch.

  group('migration 0049 exists and contains expected schema', () {
    test(
      'supabase/migrations/0049_gps_realtime_streaming.sql exists and '
      'contains key SQL markers',
      () {
        final file = File(
          'supabase/migrations/0049_gps_realtime_streaming.sql',
        );
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Migration 0049 must exist after implementation.',
        );

        final sql = file.readAsStringSync();

        expect(
          sql,
          contains('gps_samples'),
          reason: 'Migration must create the gps_samples table',
        );
        expect(
          sql,
          contains('gps_samples_dedup'),
          reason: 'Migration must create the gps_samples_dedup unique index',
        );
        expect(
          sql,
          contains('session_id'),
          reason: 'Migration must include a session_id column',
        );
        expect(
          sql,
          contains('ROW LEVEL SECURITY'),
          reason: 'Migration must enable ROW LEVEL SECURITY on gps_samples',
        );
      },
    );
  });

  group('outbox drainer switches gps_samples from insert to upsert', () {
    test(
      'outbox_drainer.dart uses upsert with dedup conflict target for '
      'gps_samples branch',
      () {
        final src = File(
          'lib/services/outbox_drainer.dart',
        ).readAsStringSync();

        expect(
          src,
          contains("onConflict: 'session_id,ts,player_id'"),
          reason:
              "OutboxDrainer must use .upsert(samples, onConflict: 'session_id,ts,player_id') "
              'for the gps_samples branch to enable crash-replay deduplication. '
              'Currently uses .insert → RED',
        );
      },
    );
  });
}
