import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/cities_provider.dart';
import '../providers/profile_provider.dart';
import '../utils/string_utils.dart';
import '../services/zones_service.dart';
import '../theme.dart';
import '../widgets/reputation_badge.dart';
import '../widgets/valencia_button.dart';
import 'profile_edit_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth.user?['id'] as String?;

    if (userId == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final profileAsync = ref.watch(profileGateProvider(userId));
    final reputationAsync = ref.watch(reputationProvider(userId));
    final referralCodeAsync = ref.watch(referralCodeProvider(userId));

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text('PROFILE', style: displayStyle(size: 20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProfileEditScreen(),
              ),
            ),
            child: Text('Edit', style: bodyStyle(size: 14, color: kAccent)),
          ),
        ],
      ),
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
            final citySlug = ref
                    .watch(joinedCitySlugsProvider(userId))
                    .valueOrNull
                    ?.firstOrNull ??
                '';
            final city = capitalize(citySlug);
            final colorHex = (p['color'] as String?) ?? '#FF7A00';

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text(username.toUpperCase(), style: displayStyle(size: 36)),
                  if (city.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(city, style: bodyStyle(size: 16)),
                  ],
                  const SizedBox(height: 24),
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
                  Builder(builder: (_) {
                    final bio = (p['bio'] as String?) ?? '';
                    if (bio.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bio, style: bodyStyle(size: 14)),
                        const SizedBox(height: 8),
                      ],
                    );
                  }),
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
                  const SizedBox(height: 32),
                  _ReferralSection(codeAsync: referralCodeAsync),
                  const SizedBox(height: 32),
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

class _ReferralSection extends StatefulWidget {
  const _ReferralSection({required this.codeAsync});
  final AsyncValue<String?> codeAsync;

  @override
  State<_ReferralSection> createState() => _ReferralSectionState();
}

class _ReferralSectionState extends State<_ReferralSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Make your friends your allies to Earn rewards.',
                    style: monoStyle(size: 11, color: kFg),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: kFgMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildCard(context),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    return widget.codeAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: SizedBox(
            width: 16,
            height: 16,
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
                borderRadius: BorderRadius.circular(12),
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
          : Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR REFERRAL CODE',
                    style: monoStyle(size: 10, color: kFgMuted),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: kAccent.withValues(alpha: 0.3),
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                      color: kBg,
                    ),
                    child: Text(
                      code,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: kFg,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ValenciaButton(
                          label: 'COPY',
                          variant: ValenciaButtonVariant.ghost,
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Code copied!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ValenciaButton(
                          label: 'SHARE',
                          onPressed: () {
                            SharePlus.instance.share(
                              ShareParams(
                                text:
                                    'Join me in RunWar — the mobile game where runners claim real streets. '
                                    'Use my code $code — we both win lifetime rewards. '
                                    'https://runwar.gg',
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'LIFETIME 20% KICKBACK · YOU + EVERY RUNNER YOU INVITE',
                      style: monoStyle(size: 9, color: kFgMuted),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

Color _hexToColor(String hex) {
  try {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return kAccent;
  }
}
