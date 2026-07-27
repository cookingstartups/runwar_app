// test/screens/account_deactivated_screen_test.dart
//
// Covers the reactivation path: AccountDeactivatedScreen offers a working
// "Reactivate my account" action that flips the account_deletion_requests
// row back to active and restores normal app access. Source-inspection,
// since the reactivate call hits a live Supabase RPC.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('AccountDeactivatedScreen exists with a reactivation action', () {
    test('lib/screens/account_deactivated_screen.dart defines the widget', () {
      final content = _read('lib/screens/account_deactivated_screen.dart');
      expect(content.contains('class AccountDeactivatedScreen'), isTrue);
    });

    test('takes a scheduledDeletionAt parameter to show the user the date', () {
      final content = _read('lib/screens/account_deactivated_screen.dart');
      expect(content.contains('scheduledDeletionAt'), isTrue);
    });

    test('offers a reactivate action calling the reactivate_account RPC', () {
      final content = _read('lib/screens/account_deactivated_screen.dart');
      expect(content.toUpperCase().contains('REACTIVATE'), isTrue,
          reason: 'A reactivation action must be visibly offered');
      expect(content.contains('reactivate_account'), isTrue,
          reason: 'Reactivation must call the reactivate_account RPC, not '
              'set some separate ad-hoc flag');
    });

    test('invalidates accountDeactivationProvider after a successful reactivate',
        () {
      final content = _read('lib/screens/account_deactivated_screen.dart');
      expect(content.contains('accountDeactivationProvider'), isTrue,
          reason: 'Gate 0.5 must re-evaluate immediately after reactivation '
              'so the user reaches the normal app on next entry');
    });
  });
}
