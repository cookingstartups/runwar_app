import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

const _kShowcaseKey = 'showcase_seen';

Future<void> markShowcaseSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kShowcaseKey, true);
}

Future<bool> isShowcaseSeen() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kShowcaseKey) ?? false;
}

class _Slide {
  final String tag;
  final String headline;
  final String body;
  final String hint; // teaser / coming-soon line — empty if none
  final Color tagColor;
  const _Slide({
    required this.tag,
    required this.headline,
    required this.body,
    this.hint = '',
    this.tagColor = kAccent,
  });
}

const _slides = [
  _Slide(
    tag: 'GPS TERRITORY',
    tagColor: kAccent,
    headline: 'Claim\nReal Streets',
    body:
        'Run GPS-tracked routes to capture territory in your city. Every block, every zone — conquer it on foot.',
  ),
  _Slide(
    tag: 'ECONOMY & POWERS',
    tagColor: kSea,
    headline: 'Every\nRun Pays',
    body:
        'Earn credits on each run. Claim drops, unlock superpowers, and defend your ground against rivals.',
  ),
  _Slide(
    tag: 'TRUST LAYER',
    tagColor: kAccent2,
    headline: 'Earn\nYour Spot',
    body:
        'Invitation-only. Reputation-based. Your every move is GPS-verified — no fakes tolerated.',
    hint: 'Leagues, clans & city wars — coming soon',
  ),
];

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _controller = PageController();
  int _page = 0;

  Future<void> _done() async {
    await markShowcaseSeen();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/request-access');
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _done();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _slides.length,
            itemBuilder: (_, i) => _SlidePage(slide: _slides[i]),
          ),

          // Skip button (hidden on last slide)
          if (_page < _slides.length - 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 24,
              child: TextButton(
                onPressed: _done,
                child: Text(
                  'SKIP',
                  style: monoStyle(size: 10, color: kFgFaint),
                ),
              ),
            ),

          // Dots + CTA
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 40,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _page ? kAccent : kFgFaint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _next,
                  child: Text(
                    _page < _slides.length - 1 ? 'NEXT →' : 'GET STARTED →',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                      color: kBg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlidePage extends StatelessWidget {
  final _Slide slide;
  const _SlidePage({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feature tag chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: slide.tagColor.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(4),
              color: slide.tagColor.withValues(alpha: 0.08),
            ),
            child: Text(
              slide.tag,
              style: monoStyle(size: 9, color: slide.tagColor),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            slide.headline.toUpperCase(),
            style: GoogleFonts.bebasNeue(
              fontSize: 64,
              height: 1.0,
              color: kFg,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 20),
          Text(slide.body, style: bodyStyle(size: 15, color: kFgMuted)),
          if (slide.hint.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: kFgFaint.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kAccent2.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      'COMING SOON',
                      style: monoStyle(size: 8, color: kAccent2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    slide.hint,
                    style: monoStyle(size: 9, color: kFgMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
