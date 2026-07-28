import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/support_ticket.dart';
import '../theme.dart';
import '../widgets/valencia_button.dart';

/// Shared screen for both plain support/bug tickets and account-deletion
/// requests (design.md section 3.4) - a single write path through the
/// submit_support_ticket RPC (migration 0068), matching the decline_offer
/// SECURITY DEFINER precedent, never a raw client insert.
class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({required this.kind, super.key});
  final SupportTicketKind kind;

  @override
  ConsumerState<SupportTicketScreen> createState() =>
      _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  late final TextEditingController _subjectCtrl;
  final TextEditingController _bodyCtrl = TextEditingController();
  bool _submitting = false;

  bool get _isDeletion => widget.kind == SupportTicketKind.accountDeletion;

  @override
  void initState() {
    super.initState();
    _subjectCtrl = TextEditingController(
      text: _isDeletion ? 'Account deletion request' : '',
    );
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isDeletion) {
      final confirmed = await _showDeletionConfirmationDialog();
      if (confirmed != true) return;
    }

    setState(() => _submitting = true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      await Supabase.instance.client.rpc('submit_support_ticket', params: {
        'p_kind': widget.kind.rpcValue,
        'p_subject': _subjectCtrl.text,
        'p_body': _bodyCtrl.text,
        'p_app_version': packageInfo.version,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isDeletion
                ? 'Your account has been deactivated. You can reactivate it any time within the next 30 days.'
                : 'Ticket submitted. We will get back to you soon.'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kDanger),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The irreversibility/deactivation-window confirmation dialog (R6-AC1).
  /// States all seven required content points in plain language:
  /// (a) irreversible once the grace window elapses, (b) conquered
  /// territories are removed, (c) credits are erased, (d) data may be
  /// retained for a compliance/legal period, (e) loss of access to
  /// friends/rivals/social connections, (f) purchases/credits already paid
  /// for are not reimbursed (no refund), (g) the account deactivates
  /// immediately but irrevocable deletion does not execute for 1 month.
  Future<bool?> _showDeletionConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete your account?',
          style: GoogleFonts.spaceGrotesk(color: kFg, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Text(
            "We'll first deactivate your account for 1 month before the "
            'deletion becomes irreversible.\n\n'
            "Once that 30-day grace window elapses, this action is "
            'irrevocable and cannot be undone. Here is exactly what happens:\n\n'
            '- All your conquered territories will be removed and released '
            'back into play.\n'
            '- Any remaining credits will be erased.\n'
            '- You will lose access to your friends, rivals, and other social '
            'connections in the game.\n'
            '- Purchases and credits already paid for are not reimbursed - no '
            'refund is issued for prior purchases.\n'
            '- For legal and compliance reasons, some data may be retained '
            'for a limited period after deletion.\n\n'
            'You can reactivate your account at any point during the 1-month '
            'deactivation window before deletion executes.',
            style: bodyStyle(size: 13, color: kFgMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: TextStyle(color: kFgMuted, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'DEACTIVATE MY ACCOUNT',
              style: TextStyle(color: kDanger, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(
          _isDeletion ? 'DELETE ACCOUNT' : 'SUPPORT',
          style: displayStyle(size: 20),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Subject', style: monoStyle(size: 11, color: kFgMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _subjectCtrl,
                readOnly: _isDeletion,
                style: bodyStyle(size: 14, color: kFg),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: kSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kBorder),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Details', style: monoStyle(size: 11, color: kFgMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _bodyCtrl,
                maxLines: 6,
                style: bodyStyle(size: 14, color: kFg),
                decoration: InputDecoration(
                  hintText: _isDeletion
                      ? 'Tell us why you are leaving (optional).'
                      : 'Describe your issue or question.',
                  hintStyle: bodyStyle(size: 13, color: kFgFaint),
                  filled: true,
                  fillColor: kSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kBorder),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ValenciaButton(
                label: _isDeletion ? 'DELETE MY ACCOUNT' : 'SUBMIT TICKET',
                onPressed: _submit,
                loading: _submitting,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
