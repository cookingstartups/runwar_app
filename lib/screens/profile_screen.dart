import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../services/zones_service.dart';
import '../theme.dart';
import '../widgets/reputation_badge.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth.user?['id'] as String?;

    // Defensive: route guard normally prevents reaching here without a user.
    if (userId == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final profileAsync = ref.watch(profileGateProvider(userId));
    final reputationAsync = ref.watch(reputationProvider(userId));
    final referralCodeAsync = ref.watch(referralCodeProvider(userId));

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: profileAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load profile: $e',
              style: bodyStyle(size: 14, color: kDanger),
            ),
          ),
          data: (p) {
            if (p == null) return const Center(child: SizedBox.shrink());
            final username = (p['username'] as String?) ?? '';
            final city = (p['city'] as String?) ?? '';
            final colorHex = (p['color'] as String?) ?? '#FF7A00';

            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // AC-9: username
                  Text(username.toUpperCase(), style: displayStyle(size: 36)),
                  const SizedBox(height: 8),
                  // AC-9: city
                  Text(city, style: bodyStyle(size: 16)),
                  const SizedBox(height: 24),
                  // AC-9: color swatch — filled circle 32×32
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _hexToColor(colorHex),
                          shape: BoxShape.circle,
                          border: Border.all(color: kBorder, width: 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        colorHex,
                        style: monoStyle(size: 12, color: kFgMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Invite / referral code
                  _InviteCodeSection(
                    codeAsync: referralCodeAsync,
                    onCopy: (code) {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Invite code copied: $code',
                            style: monoStyle(size: 12),
                          ),
                          backgroundColor: kSurface,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // P3: Reputation badge
                  reputationAsync.maybeWhen(
                    data: (rep) => Row(
                      children: [
                        Text('REPUTATION', style: monoStyle()),
                        const SizedBox(width: 12),
                        ReputationBadge(score: rep),
                      ],
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  // AC-10: zones-owned count — static snapshot at mount.
                  // Sourced exclusively from ZonesService (AC-10 invariant).
                  FutureBuilder<int>(
                    future: ZonesService.instance.countOwnedByUser(userId),
                    builder: (context, snap) {
                      final n = snap.data ?? 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ZONES OWNED', style: monoStyle()),
                          const SizedBox(height: 4),
                          Text(
                            '$n',
                            style: displayStyle(size: 48, color: kAccent),
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  // AC-11: log out button
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(authProvider.notifier).signOut(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: Text(
                      'LOG OUT',
                      style: bodyStyle(size: 12, color: kFg),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Displays the player's referral/invite code with a copy action.
///
/// Shows a locked state if the code is null (player not yet eligible to refer).
/// "Limited uses" copy reflects server-side max_redemptions cap.
class _InviteCodeSection extends StatelessWidget {
  const _InviteCodeSection({
    required this.codeAsync,
    required this.onCopy,
  });

  final AsyncValue<String?> codeAsync;
  final void Function(String code) onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('YOUR INVITE CODE', style: monoStyle(size: 10, color: kFgMuted)),
        const SizedBox(height: 8),
        codeAsync.when(
          loading: () => Container(
            height: 52,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: const Center(
              child: SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(color: kAccent, strokeWidth: 1.5),
              ),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (code) => code == null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 14, color: kFgFaint),
                      const SizedBox(width: 10),
                      Text(
                        'Invite others once you join the war.',
                        style: monoStyle(size: 10, color: kFgFaint),
                      ),
                    ],
                  ),
                )
              : GestureDetector(
                  onTap: () => onCopy(code),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            code,
                            style: monoStyle(size: 22, color: kAccent).copyWith(
                              letterSpacing: 4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(Icons.copy_outlined, size: 16, color: kFgMuted),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          'Share to invite runners into the war · limited uses',
          style: monoStyle(size: 9, color: kFgFaint),
        ),
      ],
    );
  }
}

/// Parses '#RRGGBB' or '#AARRGGBB' hex color strings.
/// Returns kAccent on any parse failure.
Color _hexToColor(String hex) {
  try {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return kAccent;
  }
}
