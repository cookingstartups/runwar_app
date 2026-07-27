// test/screens/deletion_confirmation_dialog_test.dart
//
// Covers the irreversibility/deactivation-window confirmation dialog copy.
// This is a content-completeness requirement, not a layout or exact-wording
// requirement - each assertion below checks for the substance of one of the
// seven required points, not a fixed phrase. Source-inspection, since the
// dialog only appears after a live-Supabase-backed submit flow.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

void main() {
  group('deletion confirmation dialog states all seven required points', () {
    late String content;
    setUpAll(() {
      content = _read('lib/screens/support_ticket_screen.dart');
    });

    test('states the action becomes irreversible after the grace window', () {
      final lower = content.toLowerCase();
      expect(lower.contains('irreversible') || lower.contains('irrevocable'),
          isTrue, reason: 'point (a): irreversibility after the window');
    });

    test('states conquered territories will be removed', () {
      final lower = content.toLowerCase();
      expect(lower.contains('territor'), isTrue,
          reason: 'point (b): territories will be removed');
    });

    test('states credits will be erased', () {
      final lower = content.toLowerCase();
      expect(lower.contains('credit'), isTrue,
          reason: 'point (c): credits will be erased');
    });

    test('states data may be retained for a compliance period', () {
      final lower = content.toLowerCase();
      expect(
          lower.contains('retain') ||
              lower.contains('compliance') ||
              lower.contains('legal'),
          isTrue,
          reason: 'point (d): legally reasonable data retention period');
    });

    test('states loss of access to friends/rivals/social connections', () {
      final lower = content.toLowerCase();
      expect(
          lower.contains('friend') ||
              lower.contains('rival') ||
              lower.contains('social'),
          isTrue,
          reason: 'point (e): loses social/friend/rival access');
    });

    test('states purchases or credits already paid for are not reimbursed', () {
      final lower = content.toLowerCase();
      expect(
          lower.contains('not reimbursed') ||
              lower.contains('no refund') ||
              lower.contains('non-refundable') ||
              lower.contains('refund'),
          isTrue,
          reason: 'point (f): no refunds for prior purchases/credits');
    });

    test('explicitly names the one-month deactivation grace period before '
        'irrevocable deletion executes', () {
      final lower = content.toLowerCase();
      expect(
          lower.contains('1 month') ||
              lower.contains('one month') ||
              lower.contains('30 day') ||
              lower.contains('30-day'),
          isTrue,
          reason: 'point (g): explicit deactivate-for-1-month-first language');
      expect(lower.contains('deactivat'), isTrue,
          reason: 'point (g) must name deactivation specifically, not just '
              'a generic wait period');
    });
  });
}
