// lib/screens/referrals_screen.dart
// Phase 3 trust layer — referral kickback history screen.
//
// Shows the player's total kickback earned (live) and a paginated list of
// individual kickback transactions. Uses [totalKickbackProvider] (stream) and
// [kickbackHistoryProvider] (future) from referral_providers.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/trust/referral_providers.dart';
import '../theme.dart';
import '../widgets/kickback_history_tile.dart';

/// Screen displaying a player's referral earnings history.
///
/// Route: pushed as a named route or via [Navigator.push]; no required
/// constructor arguments — player ID is read from [authProvider].
class ReferralsScreen extends ConsumerWidget {
  const ReferralsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final playerId = user['id'] as String;
    final totalAsync = ref.watch(totalKickbackProvider(playerId));
    final historyAsync = ref.watch(kickbackHistoryProvider(playerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral Earnings'),
        actions: [
          totalAsync.when(
            data: (total) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: Text(
                  '+$total cr total',
                  style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: const TextStyle(color: kDanger),
          ),
        ),
        data: (entries) => entries.isEmpty
            ? Center(
                child: Text(
                  'No referral earnings yet.\nShare your invite code to earn!',
                  textAlign: TextAlign.center,
                  style: bodyStyle(),
                ),
              )
            : ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  color: kBorder,
                ),
                itemBuilder: (_, i) => KickbackHistoryTile(entry: entries[i]),
              ),
      ),
    );
  }
}
