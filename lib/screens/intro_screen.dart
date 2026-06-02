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

// ---------------------------------------------------------------------------
// Slide data
// ---------------------------------------------------------------------------
class _Slide {
  final String tag;
  final String headline;
  final String body;
  final String hint;
  final Color tagColor;
  final String asset; // path under assets/

  const _Slide({
    required this.tag,
    required this.headline,
    required this.body,
    required this.asset,
    this.hint = '',
    this.tagColor = kAccent,
  });
}

const _slides = [
  _Slide(
    tag: 'GPS TERRITORY',
    tagColor: kAccent,
    headline: 'Claim\nReal Streets',
    body: 'Run GPS-tracked routes to capture territory in your city.\nEvery block you conquer is yours — until someone takes it.',
    asset: 'assets/screenshots/run_claim.gif',
  ),
  _Slide(
    tag: 'ECONOMY & POWERS',
    tagColor: kSea,
    headline: 'Every\nRun Pays',
    body: 'Earn credits on each run. Claim drops, unlock superpowers,\nand defend your ground against rivals.',
    asset: 'assets/screenshots/run_city.gif',
  ),
  _Slide(
    tag: 'TRUST LAYER',
    tagColor: kAccent2,
    headline: 'Earn\nYour Spot',
    body: 'Invitation-only. Reputation-based.\nYour every move is GPS-verified — no fakes.',
    asset: 'assets/screenshots/run_defend.gif',
    hint: 'Leagues, clans & city wars — coming soon',
  ),
];

// ---------------------------------------------------------------------------
// IntroScreen
// ---------------------------------------------------------------------------
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
    final bottom = MediaQuery.of(context).padding.bottom;
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          // ── Skip row ──────────────────────────────────────────────────────
          SizedBox(height: top + 8),
          SizedBox(
            height: 36,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: AnimatedOpacity(
                  opacity: _page < _slides.length - 1 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    onPressed: _page < _slides.length - 1 ? _done : null,
                    child: Text('SKIP', style: monoStyle(size: 10, color: kFgFaint)),
                  ),
                ),
              ),
            ),
          ),

          // ── Slide pages ───────────────────────────────────────────────────
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _slides.length,
              itemBuilder: (_, i) => _SlidePage(slide: _slides[i]),
            ),
          ),

          // ── Dots + CTA ───────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, bottom + 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide page — GIF panel + copy
// ---------------------------------------------------------------------------
class _SlidePage extends StatelessWidget {
  final _Slide slide;
  const _SlidePage({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── GIF preview panel ─────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: slide.tagColor.withValues(alpha: 0.25),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  color: kSurface,
                ),
                child: Image.asset(
                  slide.asset,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  width: double.infinity,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ── Text content ──────────────────────────────────────────────────
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: slide.tagColor.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(4),
                    color: slide.tagColor.withValues(alpha: 0.08),
                  ),
                  child: Text(slide.tag, style: monoStyle(size: 9, color: slide.tagColor)),
                ),
                const SizedBox(height: 14),

                // Headline — sized down from 64 to fit reliably
                Text(
                  slide.headline.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bebasNeue(
                    fontSize: 52,
                    height: 1.0,
                    color: kFg,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),

                // Body
                Text(
                  slide.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle(size: 13, color: kFgMuted),
                ),

                // Coming-soon hint
                if (slide.hint.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kAccent2.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text('COMING SOON', style: monoStyle(size: 8, color: kAccent2)),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          slide.hint,
                          style: monoStyle(size: 9, color: kFgMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
