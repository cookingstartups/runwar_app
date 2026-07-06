import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import '../providers/showcase_provider.dart';
import '../widgets/intro/intro_cities_preview.dart';
import '../widgets/intro/intro_hero_photo.dart';
import '../widgets/intro/intro_loot_drop_map.dart';
import '../widgets/intro/intro_purge_leaderboard.dart';
import '../widgets/intro_map_animations.dart';
import '../widgets/tag_chip.dart';
import '../widgets/valencia_button.dart';

// ---------------------------------------------------------------------------
// Animation type per slide
// ---------------------------------------------------------------------------
enum _Anim { pulse, hexCapture, rivals, ctfDrop, fortify, defense, defenseA, physicalEvents, lootDrop, purgeCut, none }

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
  final String? monoSubline;

  const _Slide({
    required this.tag,
    required this.headline,
    required this.body,
    required this.layout,
    this.tagColor = kAccent,
    this.anim = _Anim.none,
    // ignore: unused_element_parameter
    this.bodyMaxLines = 3,
    this.monoSubline,
  });
}

const _slides = [
  // 1 - Comeback
  _Slide(
    tag: 'CLAIM IT',
    tagColor: kAccent,
    headline: 'Loop it. Own it.',
    body: 'Draw a loop while you run. Close it and the street flips to you instantly — no fights, no waiting on results.',
    anim: _Anim.pulse,
    layout: _Layout.visualTopTextBottom,
  ),
  // 2 - Mastery / Fortify
  _Slide(
    tag: 'FORTIFY',
    tagColor: kAccent,
    headline: 'Run it again. Make it armor.',
    body: 'Every extra lap hardens your claim. Level 1, level 2, level 3. The streets remember who trained hardest.',
    anim: _Anim.fortify,
    layout: _Layout.textTopVisualBottom,
  ),
  // 3 - Provocation
  _Slide(
    tag: 'YOUR TURF',
    tagColor: kSea,
    headline: 'A rival stole your block.',
    body: 'Every street belongs to the last runner who looped it. Their name. Your pavement. Take it back — or keep paying rent in shoe rubber.',
    anim: _Anim.hexCapture,
    layout: _Layout.visualTopTextBottom,
  ),
  // 4 - Shield (Variant A)
  // SHIELD Variant A - winner. B and C archived (classes kept in intro_map_animations.dart).
  _Slide(
    tag: 'SHIELD',
    tagColor: kAccent,
    headline: 'Under attack? Tap back.',
    body: 'Fire your shield straight from the phone. The attack breaks. Your paint stays.',
    anim: _Anim.defenseA,
    layout: _Layout.textTopVisualBottom,
    monoSubline: 'DEFEND FROM HOME, FROM WORK, FROM BED',
  ),
  // 5 - Superpowers
  _Slide(
    tag: 'EARN YOUR EDGE',
    tagColor: kSea,
    headline: 'You cannot pay-to-win. You must earn it.',
    body: 'Shields, strikes, radar sweeps. Every superpower is earned on the street, never bought. Once it is yours, credits can only stretch its reach - extra range, extra time, never a shortcut to owning it.',
    anim: _Anim.defense,
    layout: _Layout.textTopVisualBottom,
  ),
  // 6 - Loot drops
  _Slide(
    tag: 'LOOT DROPS',
    tagColor: kAccent2,
    headline: 'First feet take it all.',
    body: 'Crates hit the map without warning. Cash, gear, killer loot — whoever\'s lungs get there first walks away with everything.',
    anim: _Anim.lootDrop,
    layout: _Layout.visualTopTextBottom,
    bodyMaxLines: 4,
  ),
  // 7 - Special events / CTF
  _Slide(
    tag: 'SPECIAL EVENT',
    tagColor: kAccent,
    headline: 'A flag drops. The city sprints.',
    body: 'One flag. One exact GPS point. Every runner notified in the same second.',
    anim: _Anim.ctfDrop,
    layout: _Layout.textTopVisualBottom,
    bodyMaxLines: 4,
  ),
  // 8 - Purge/survival cut mechanic
  _Slide(
    tag: 'THE PURGE',
    tagColor: kAccent2,
    headline: 'THE PURGE BEGINS',
    body: 'We leave no room for laziness here. Only the disciplined, competitive, and committed survive. If at any point you are one of the bottom 5% of players, your account can be PURGED and you\'d lose it all if that happens. Stay above the line once the purge ends, or lose it all.',
    anim: _Anim.purgeCut,
    layout: _Layout.visualTopTextBottom,
    bodyMaxLines: 8,
  ),
  // 9 - Real-world events
  _Slide(
    tag: 'YEARLY IN-PERSON EVENT',
    tagColor: kAccent2,
    headline: 'Real streets. Real rivals.',
    body: 'Behind every gamertag is a runner in your city.',
    anim: _Anim.physicalEvents,
    layout: _Layout.visualTopTextBottom,
  ),
  // 10 - Cities preview / final CTA
  _Slide(
    tag: 'INVITE ONLY',
    tagColor: kAccent,
    headline: 'Choose your ground.',
    body: 'Valencia is live. Five more cities sit behind the wall.',
    anim: _Anim.none,
    layout: _Layout.centeredClose,
  ),
];

