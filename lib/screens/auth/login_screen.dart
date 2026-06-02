import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/grain_overlay.dart';
import '../../widgets/valencia_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).signInWithGoogle();
      // _RouteGuard re-evaluates automatically — no navigation needed here
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e'), backgroundColor: kDanger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
        parent: _fadeCtrl, curve: const Cubic(0.22, 1, 0.36, 1));
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred Valencia photo background
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Opacity(
              opacity: 0.55,
              child: Image.asset(
                'assets/cities/valencia.jpg',
                fit: BoxFit.cover,
                width: size.width,
                height: size.height,
              ),
            ),
          ),
          // Scrim: opaque left, fades right
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.55, 1.0],
                  colors: [
                    kBg,
                    kBg.withValues(alpha: 0.85),
                    kBg.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: FadeTransition(
              opacity: fade,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RUNWAR · 2026',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 3.0,
                        color: kFgMuted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'EARLY ACCESS',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 3.0,
                        color: kAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Claim your\ncity.',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: kFg,
                        height: 0.98,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'A mobile game for runners. Claim real streets.\nGPS-tracked. No fakes.',
                      style: GoogleFonts.inter(fontSize: 15, color: kFgMuted, height: 1.5),
                    ),
                    const SizedBox(height: 40),
                    ValenciaButton(
                      label: 'CONTINUE WITH GOOGLE',
                      onPressed: _signInWithGoogle,
                      loading: _loading,
                      icon: const Icon(Icons.g_mobiledata, size: 22),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          const GrainOverlay(),
        ],
      ),
    );
  }
}
