import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import '../providers/showcase_provider.dart';
import '../widgets/intro_map_animations.dart';
import '../widgets/pulse_ring.dart';
import '../widgets/tag_chip.dart';

// ---------------------------------------------------------------------------
// Animation type per slide
// ---------------------------------------------------------------------------
enum _Anim { pulse, hexCapture, rivals, ctfDrop, fortify, defense, defenseA, defenseB, defenseC, physicalEvents, none }

// ---------------------------------------------------------------------------
// Layout modes
// ---------------------------------------------------------------------------
enum _Layout {
  fullBleed,
  textTopVisualBottom,
  visualTopTextBottom,
  centeredClose,
}

// ---------------------------------------------------------------------------
// Slide data
// ---------------------------------------------------------------------------
class _Slide {
  final String tag;
  final String headline;
  final String body;
  final Color tagColor;
  final _Anim anim;
  final _Layout layout;
  final int bodyMaxLines;

  const _Slide({
    required this.tag,
    required this.headline,
    required this.body,
    required this.layout,
    this.tagColor = kAccent,
    this.anim = _Anim.none,
    // ignore: unused_element_parameter
    this.bodyMaxLines = 3,
  });
}

const _slides = [
  // 1 — Provocation
  _Slide(
    tag: 'YOUR TURF',
    tagColor: kAccent,
    headline: 'SOMEONE CAPTURED\nYOUR STREET.',
    body: 'Every block you sweat on belongs to the last runner who looped it. Their name. Your pavement. Take it back — or keep paying rent in shoe rubber.',
    anim: _Anim.pulse,
    layout: _Layout.visualTopTextBottom,
  ),
  // 2 — Comeback
  _Slide(
    tag: 'CLAIM IT',
    tagColor: kSea,
    headline: 'LASSO IT.\nRIP IT BACK.',
    body: 'Draw a loop while you run. Every meter you close is a meter you steal. Chip away at the giants — one block today, the whole neighbourhood by Sunday.',
    anim: _Anim.hexCapture,
    layout: _Layout.textTopVisualBottom,
  ),
  // 3 — Shield (Variant A)
  // SHIELD Variant A — winner. B and C archived (classes kept in intro_map_animations.dart).
  _Slide(
    tag: 'SHIELD · VARIANT A',
    tagColor: kAccent,
    headline: 'ACTIVATE.\nDROP THE SHIELD.',
    body: 'Earned on the streets — deployed from your couch. The inventory drop sends your shield flying to any territory you own.',
    anim: _Anim.defenseA,
    layout: _Layout.textTopVisualBottom,
  ),
  // 4 — Mastery / Fortify
  _Slide(
    tag: 'FORTIFY',
    tagColor: kAccent,
    headline: 'RUN IT. OWN IT.\nFORTIFY IT.',
    body: 'Lap your zone again and it levels up — all the way to level 15. The higher the level, the more it costs to take it back. The streets remember who trained hardest.',
    anim: _Anim.fortify,
    layout: _Layout.visualTopTextBottom,
  ),
  // 5 — Superpowers
  _Slide(
    tag: 'EARN YOUR EDGE',
    tagColor: kSea,
    headline: 'EARNED IN STREETS.\nDEPLOYED FROM HOME.',
    body: 'Superpowers can\'t be bought. You earn them by running — then unleash them anywhere in the city without leaving your couch. Pay with kilometres, not cash.',
    anim: _Anim.defense,
    layout: _Layout.textTopVisualBottom,
  ),
  // 6 — Loot drops
  _Slide(
    tag: 'LOOT DROPS',
    tagColor: kAccent2,
    headline: 'FIRST FEET\nTAKE IT ALL.',
    body: 'GPS drops hit the map without warning. Cash, crates, killer gear — pinned to a spot somewhere in your city. One winner: whoever\'s lungs get there first.',
    anim: _Anim.ctfDrop,
    layout: _Layout.visualTopTextBottom,
    bodyMaxLines: 4,
  ),
  // 6 — Special events / CTF
  _Slide(
    tag: 'SPECIAL EVENT',
    tagColor: kAccent,
    headline: 'A FLAG DROPS.\nONE RUNNER WINS.',
    body: 'A daily flag drops somewhere in the city. First feet claim the territory — and the glory.',
    anim: _Anim.rivals,
    layout: _Layout.textTopVisualBottom,
    bodyMaxLines: 4,
  ),
  // 7 — Competitive elimination (spec: earn your seat)
  _Slide(
    tag: 'THE BOTTOM DROPS',
    tagColor: kAccent2,
    headline: 'RUN OR LOSE\nYOUR SEAT.',
    body: 'Every week, the bottom runners get cut. Their zones gone. Their rank gone. The city has no room for passengers. Earn your place or someone else will.',
    anim: _Anim.none,
    layout: _Layout.textTopVisualBottom,
    bodyMaxLines: 4,
  ),
  // 8 — ICP targeting: survival cut mechanic
  _Slide(
    tag: 'SURVIVAL CUT WEEK',
    tagColor: kAccent2,
    headline: 'STAY IN THE TOP 90%.\nOR LOSE EVERYTHING.',
    body: 'From time to time we cut off the bottom 10% of runners — You must earn your seat in this war room.',
    anim: _Anim.rivals,
    layout: _Layout.visualTopTextBottom,
    bodyMaxLines: 4,
  ),
  // 9 — Real-world events
  _Slide(
    tag: 'YEARLY IN-PERSON EVENT',
    tagColor: kAccent2,
    headline: 'THE GAME\nGETS REAL.',
    body: 'Real-world races coming to your city — limited seats, livestreamed, glory on the line.',
    anim: _Anim.physicalEvents,
    layout: _Layout.visualTopTextBottom,
  ),
  // 10 — Invite only
  _Slide(
    tag: 'INVITE ONLY',
    tagColor: kAccent,
    headline: 'THE CITY\'S WAITING.\nMOST WON\'T GET IN.',
    body: 'RunWar isn\'t for joggers. It\'s for the ones who feel it in their chest before the alarm goes off. If that\'s you — knock.',
    anim: _Anim.none,
    layout: _Layout.centeredClose,
  ),
];

