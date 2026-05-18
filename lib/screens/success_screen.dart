import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

class SuccessArgs {
  final String city;
  final String referralCode;
  const SuccessArgs({required this.city, required this.referralCode});
}

class SuccessScreen extends StatefulWidget {
  final SuccessArgs args;
  const SuccessScreen({super.key, required this.args});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _copied = false;

  String get _link => 'https://runwar.app/join?ref=${widget.args.referralCode}';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _link));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _share() {
    Share.share(
      'I just joined RunWar — the territory running game. Invitation only.\n$_link',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Headline
                  Text(
                    'YOU\'RE IN.',
                    style: GoogleFonts.bebasNeue(
                      fontSize: 64,
                      color: kFg,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "We'll reach out when ${widget.args.city} goes live.\nInvite runners to move up the list.",
                    style: bodyStyle(size: 15),
                  ),

                  const SizedBox(height: 40),

                  // Affiliate block
                  Container(
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorder),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR AFFILIATE LINK',
                          style: monoStyle(size: 9, color: kAccent),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Every runner you bring in earns you '
                          '20% lifetime — from all their future payments, forever.',
                          style: bodyStyle(size: 13),
                        ),
                        const SizedBox(height: 16),

                        // Link box
                        Container(
                          decoration: BoxDecoration(
                            color: kAccent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(
                            _link,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              color: kAccent,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _copy,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(
                                  _copied ? 'COPIED ✓' : 'COPY LINK',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2,
                                    color: kBg,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _share,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                  side: const BorderSide(color: kBorder),
                                  foregroundColor: kFgMuted,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'SHARE',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Fine print
                  Center(
                    child: Text(
                      'TELL A RUNNER WHO DESERVES THIS.',
                      style: monoStyle(size: 9),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