// ---------------------------------------------------------------------------
// Shared top-level helper - resolves _Anim enum to its widget
// ---------------------------------------------------------------------------
Widget _buildAnimWidget(_Anim anim, Color accent) => switch (anim) {
      _Anim.pulse          => IntroPulseMap(accent: accent),
      _Anim.hexCapture     => IntroCaptureMap(accent: accent),
      _Anim.rivals         => IntroRivalsMap(accent: accent),
      _Anim.ctfDrop        => IntroFlagDropMap(accent: accent),
      _Anim.fortify        => IntroFortifyMap(accent: accent),
      _Anim.defense        => IntroDefenseMap(accent: accent),
      _Anim.defenseA       => IntroDefenseMapA(accent: accent),
      _Anim.physicalEvents => const IntroHeroPhoto(),
      _Anim.lootDrop       => const IntroLootDropMap(),
      _Anim.purgeCut       => const IntroPurgeLeaderboard(),
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
                IntroLootDropMap(),
              ]),
            ),
            // Stack-based slide transition - no AnimatedSwitcher flicker
            ClipRect(
              child: Stack(
                children: [
                  // Outgoing - slides away
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
                      onDone: _done,
                      key: ValueKey(_prevPage),
                    ),
                  ),
                  // Incoming - slides in
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
                      onDone: _done,
                      key: ValueKey(_page),
                    ),
                  ),
                ],
              ),
            ),

            // Tap-border navigation - left edge → prev, right edge → next.
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

            // Skip row - floats above content
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

            // Dots + CTA - floats at bottom
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
// Slide page - dispatches to layout variant
// ---------------------------------------------------------------------------
class _SlidePage extends StatelessWidget {
  final _Slide slide;
  final VoidCallback onDone;
  const _SlidePage({required this.slide, required this.onDone, super.key});

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
        return _CitiesPreviewSlide(slide: slide, onDone: onDone);
    }
  }
}

// ---------------------------------------------------------------------------
// Layout A - Full bleed (fallback layout; kept for future use)
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

        // Bottom scrim - keeps CTA area readable
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

        // Text - positioned center-left, above scrim
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
// Layout B - Full-bleed split (slides 2-6)
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
        if (slide.monoSubline != null) ...[
          const SizedBox(height: 10),
          Text(slide.monoSubline!, style: monoStyle(size: 10, color: slide.tagColor)),
        ],
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
// Layout C - Cities preview (slide 10: choose your ground / final CTA)
// Honest preview of real city selection - Valencia OPEN, five cities locked
// behind an invite-to-unlock affordance - closing with the final signup CTA.
// ---------------------------------------------------------------------------
class _CitiesPreviewSlide extends StatelessWidget {
  final _Slide slide;
  final VoidCallback _done;
  const _CitiesPreviewSlide({required this.slide, required VoidCallback onDone})
      : _done = onDone;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: top + 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TagChip(label: slide.tag, color: slide.tagColor),
              const SizedBox(height: 14),
              Text(
                slide.headline,
                style: GoogleFonts.bebasNeue(
                  fontSize: 42,
                  height: 1.0,
                  color: kFg,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                slide.body,
                maxLines: slide.bodyMaxLines,
                overflow: TextOverflow.ellipsis,
                style: bodyStyle(size: 13, color: kFgMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Expanded(child: IntroCitiesPreview()),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 96),
          child: ValenciaButton(
            label: "I'M IN · CREATE MY ACCOUNT",
            onPressed: _done,
          ),
        ),
      ],
    );
  }
}
