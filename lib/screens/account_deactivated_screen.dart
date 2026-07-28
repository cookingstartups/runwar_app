import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show accountDeactivationProvider;
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/valencia_button.dart';

/// Gate 0.5's destination screen (main.dart's _RouteGuard): shown instead of
/// the normal app shell while a pending account_deletion_requests row exists
/// for the current user. Offers a working reactivation path (R7-AC2) that
/// invalidates accountDeactivationProvider so the gate re-evaluates
/// immediately and the user reaches the normal app on next entry.
class AccountDeactivatedScreen extends ConsumerStatefulWidget {
  const AccountDeactivatedScreen({required this.scheduledDeletionAt, super.key});
  final DateTime scheduledDeletionAt;

  @override
  ConsumerState<AccountDeactivatedScreen> createState() =>
      _AccountDeactivatedScreenState();
}

class _AccountDeactivatedScreenState
    extends ConsumerState<AccountDeactivatedScreen> {
  bool _reactivating = false;

  Future<void> _reactivate() async {
    setState(() => _reactivating = true);
    try {
      await Supabase.instance.client.rpc('reactivate_account');
      final userId = ref.read(authProvider).user?['id'] as String?;
      if (userId != null) {
        // Gate 0.5 must re-evaluate immediately after reactivation so the
        // user reaches the normal app on next entry.
        ref.invalidate(accountDeactivationProvider(userId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kDanger),
        );
      }
    } finally {
      if (mounted) setState(() => _reactivating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.yMMMMd().format(widget.scheduledDeletionAt);

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'YOUR ACCOUNT\nIS DEACTIVATED.',
                style: GoogleFonts.bebasNeue(
                  fontSize: 48,
                  height: 0.95,
                  color: kFg,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your account is scheduled for deletion on $dateLabel. '
                'Reactivate any time before then to keep your territory, '
                'credits, and connections.',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.55,
                  color: kFgMuted,
                ),
              ),
              const Spacer(),
              ValenciaButton(
                label: 'REACTIVATE MY ACCOUNT',
                onPressed: _reactivate,
                loading: _reactivating,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
