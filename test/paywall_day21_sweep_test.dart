// test/paywall_day21_sweep_test.dart
//
// Grep-based regression locks for the day-14 -> day-21 paywall retarget
// (paywall-day21-revision). These verify the stale "14"/"Day 30 unaffected"
// literals are gone from the specific locations that carry them, and that
// the shared kFirstThirtyDaysCapstoneDay constant exists and backs both
// consuming services. Source-level checks (not widget tests) mirror the
// convention already used in test/main/route_guard_test.dart's AC-3/AC-11
// checks for files that are awkward or heavy to exercise as widgets.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('shared capstone-day constant', () {
    test('kFirstThirtyDaysCapstoneDay is defined in runwar_constants.dart', () {
      final content = _read('lib/utils/runwar_constants.dart');
      expect(content.contains('kFirstThirtyDaysCapstoneDay'), isTrue,
          reason: 'the shared constant must live in the zero-dependency '
              'leaf constants file so both services can import it without '
              'a cycle');
    });

    test('kBetaTesterEmails doc comment no longer references the 14-day '
        'trial paywall gate', () {
      final content = _read('lib/utils/runwar_constants.dart');
      expect(content.contains('14-day trial paywall gate'), isFalse,
          reason: 'this stale reference was found during the Architect '
              'review and added to the R7 sweep scope');
    });
  });

  group('milestone_reward_modal.dart sweep', () {
    test('no longer gates the paywall section on day == 14', () {
      final content = _read('lib/widgets/milestone_reward_modal.dart');
      expect(content.contains('widget.day == 14'), isFalse,
          reason: 'the paywall-day literal must move to 21 (or the shared '
              'constant)');
    });

    test('the paywall section class is no longer named for day 14', () {
      final content = _read('lib/widgets/milestone_reward_modal.dart');
      expect(content.contains('_Day14PaywallSection'), isFalse,
          reason: 'the class name itself encodes the stale day and must be '
              'renamed to reflect day 21');
    });
  });

  group('paywall_screen.dart sweep', () {
    test('no longer claims the trial grants 14 activity credits', () {
      final content = _read('lib/screens/paywall_screen.dart');
      expect(content.contains('Your 14 activity credits'), isFalse,
          reason: 'the trial-length claim in the paywall copy must not '
              'still say 14');
    });
  });

  group('paywall_downsell_screen.dart sweep', () {
    test('doc comment no longer references day-14', () {
      final content = _read('lib/screens/paywall_downsell_screen.dart');
      expect(content.contains('day-14'), isFalse,
          reason: 'doc comment must describe the day-21 framing instead');
    });
  });

  group('trial_service.dart sweep', () {
    test('class doc comment no longer describes a 14-day activity trial', () {
      final content = _read('lib/services/trial_service.dart');
      expect(content.contains('Manages the 14-day activity-based trial'),
          isFalse,
          reason: 'the hard-paywall gate is now calendar-based at day 21; '
              'the doc comment must not still describe a 14-day trial '
              '(the burn/freeze literals themselves stay unchanged per '
              'R1-AC2, only the doctrine-as-code comment moves)');
    });
  });

  group('day30_mission.dart sweep (R6-AC5)', () {
    test('header doc comment no longer states Day 30 is unaffected/outside '
        'the window', () {
      final content = _read('lib/models/day30_mission.dart');
      final hasStaleClaim =
          content.contains('Day 30 (the capstone') &&
              content.contains('is unaffected') &&
              content.contains('outside the 21-day core window');
      expect(
        hasStaleClaim,
        isFalse,
        reason: 'the capstone now unlocks inside the 21-day window at day '
            '21, so the doc comment stating it is unaffected/outside the '
            'window is stale and must be rewritten',
      );
    });
  });

  group('first_thirty_days_missions_service.dart sweep (R6-AC5)', () {
    test('dailyCadenceThroughDay doc comment no longer states Day 30 stays '
        'outside this window', () {
      final content =
          _read('lib/services/first_thirty_days_missions_service.dart');
      expect(
        content.contains('Day 30 (the capstone) stays outside this window'),
        isFalse,
        reason: 'the capstone is now curriculum\'s day-21 entry, included '
            'via dailySeries()\'s ordinary bespoke-day lookup',
      );
    });
  });
}