// ---------------------------------------------------------------------------
// Shared top-level helper — resolves _Anim enum to its widget
// ---------------------------------------------------------------------------
Widget _buildAnimWidget(_Anim anim, Color accent) => switch (anim) {
      _Anim.pulse          => IntroPulseMap(accent: accent),
      _Anim.hexCapture     => IntroCaptureMap(accent: accent),
      _Anim.rivals         => IntroRivalsMap(accent: accent),
      _Anim.ctfDrop        => IntroFlagDropMap(accent: accent),
      _Anim.fortify        => IntroFortifyMap(accent: accent),
      _Anim.defense        => IntroDefenseMap(accent: accent),
      _Anim.defenseA       => IntroDefenseMapA(accent: accent),
      _Anim.defenseB       => IntroDefenseMapB(accent: accent),
      _Anim.defenseC       => IntroDefenseMapC(accent: accent),
      _Anim.physicalEvents => IntroPhysicalEventsMap(accent: accent),
      _Anim.none           => const SizedBox.shrink(),
    };

// ---------------------------------------------------------------------------
// Shared gradient helper for split-bleed slides
// ---------------------------------------------------------------------------
LinearGradient _splitBleedGradient({required bool visualOnTop}) {
  const stops = [0.0, 0.10, 0.42, 0.58, 0.72, 1.0];
  final colors = [
    kBg.withValues(alpha: 0.0),
    kBg.withValues(alpha: 0.0),
    kBg.withValues(alpha: 0.55),
    kBg.withValues(alpha: 0.92),
    kBg,
    kBg,
  ];
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: stops,
    colors: visualOnTop ? colors : colors.reversed.toList(),
  );
}

