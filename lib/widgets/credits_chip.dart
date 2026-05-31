import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/economy/credits_provider.dart';
import '../theme.dart';

/// Small pill/chip displaying a player's credit balance.
/// Watches [creditsBalanceProvider(playerId)] and rebuilds on changes.
/// Formats values >= 1000 in compact form (e.g. 1200 → "1.2K").
/// Shows a loading indicator while the stream is pending.
class CreditsChip extends ConsumerWidget {
  const CreditsChip({required this.playerId, super.key});

  final String playerId;

  String _format(int n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) {
      final k = n / 1000;
      return '${_trimTrailingZero(k)}K';
    }
    final m = n / 1000000;
    return '${_trimTrailingZero(m)}M';
  }

  String _trimTrailingZero(double d) {
    final s = d.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(creditsBalanceProvider(playerId));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.toll, size: 14, color: kAccent2),
          const SizedBox(width: 5),
          balanceAsync.when(
            loading: () => const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: kAccent2),
            ),
            error: (_, __) => const Text(
              '--',
              style: TextStyle(
                color: kFgMuted,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
            data: (balance) => Text(
              _format(balance),
              style: const TextStyle(
                color: kFg,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
