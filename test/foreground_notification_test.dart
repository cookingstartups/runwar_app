
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/run_recorder_service.dart';

void main() {
  // =========================================================================
  // Foreground notification constants
  //
  // These tests assert the @visibleForTesting static constants that control
  // the foreground notification title, tick cadence, and channel importance.
  // They compile-fail until the constants are added to RunRecorderService.
  // =========================================================================

  group('foreground notification constants - correct values', () {
    // GIVEN the RunRecorderService exposes kNotificationTitle
    // WHEN the constant is read
    // THEN it equals exactly "RunWar - Active Session"
    test('notification title is "RunWar - Active Session"', () {
      expect(
        RunRecorderService.kNotificationTitle,
        equals('RunWar - Active Session'),
        reason: 'Title must be branded; the old "Run in progress" string is not acceptable',
      );
    });

    // GIVEN the RunRecorderService exposes kForegroundTaskInterval
    // WHEN the constant is read
    // THEN it equals Duration(seconds: 15)
    test('foreground task interval is 15 seconds', () {
      expect(
        RunRecorderService.kForegroundTaskInterval,
        equals(const Duration(seconds: 15)),
        reason: 'Cadence must be 15 s; the old 30 s interval is too slow',
      );
    });

    // GIVEN the RunRecorderService exposes kNotificationChannelImportance
    // WHEN the constant is read
    // THEN it equals "default" (DEFAULT importance prevents heads-up popup on update)
    test('notification channel importance is "default"', () {
      expect(
        RunRecorderService.kNotificationChannelImportance,
        equals('default'),
        reason: 'DEFAULT importance prevents the heads-up popup from interrupting gameplay on every tick update',
      );
    });

    // GIVEN RunRecorderService declares all three constants as static members
    // WHEN the constants are accessed via the class name
    // THEN they are all non-null (compile-level seam: undefined if not added)
    test('all three constants are accessible on RunRecorderService', () {
      // If any constant is missing the test file itself fails to compile.
      expect(RunRecorderService.kNotificationTitle, isNotNull);
      expect(RunRecorderService.kForegroundTaskInterval, isNotNull);
      expect(RunRecorderService.kNotificationChannelImportance, isNotNull);
    });
  });
}