// ---------------------------------------------------------------------------
// IntroScreen
// ---------------------------------------------------------------------------
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  int _page = 0;
  int _prevPage = 0;
  Axis _axis = Axis.vertical;
  int _dir = 1; // +1 forward, -1 backward

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _prevPage = _page);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    await markShowcaseSeen();
    if (!mounted) return;
    ref.invalidate(showcaseSeenProvider);
  }

  void _navigate(int delta, {Axis axis = Axis.vertical}) {
    final next = (_page + delta).clamp(0, _slides.length - 1);
    if (next == _page) {
      if (delta > 0 && _page == _slides.length - 1) _done();
      return;
    }
    setState(() {
      _prevPage = _page;
      _page = next;
      _axis = axis;
      _dir = delta.sign;
    });
    _ctrl.forward(from: 0);
  }

  void _next({Axis axis = Axis.vertical}) => _navigate(1, axis: axis);
  void _prev({Axis axis = Axis.vertical}) => _navigate(-1, axis: axis);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final top = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: kBg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -200) {
            _next(axis: Axis.horizontal);
          } else if (v > 200) {
            _prev(axis: Axis.horizontal);
          }
        },
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -200) {
            _next(axis: Axis.vertical);
          } else if (v > 200) {
            _prev(axis: Axis.vertical);
          }
        },
        child: Stack(
          children: [
            // Pre-warm FlutterMap tile cache for all slides before user reaches them.
            const Offstage(
              offstage: true,
              child: Column(children: [
                IntroPulseMap(accent: kAccent),
                IntroCaptureMap(accent: kSea),
                IntroRivalsMap(accent: kAccent),
                IntroFlagDropMap(accent: kAccent2),
              ]),
            ),
            // Stack-based slide transition — no AnimatedSwitcher flicker
            ClipRect(
              child: Stack(
                children: [
                  // Outgoing — slides away
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset.zero,
                      end: _axis == Axis.vertical
                          ? Offset(0, -_dir.toDouble())
                          : Offset(-_dir.toDouble(), 0),
                    ).animate(CurvedAnimation(
                      parent: _ctrl,
                      curve: Curves.easeInOutCubic,
                    )),
                    child: _SlidePage(
                      slide: _slides[_prevPage],
                      key: ValueKey(_prevPage),
                    ),
                  ),
                  // Incoming — slides in
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: _axis == Axis.vertical
                          ? Offset(0, _dir.toDouble())
                          : Offset(_dir.toDouble(), 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _ctrl,
                      curve: Curves.easeInOutCubic,
                    )),
                    child: _SlidePage(
                      slide: _slides[_page],
                      key: ValueKey(_page),
                    ),
                  ),
                ],
              ),
            ),

            // Tap-border navigation — left edge → prev, right edge → next.
            // Excludes top 60px (SKIP button zone) and bottom 180px (CTA zone).
            Positioned(
              top: top + 60,
              bottom: 180,
              left: 0,
              width: screenWidth * 0.15,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _prev(axis: Axis.horizontal),
              ),
            ),
            Positioned(
              top: top + 60,
              bottom: 180,
              right: 0,
              width: screenWidth * 0.15,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _next(axis: Axis.horizontal),
              ),
            ),

            // Skip row — floats above content
            Positioned(
              top: top + 8,
              right: 20,
              child: SizedBox(
                height: 36,
                child: AnimatedOpacity(
                  opacity: _page < _slides.length - 1 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    // Long-press resets showcase_seen without wiping SQLite data.
                    onLongPress: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('showcase_seen');
                    },
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
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 28 : 6,
                          height: i == _page ? 8 : 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: i == _page ? kAccent : kFgFaint,
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide page — dispatches to layout variant
// ---------------------------------------------------------------------------
class _SlidePage extends StatelessWidget {
  final _Slide slide;
  const _SlidePage({required this.slide, super.key});

  @override
  Widget build(BuildContext context) {
    switch (slide.layout) {
      case _Layout.fullBleed:
        return _FullBleedSlide(slide: slide);
      case _Layout.textTopVisualBottom:
        return _SplitBleedSlide(slide: slide, visualOnTop: false);
      case _Layout.visualTopTextBottom:
        return _SplitBleedSlide(slide: slide, visualOnTop: true);
      case _Layout.centeredClose:
        return _CenteredCloseSlide(slide: slide);
    }
  }
}

// ---------------------------------------------------------------------------
// Layout A — Full bleed (fallback layout; kept for future use)
// Real Valencia FlutterMap fills screen, scrim darkens bottom, text overlays.
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
        Positioned.fill(
          child: _buildAnimWidget(slide.anim, slide.tagColor),
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
          top: top + 80,
          left: 28,
          right: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TagChip(label: slide.tag, color: slide.tagColor),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: Text(
                  slide.headline,
                  style: GoogleFonts.bebasNeue(
                    fontSize: 64,
                    height: 1.0,
                    color: kFg,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                slide.body,
                maxLines: slide.bodyMaxLines,
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
// Layout B — Full-bleed split (slides 2-6)
// Map fills the entire screen; a gradient dissolves it into kBg on one half
// so that the text block floats on a clean dark surface.
// ---------------------------------------------------------------------------
class _SplitBleedSlide extends StatelessWidget {
  final _Slide slide;
  final bool visualOnTop;
  const _SplitBleedSlide({required this.slide, required this.visualOnTop});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TagChip(label: slide.tag, color: slide.tagColor),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: Text(
            slide.headline,
            style: GoogleFonts.bebasNeue(
              fontSize: 54,
              height: 1.0,
              color: kFg,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          slide.body,
          maxLines: slide.bodyMaxLines,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle(size: 13, color: kFgMuted),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildAnimWidget(slide.anim, slide.tagColor),

        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: _splitBleedGradient(visualOnTop: visualOnTop),
            ),
          ),
        ),

        if (visualOnTop)
          Positioned(
            left: 28,
            right: 28,
            bottom: 148,
            child: textBlock,
          )
        else
          Positioned(
            top: top + 56,
            left: 28,
            right: 28,
            child: textBlock,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Layout C — Centered close (slide 7: invite only)
// Pure dark screen, centered typography, pulse ring — silence = pressure
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
          Center(child: TagChip(label: slide.tag, color: slide.tagColor)),
          const SizedBox(height: 16),
          const PulseRing(),
          const SizedBox(height: 20),
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
            maxLines: slide.bodyMaxLines,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(size: 15, color: kFgMuted),
          ),
          const SizedBox(height: 20),
          Container(width: 40, height: 1, color: kAccent.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
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
