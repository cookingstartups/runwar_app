import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
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
// Layout modes
// ---------------------------------------------------------------------------
enum _Layout {
  fullBleed,          // Lottie fills screen, text overlays with scrim — slide 1
  textTopVisualBottom, // Text flex 4 / Lottie panel flex 5 — slides 2-4
  centeredClose,      // Pure dark, centered typography, no Lottie — slide 5
}

// ---------------------------------------------------------------------------
// Slide data
// ---------------------------------------------------------------------------
class _Slide {
  final String tag;
  final String headline;
  final String body;
  final Color tagColor;
  final String? lottie;
  final _Layout layout;

  const _Slide({
    required this.tag,
    required this.headline,
    required this.body,
    required this.layout,
    this.tagColor = kAccent,
    this.lottie,
  });
}

const _slides = [
  // 1 — Identity
  _Slide(
    tag: 'YOUR TURF',
    tagColor: kAccent,
    headline: 'YOUR CITY IS\nYOUR BATTLEGROUND.',
    body: 'Every street is contested. Every block is up for grabs.\nRun it. Own it. Stop — lose it.',
    lottie: 'assets/lottie/pulse.json',
    layout: _Layout.fullBleed,
  ),
  // 2 — Stakes
  _Slide(
    tag: 'THE RULES',
    tagColor: kSea,
    headline: 'RUN IT. OWN IT.\nSTOP. LOSE IT.',
    body: 'The map rewards presence, not history.\nIf you didn\'t earn it on foot, you don\'t keep it.',
    lottie: 'assets/lottie/hex_capture.json',
    layout: _Layout.textTopVisualBottom,
  ),
  // 3 — Live city / social (Pablo's #1 hook)
  _Slide(
    tag: 'LIVE CITY',
    tagColor: kAccent,
    headline: 'YOUR RIVALS ARE\nALREADY RUNNING.',
    body: 'See other runners on the map. In real time. In your city.\nEvery block you see belongs to someone.',
    lottie: 'assets/lottie/rivals.json',
    layout: _Layout.textTopVisualBottom,
  ),
  // 4 — Daily CTF + GPS drops (Pablo confirmed IN MVP)
  _Slide(
    tag: 'DAILY DROPS',
    tagColor: kAccent2,
    headline: 'A FLAG JUST\nDROPPED.',
    body: 'Real GPS locations. Real urgency. First runner to arrive wins.\nMap drops and powers hidden across your city.',
    lottie: 'assets/lottie/ctf_drop.json',
    layout: _Layout.textTopVisualBottom,
  ),
  // 5 — Invite close
  _Slide(
    tag: 'INVITE ONLY',
    tagColor: kAccent,
    headline: 'NOT BY LUCK.\nBY HUNGER.',
    body: 'The runners who feel it most get in first.\nYour city is waiting.',
    lottie: null,
    layout: _Layout.centeredClose,
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
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _done();
    }
  }

  void _prev() {
    if (_page > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
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
    final isClose = _slides[_page].layout == _Layout.centeredClose;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // PageView fills screen — horizontal swipe: left = next, right = back.
          PageView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _slides.length,
            itemBuilder: (_, i) => _SlidePage(slide: _slides[i]),
          ),

          // Skip row — floats above PageView
          Positioned(
            top: top + 8,
            right: 20,
            child: SizedBox(
              height: 36,
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

          // Dots + CTA — floats at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
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
                      style: isClose
                          ? ElevatedButton.styleFrom(
                              backgroundColor: kAccent,
                              foregroundColor: kBg,
                            )
                          : null,
                      child: Text(
                        _page < _slides.length - 1 ? 'NEXT →' : 'JOIN THE WAR →',
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
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide page — dispatches to layout variant
// ---------------------------------------------------------------------------
class _SlidePage extends StatelessWidget {
  final _Slide slide;
  const _SlidePage({required this.slide});

  @override
  Widget build(BuildContext context) {
    switch (slide.layout) {
      case _Layout.fullBleed:
        return _FullBleedSlide(slide: slide);
      case _Layout.textTopVisualBottom:
        return _TextTopSlide(slide: slide);
      case _Layout.centeredClose:
        return _CenteredCloseSlide(slide: slide);
    }
  }
}

// ---------------------------------------------------------------------------
// Layout A — Full bleed (slide 1: identity)
// Lottie fills screen, scrim darkens bottom, text overlays center-left
// ---------------------------------------------------------------------------
class _FullBleedSlide extends StatelessWidget {
  final _Slide slide;
  const _FullBleedSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Lottie full-bleed background
        if (slide.lottie != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: Lottie.asset(
                slide.lottie!,
                repeat: true,
                fit: BoxFit.cover,
                delegates: LottieDelegates(
                  values: [
                    ValueDelegate.colorFilter(
                      const ['**'],
                      value: ColorFilter.mode(slide.tagColor, BlendMode.srcIn),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Bottom scrim — keeps CTA area readable
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.35, 0.65, 1.0],
                colors: [
                  kBg.withValues(alpha: 0.1),
                  kBg.withValues(alpha: 0.3),
                  kBg.withValues(alpha: 0.75),
                  kBg.withValues(alpha: 0.97),
                ],
              ),
            ),
          ),
        ),

        // Text — positioned center-left, above scrim
        Positioned(
          top: top + 60,
          left: 28,
          right: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TagChip(slide: slide),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: Text(
                  slide.headline,
                  style: GoogleFonts.bebasNeue(
                    fontSize: 58,
                    height: 1.0,
                    color: kFg,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                slide.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: bodyStyle(size: 14, color: kFgMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Layout B — Text top / Lottie panel bottom (slides 2-4)
// ---------------------------------------------------------------------------
class _TextTopSlide extends StatelessWidget {
  final _Slide slide;
  const _TextTopSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    // Reserve space for floating skip row (36px) + top padding
    final top = MediaQuery.of(context).padding.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: top + 52),

        // Text
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TagChip(slide: slide),
                const SizedBox(height: 14),
                Text(
                  slide.headline,
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
                Text(
                  slide.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle(size: 13, color: kFgMuted),
                ),
              ],
            ),
          ),
        ),

        // Lottie panel
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 80),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kBorder.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(16),
                  color: kSurface,
                  boxShadow: [
                    BoxShadow(
                      color: kBg.withValues(alpha: 0.4),
                      blurRadius: 24,
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: slide.lottie != null
                    ? Lottie.asset(
                        slide.lottie!,
                        repeat: true,
                        fit: BoxFit.contain,
                        delegates: LottieDelegates(
                          values: [
                            ValueDelegate.colorFilter(
                              const ['**'],
                              value: ColorFilter.mode(slide.tagColor, BlendMode.srcIn),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Layout C — Centered close (slide 5: invite only)
// Pure dark screen, centered typography, no animation — silence = pressure
// ---------------------------------------------------------------------------
class _CenteredCloseSlide extends StatelessWidget {
  final _Slide slide;
  const _CenteredCloseSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 140),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _TagChip(slide: slide, centered: true),
          const SizedBox(height: 24),
          Text(
            slide.headline,
            textAlign: TextAlign.center,
            style: GoogleFonts.bebasNeue(
              fontSize: 62,
              height: 1.0,
              color: kFg,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(size: 15, color: kFgMuted),
          ),
          const SizedBox(height: 36),
          // Scarcity signal
          Text(
            'EARLY ACCESS · INVITE ONLY',
            style: monoStyle(size: 9, color: kAccent2),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared tag chip
// ---------------------------------------------------------------------------
class _TagChip extends StatelessWidget {
  final _Slide slide;
  final bool centered;
  const _TagChip({required this.slide, this.centered = false});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: slide.tagColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
        color: slide.tagColor.withValues(alpha: 0.08),
      ),
      child: Text(slide.tag, style: monoStyle(size: 9, color: slide.tagColor)),
    );
    return centered ? Center(child: chip) : chip;
  }
}
