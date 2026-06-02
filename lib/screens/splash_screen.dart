import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/grain_overlay.dart';
import '../widgets/pulse_dot.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.showStatus = false, this.statusLabel = ''});
  final bool showStatus;
  final String statusLabel;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _slideCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _fadeCtrl.forward();
        _slideCtrl.forward();
      }
    });

    // Auto-advance after 2800ms only when NOT used as the loading gate
    if (!widget.showStatus) {
      Future.delayed(const Duration(milliseconds: 2800), () {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/intro');
        }
      });
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final fade = CurvedAnimation(parent: _fadeCtrl, curve: const Cubic(0.22, 1, 0.36, 1));
    final slide = CurvedAnimation(parent: _slideCtrl, curve: const Cubic(0.22, 1, 0.36, 1));

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Valencia map — real CartoDB dark tiles, JPEG for full color depth
          Positioned.fill(
            child: Image.asset(
              'assets/maps/valencia_map.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Layer 2: Radial orange glow
          Positioned(
            left: size.width * 0.5 - 300,
            top: size.height * 0.65 - 300,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kAccent.withValues(alpha: 0.18),
                    kAccent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // Layer 3: Bottom scrim — top stays fully open so map reads clearly
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.40, 0.75, 1.0],
                  colors: [
                    kBg.withValues(alpha: 0.0),
                    kBg.withValues(alpha: 0.05),
                    kBg.withValues(alpha: 0.70),
                    kBg.withValues(alpha: 0.94),
                  ],
                ),
              ),
            ),
          ),
          // Layer 4: Center content
          SafeArea(
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(slide),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'EARLY ACCESS FOR COMMITTED RUNNERS ONLY',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 4.0,
                        color: kAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width - 48,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: kGradientGold,
                          ).createShader(bounds),
                          child: Text(
                            'RUNWAR',
                            softWrap: false,
                            maxLines: 1,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 96,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 0.95,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(width: 80, height: 1, color: kBorder),
                    const SizedBox(height: 16),
                    Text(
                      'The game where runners claim real streets.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: kFgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Layer 6: Status label at bottom (only when used as gate)
          if (widget.showStatus && widget.statusLabel.isNotEmpty)
            Positioned(
              bottom: 32 + MediaQuery.paddingOf(context).bottom,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: fade,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PulseDot(color: kAccent, size: 6),
                    const SizedBox(width: 8),
                    Text(
                      widget.statusLabel,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 3.0,
                        color: kFgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Layer 7: Grain overlay
          const GrainOverlay(),
        ],
      ),
    );
  }
}

