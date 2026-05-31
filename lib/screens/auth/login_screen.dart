import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import 'invitation_code_screen.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  Future<void> _signInWithGoogle(BuildContext context, WidgetRef ref) async {
    await ref.read(authProvider.notifier).signInWithGoogle();
    if (!context.mounted) return;
    final state = ref.read(authProvider);
    final user = state.user;
    if (user != null && user['invited_at'] == null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvitationCodeScreen(userId: user['id'] as String),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authProvider);
    final loading = state.isLoading;
    final errorText = state.error;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Animated GIF background (hero map spoiler) ──────────────────
          Positioned.fill(
            child: Image.asset(
              'assets/animations/hero.gif',
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          // ── Dark gradient — keeps text legible over the animation ───────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    kBg.withValues(alpha: 0.55),
                    kBg.withValues(alpha: 0.75),
                    kBg.withValues(alpha: 0.97),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // ── Foreground content ───────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Text('RUNWAR', style: displayStyle(size: 52)),
                  const SizedBox(height: 8),
                  Text(
                    'Claim the streets. Run your city.',
                    style: bodyStyle(size: 14, color: kFgMuted),
                  ),
                  const Spacer(),
                  if (errorText != null) ...[
                    Text(
                      errorText,
                      style: bodyStyle(size: 13, color: kDanger),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  OutlinedButton.icon(
                    onPressed: loading
                        ? null
                        : () => _signInWithGoogle(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kFg,
                      side: const BorderSide(color: kBorder),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: bodyStyle(size: 14, color: kFg).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kFg,
                            ),
                          )
                        : const Icon(Icons.g_mobiledata, size: 26, color: kFg),
                    label: const Text('Continue with Google'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
