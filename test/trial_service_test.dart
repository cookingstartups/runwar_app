// test/trial_service_test.dart
//
// Pure unit tests for TrialStatus.isExpired's calendar-based retarget
// (paywall-day21-revision). Constructs TrialStatus directly, matching this
// repo's convention for services that call Supabase.instance.client directly
// (see first_thirty_days_missions_test.dart's header note) -- getStatus()
// itself is not exercised here, only the pure isExpired getter design.md
// Section 13 flags as the highest-value regression lock for this feature.

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/trial_service.dart';

void main() {
  group('TrialStatus.isExpired: calendar-based gate (not activity-burn)', () {
    test('walls a user whose trial started exactly 21 calendar days ago, '
        'regardless of daysRemaining', () {
      final status = TrialStatus(
        started: true,
        daysRemaining: 14,
        streak: 0,
        trialStartedAt: DateTime.now().toUtc().subtract(const Duration(days: 21)),
      );
      expect(status.isExpired, isTrue,
          reason: 'day 21 must wall regardless of the old activity-burn '
              'daysRemaining value');
    });

    test('does not wall a user whose trial started 20 calendar days ago, '
        'even if daysRemaining would already read 0 under the old rule', () {
      final status = TrialStatus(
        started: true,
        daysRemaining: 0,
        streak: 5,
        trialStartedAt: DateTime.now().toUtc().subtract(const Duration(days: 20)),
      );
      expect(status.isExpired, isFalse,
          reason: 'gate must be a pure function of calendar day, never of '
              'daysRemaining');
    });

    test('resurrects a user currently showing as walled under the old rule '
        'but whose calendar age is only 10 days', () {
      final status = TrialStatus(
        started: true,
        daysRemaining: 0,
        streak: 0,
        trialStartedAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
      );
      expect(status.isExpired, isFalse,
          reason: 'full retroactive resurrection: dayIndex 10 < 21 must '
              'un-wall this user using their original trial_started_at');
    });

    test('keeps walling a user whose calendar age is far past 21 days', () {
      final status = TrialStatus(
        started: true,
        daysRemaining: 0,
        streak: 0,
        trialStartedAt: DateTime.now().toUtc().subtract(const Duration(days: 40)),
      );
      expect(status.isExpired, isTrue,
          reason: 'dayIndex 40 >= 21 must remain gated');
    });

    test('does not wall a user whose trial has not started (null start)', () {
      const status = TrialStatus(
        started: true,
        daysRemaining: 0,
        streak: 0,
        trialStartedAt: null,
      );
      expect(status.isExpired, isFalse,
          reason: 'dayIndexFor(null) returns 0, which is below 21');
    });

    test('does not wall a user whose trial has not started at all '
        '(started: false)', () {
      const status = TrialStatus(
        started: false,
        daysRemaining: 14,
        streak: 0,
        trialStartedAt: null,
      );
      expect(status.isExpired, isFalse);
    });
  });
}
