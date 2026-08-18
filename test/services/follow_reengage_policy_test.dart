// test/services/follow_reengage_policy_test.dart
//
// Pure behavioral tests for the run-session camera follow re-engage
// predicate. Elapsed time is inclusive at the 5-minute threshold; distance
// is exclusive at the 100-metre threshold - both boundaries locked and
// asserted here explicitly.

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/follow_reengage_policy.dart';

void main() {
  group('shouldReengageFollow: both conditions met', () {
    test('elapsed well past 5 minutes and distance well past 100 m re-engages', () {
      final result = shouldReengageFollow(
        elapsed: const Duration(minutes: 30),
        distanceMeters: 1000,
      );
      expect(result, isTrue);
    });
  });

  group('shouldReengageFollow: only time condition met', () {
    test('elapsed past 5 minutes but distance short of 100 m does not re-engage', () {
      final result = shouldReengageFollow(
        elapsed: const Duration(minutes: 10),
        distanceMeters: 40,
      );
      expect(result, isFalse);
    });
  });

  group('shouldReengageFollow: only distance condition met', () {
    test('distance past 100 m but elapsed short of 5 minutes does not re-engage', () {
      final result = shouldReengageFollow(
        elapsed: const Duration(minutes: 4, seconds: 59),
        distanceMeters: 500,
      );
      expect(result, isFalse);
    });
  });

  group('shouldReengageFollow: neither condition met', () {
    test('short elapsed and short distance does not re-engage', () {
      final result = shouldReengageFollow(
        elapsed: const Duration(minutes: 1),
        distanceMeters: 10,
      );
      expect(result, isFalse);
    });
  });

  group('shouldReengageFollow: boundary values', () {
    test('exactly 5 minutes elapsed and exactly 100 m distance does not re-engage (distance exclusive)', () {
      final result = shouldReengageFollow(
        elapsed: const Duration(minutes: 5),
        distanceMeters: 100,
      );
      expect(result, isFalse,
          reason: 'distance threshold is exclusive - exactly 100 m must not satisfy the distance condition');
    });

    test('exactly 5 minutes elapsed and just over 100 m distance re-engages (time inclusive, distance satisfied)', () {
      final result = shouldReengageFollow(
        elapsed: const Duration(minutes: 5),
        distanceMeters: 100.01,
      );
      expect(result, isTrue,
          reason: 'time threshold is inclusive - exactly 5 minutes satisfies the time condition on its own');
    });

    test('one second short of 5 minutes with distance well past 100 m does not re-engage (time exclusive below threshold)', () {
      final result = shouldReengageFollow(
        elapsed: const Duration(minutes: 4, seconds: 59),
        distanceMeters: 1000,
      );
      expect(result, isFalse,
          reason: 'elapsed just under 5 minutes must not satisfy the time condition');
    });
  });
}
