import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme.dart';
import '../../data/cities_catalog.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cities_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/grain_overlay.dart';
import '../../widgets/milestone_progress_bar.dart';
import '../../widgets/valencia_button.dart';
import 'invitation_code_screen.dart';

class JoinWarConfirmationScreen extends ConsumerWidget {
  const JoinWarConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authProvider).user?['id'] as String? ?? '';
    final joinedAsync = ref.watch(joinedCitySlugsProvider(userId));
    final citiesAsync = ref.watch(citiesProvider);
    final codeAsync = ref.watch(referralCodeProvider(userId));

    final cities = citiesAsync.value ?? kCitiesCatalog;
    final joinedSlugs = joinedAsync.value ?? [];
    final referralCode = codeAsync.value; // null = not yet eligible to refer
    final joinedCities =
        cities.where((c) => joinedSlugs.contains(c.slug)).toList();
    final firstName = joinedCities.isNotEmpty ? joinedCities.first.name : 'your city';

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero block
                  const MilestoneProgressBar(currentStep: 2),
                  const SizedBox(height: 14),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: kGradientGold,
                    ).createShader(b),
                    child: Text(
                      "You're\nin line.",
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 0.95,
                        letterSpacing: -1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "We'll alert you when $firstName opens for runners.",
                    style: GoogleFonts.inter(
                        fontSize: 14, color: kFgMuted, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  // Waitlist summary card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kBorder),
                    ),
                    child: Column(
                      children: [
                        ...joinedCities.asMap().entries.map((entry) {
                          final i = entry.key;
                          final c = entry.value;
                          final pct = c.totalTarget > 0
                              ? c.joinedCount / c.totalTarget
                              : 0.0;
                          return Padding(
                            padding: EdgeInsets.only(
                                bottom: i < joinedCities.length - 1 ? 16 : 0),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(100),
                                            child: Image.asset(
                                              'assets/cities/${c.slug}.jpg',
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              color: c.isUnlocked ? null : Colors.black.withValues(alpha: 0.45),
                                              colorBlendMode: c.isUnlocked ? null : BlendMode.darken,
                                            ),
                                          ),
                                          if (!c.isUnlocked)
                                            const Center(
                                              child: Icon(Icons.lock_outline, size: 16, color: Colors.white),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(c.name,
                                              style: GoogleFonts.spaceGrotesk(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: c.isUnlocked ? kFg : kFg.withValues(alpha: 0.4))),
                                          Text('${c.flag}  ${c.country}',
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 10,
                                                color: kFgMuted,
                                              )),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      c.isUnlocked ? 'OPEN' : 'SOON',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 9,
                                        letterSpacing: 2,
                                        color: c.isUnlocked
                                            ? kAccent
                                            : kFgMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Stack(children: [
                                  Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: kFg.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: pct.clamp(0.0, 1.0),
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: kAccent.withValues(alpha: 0.7),
                                        borderRadius:
                                            BorderRadius.circular(100),
                                      ),
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '${c.joinedCount} / ${c.totalTarget}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 9,
                                      color: kFgMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Divider with label
                  Row(children: [
                    Expanded(child: Container(height: 1, color: kBorder)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'INVITE ALLIES TO CLAIM IT FASTER',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 2,
                          color: kFgMuted,
                        ),
                      ),
                    ),
                    Expanded(child: Container(height: 1, color: kBorder)),
                  ]),
                  const SizedBox(height: 20),
                  // Referral card — only shown to invited players who redeemed a code
                  if (referralCode != null) ...[
                    Container(
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
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              letterSpacing: 3,
                              color: kFgMuted,
                            ),
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
                                  strokeAlign: BorderSide.strokeAlignOutside),
                              color: kBg,
                            ),
                            child: Text(
                              referralCode,
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
                          Row(children: [
                            Expanded(
                              child: ValenciaButton(
                                label: 'COPY',
                                variant: ValenciaButtonVariant.ghost,
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: referralCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Code copied!'),
                                        duration: Duration(seconds: 2)),
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
                                      text: 'Join me in RunWar — the mobile game where runners claim real streets. '
                                          'Use my code $referralCode — we both win lifetime rewards. '
                                          'https://runwar.gg',
                                    ),
                                  );
                                },
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'LIFETIME 20% KICKBACK · YOU + EVERY RUNNER YOU INVITE',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9,
                                letterSpacing: 2,
                                color: kFgMuted,
                              ),
                            ),
                          ),
                        ],
                    ),
                  ),
                  ],  // end referralCode != null
                  const SizedBox(height: 16),
                  ValenciaButton(
                    label: 'I HAVE AN INVITE CODE',
                    variant: ValenciaButtonVariant.ghost,
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => const InvitationCodeScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const GrainOverlay(),
        ],
      ),
    );
  }
}
