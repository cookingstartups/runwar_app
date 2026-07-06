import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/cities_catalog.dart';
import '../theme.dart';

class CityCard extends StatefulWidget {
  const CityCard({
    super.key,
    required this.city,
    required this.selected,
    required this.onTap,
    this.inviteHint = false,
  });
  final CityEntry city;
  final bool selected;
  final VoidCallback onTap;

  /// Opt-in "Invite friends to unlock" affordance for locked cards. Defaults
  /// to false so the shipped CitiesSelectionScreen call site (which never
  /// passes this) is visually unaffected.
  final bool inviteHint;

  @override
  State<CityCard> createState() => _CityCardState();
}

class _CityCardState extends State<CityCard> with SingleTickerProviderStateMixin {
  late final AnimationController _barCtrl;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _barCtrl.forward();
    });
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  Color _hueToColor(String hue) {
    try {
      final parts = hue.replaceAll('%', '').split(' ');
      if (parts.length != 3) return kAccent;
      final h = double.parse(parts[0]) / 360;
      final s = double.parse(parts[1]) / 100;
      final l = double.parse(parts[2]) / 100;
      return HSLColor.fromAHSL(1.0, h * 360, s, l).toColor();
    } catch (_) {
      return kAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = _hueToColor(widget.city.hue);
    final progress = widget.city.totalTarget > 0
        ? widget.city.joinedCount / widget.city.totalTarget
        : 0.0;

    final badgeText = widget.city.isUnlocked ? 'OPEN' : 'SOON';
    final badgeColor = widget.city.isUnlocked ? kAccent : kFgMuted;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: const Cubic(0.22, 1, 0.36, 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected
                ? kAccent
                : kBorder,
            width: widget.selected ? 2 : 1,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: kAccent.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 0,
                  )
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // City photo at 40% opacity
              Image.asset(
                'assets/cities/${widget.city.slug}.jpg',
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.60),
                colorBlendMode: BlendMode.darken,
              ),
              // Bottom gradient fade
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.4, 1.0],
                      colors: [
                        kBg.withValues(alpha: 0.0),
                        kBg.withValues(alpha: 0.5),
                        kBg.withValues(alpha: 0.98),
                      ],
                    ),
                  ),
                ),
              ),
              // Per-city radial hue tint
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.0, 0.6),
                      radius: 0.8,
                      colors: [
                        hueColor.withValues(alpha: 0.35),
                        hueColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              // Center lock/status puck
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: kBg.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: kFg.withValues(alpha: 0.1)),
                      ),
                      child: Icon(
                        widget.selected
                            ? Icons.check
                            : widget.city.isUnlocked
                                ? Icons.bolt
                                : Icons.lock_outline,
                        color: widget.selected
                            ? kAccent
                            : widget.city.isUnlocked
                                ? kAccent
                                : kFgMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              // Top-right badge
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kFg.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: badgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      letterSpacing: 2.0,
                      color: badgeColor,
                    ),
                  ),
                ),
              ),
              // Top-left checkmark if selected
              if (widget.selected)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: kAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 14, color: kBg),
                  ),
                ),
              // Bottom content
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.city.name,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kFg,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.city.flag}  ${widget.city.country}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: kFgMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Progress bar
                      Stack(
                        children: [
                          Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: kFg.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _barCtrl,
                            builder: (_, __) {
                              return FractionallySizedBox(
                                widthFactor:
                                    progress * _barCtrl.value,
                                child: Container(
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: kAccent.withValues(
                                        alpha: widget.city.isUnlocked
                                            ? 1.0
                                            : 0.5),
                                    borderRadius:
                                        BorderRadius.circular(100),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.city.joinedCount} / ${widget.city.totalTarget}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 1.5,
                          color: kFgMuted,
                        ),
                      ),
                      if (widget.inviteHint && !widget.city.isUnlocked) ...[
                        const SizedBox(height: 6),
                        const Row(
                          children: [
                            Icon(Icons.ios_share, size: 11, color: kAccent2),
                            SizedBox(width: 4),
                            Text(
                              'Invite friends to unlock',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 8,
                                letterSpacing: 1.0,
                                color: kAccent2,
                                fontWeight: FontWeight.w600,
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
          ),
        ),
      ),
    );
  }
}
