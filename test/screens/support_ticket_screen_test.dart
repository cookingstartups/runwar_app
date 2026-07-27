// test/screens/support_ticket_screen_test.dart
//
// Covers the shared SupportTicketScreen serving both plain support tickets
// and account-deletion requests, and its atomic RPC-based submit path
// (matching the SECURITY DEFINER pattern already used by decline_offer,
// not sequential unprotected client REST calls). Source-inspection, since
// the RPC call hits a live Supabase client.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('one shared screen for both ticket kinds', () {
    test('lib/screens/support_ticket_screen.dart exists and defines '
        'SupportTicketScreen with a required kind parameter', () {
      final content = _read('lib/screens/support_ticket_screen.dart');
      expect(content.contains('class SupportTicketScreen'), isTrue);
      expect(content.contains('kind'), isTrue,
          reason: 'A kind parameter must discriminate support vs deletion');
    });

    test('a SupportTicketKind enum defines support and accountDeletion', () {
      final content = _read('lib/screens/support_ticket_screen.dart');
      final hasEnumHere = content.contains('SupportTicketKind');
      final modelFile = File('lib/models/support_ticket.dart');
      final hasEnumInModel =
          modelFile.existsSync() && modelFile.readAsStringSync().contains('SupportTicketKind');
      expect(hasEnumHere || hasEnumInModel, isTrue,
          reason: 'SupportTicketKind must exist, in the screen or the model file');
    });

    test('no separate AccountDeletionRequestScreen exists', () {
      expect(File('lib/screens/account_deletion_request_screen.dart').existsSync(),
          isFalse,
          reason: 'Deletion must route through SupportTicketScreen, not a '
              'dedicated screen (superseded mockup design)');
    });
  });

  group('submit goes through the atomic RPC, not raw table inserts', () {
    test('support_ticket_screen.dart calls the submit_support_ticket RPC', () {
      final content = _read('lib/screens/support_ticket_screen.dart');
      expect(content.contains('submit_support_ticket'), isTrue,
          reason: 'Ticket + deletion-request creation must go through the '
              'SECURITY DEFINER RPC, matching the decline_offer precedent');
    });

    test('support_ticket_screen.dart does not insert directly into '
        'support_tickets via a raw client call', () {
      final content = _read('lib/screens/support_ticket_screen.dart');
      expect(content.contains(".from('support_tickets').insert"), isFalse,
          reason: 'Direct client insert would not be atomic with the '
              'deletion-request row and must not be used');
    });
  });
}
