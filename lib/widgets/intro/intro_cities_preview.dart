// lib/widgets/intro/intro_cities_preview.dart
//
// IntroCitiesPreview -- slide 10 ("Choose your ground."). A non-interactive,
// display-only 3D card carousel previewing the real city roster
// (kCitiesCatalog).
//
// Design: the "constant linear turntable" locked in
// infra/meta/specs/runwar/intro-carousel-realism/decisions.md
// ("Slide 10 Choose your ground", APPROVED by operator) and mocked up as
// slide A's proposed column in
// infra/meta/specs/runwar/intro-carousel-realism/mockups/slides-proposed.html
// (`a-pro-orbit`: rotateY 0..360deg translateZ(R), 18s linear, perspective
// 900px, depth-locked opacity/blur). This replaces the earlier
// "Land and Go" dwell/land schedule, whose per-card arrival/departure
// easing and piecewise waypoint path produced exactly the uneven-easing
// wobble the redesign calls out.
//
// The three locked craft rules, mapped to this implementation:
//
//   1. ONE constant linear angular speed. The shared AnimationController
//      repeats linearly over kCitiesRingLoopDuration (18s, matching the
//      mockup) and each card's ring angle is a pure linear function of the
//      controller value: theta = 2*pi*(t + i/6). No Curve, Cubic, or
//      per-segment easing exists anywhere on the motion path.
//   2. Scale, opacity and blur are functions of DEPTH only. depth =
//      cos(theta) in [-1, 1] (1 = nearest/front). Scale falls out of the
//      real perspective divide (Matrix4 entry(3,2)); opacity and blur are
//      monotonic linear maps of depth. Nothing is keyed to elapsed time.
//   3. Cards are sorted and painted back-to-front by depth every frame, so
//      nearer cards always occlude farther ones with no popping at swap
//      boundaries.
//
// Non-interactive: no GestureDetector exists anywhere in this widget, and
// the whole thing is additionally wrapped in IgnorePointer as defense in
// depth. This is a showcase, not a picker -- real city selection only
// happens post-signup, on CitiesSelectionScreen.
//
// Data note: kCitiesCatalog.totalTarget is real, static per-city capacity
// data and is used directly in the readout below. kCitiesCatalog.joinedCount
// always defaults to 0 in this static constant -- live per-city join counts
// are only available at runtime via CitiesRepository/citiesProvider
// (Supabase-backed, see lib/providers/cities_provider.dart), not stored in
// the static catalog itself. Wiring that live async count into this
// non-interactive intro carousel would add a new network dependency, which
// the redesign decision explicitly said this slide does not need -- so the
// readout shows the real capacity ceiling ("N SPOTS") rather than a
// fabricated or always-zero occupancy count.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cities_catalog.dart';
import '../../theme.dart';

/// One full ring revolution -- all 6 cities pass the front once. Matches the
/// mockup's proposed 18s linear orbit (`a-pro-orbit 18s linear infinite`);
/// the old 16.8s value belonged to the retired dwell schedule.
const Duration kCitiesRingLoopDuration = Duration(milliseconds: 18000);

const int _kCityCount = 6;

/// Ring radius in logical px. The mockup uses translateZ(150px) in a 320px
/// viewport; scaled to a ~360dp phone width this keeps the same proportions.
const double _kRingRadius = 168.0;

/// Perspective divide, 1/d for the mockup's `perspective: 900px`. Front
/// cards (z = -R) scale to ~1.23x, back cards (z = +R) to ~0.84x -- the
/// depth-locked scale falloff comes entirely from this real divide.
const double _kPerspective = 1.0 / 900.0;

/// Depth-locked opacity endpoints: 1.0 at the front of the ring, this at
/// the very back (mockup: opacity .28 at 180deg).
const double _kBackOpacity = 0.28;

/// Depth-locked blur endpoint at the very back of the ring (mockup:
/// blur(2.4px) at 180deg). Sigma is quantized in the widget layer to avoid
/// re-creating an ImageFilter at a new sigma every frame.
const double _kMaxBlurSigma = 2.4;

/// Readout visibility window, in phase distance from the exact front of the
/// ring: fully visible while within [_kReadoutHoldPhase], linearly fading
/// to invisible by [_kReadoutFadePhase]. 1/12 is the half-slot boundary, so
/// consecutive cities cross-fade with no overlap and no long dead gap
/// (mirrors the mockup's ~16.6%-of-loop per-city window).
const double _kReadoutHoldPhase = 0.055;
const double _kReadoutFadePhase = 1.0 / 12.0;

/// This card's own phase within [0,1), given the shared controller value and
/// the card's index (each of the 6 cards is offset by 1/6 of the loop).
/// Phase 0 == exact front of the ring. Linear in the controller value by
/// construction: constant angular speed, no easing anywhere on the path.
double cityCardPhase(double controllerValue, int index) {
  final p = controllerValue + index / _kCityCount;
  return p - p.floorToDouble();
}

@immutable
class CityCardPose {
  const CityCardPose({
    required this.angleRadians,
    required this.depth,
    required this.opacity,
    required this.blurSigma,
    required this.readoutOpacity,
  });

  /// Ring angle theta = 2*pi*phase. 0 == front, pi == back.
  final double angleRadians;

  /// cos(theta) in [-1, 1]; 1 is nearest to the viewer. The single value
  /// every visual falloff (paint order, opacity, blur) derives from.
  final double depth;

  final double opacity;
  final double blurSigma;
  final double readoutOpacity;
}

/// Pure pose function for a single card's own phase. Exposed at library
/// (non-private) scope so widget tests can assert the schedule directly.
CityCardPose cityCardPose(double phase) {
  final p = phase - phase.floorToDouble();
  final theta = p * 2 * math.pi;
  final depth = math.cos(theta);
  // Normalized nearness: 0 at the very back, 1 at the very front. Opacity
  // and blur are monotonic linear functions of this (i.e. of depth), never
  // of time -- the depth-locked rule.
  final near = (depth + 1.0) / 2.0;
  final opacity = _kBackOpacity + (1.0 - _kBackOpacity) * near;
  final blurSigma = _kMaxBlurSigma * (1.0 - near);

  // Readout window keyed to phase distance from the exact front.
  final d = p <= 0.5 ? p : 1.0 - p;
  final double readoutOpacity;
  if (d <= _kReadoutHoldPhase) {
    readoutOpacity = 1.0;
  } else if (d >= _kReadoutFadePhase) {
    readoutOpacity = 0.0;
  } else {
    readoutOpacity =
        1.0 - (d - _kReadoutHoldPhase) / (_kReadoutFadePhase - _kReadoutHoldPhase);
  }

  return CityCardPose(
    angleRadians: theta,
    depth: depth,
    opacity: opacity,
    blurSigma: blurSigma,
    readoutOpacity: readoutOpacity,
  );
}

class IntroCitiesPreview extends StatefulWidget {
  const IntroCitiesPreview({super.key});

  @override
  State<IntroCitiesPreview> createState() => _IntroCitiesPreviewState();
}

class _IntroCitiesPreviewState extends State<IntroCitiesPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    assert(kCitiesCatalog.length == _kCityCount);
    _ctrl = AnimationController(vsync: this, duration: kCitiesRingLoopDuration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // Weight the ring toward the bottom half of the slide's remaining
        // space, keeping the top clear for the headline copy (the mockup
        // parks the proposed ring in the lower half of the frame).
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          // Honest non-interactivity signal -- subtler than the old bordered
          // pill banner, matching the mockup's own "REAL SELECTION HAPPENS
          // AFTER SIGNUP" sub-line treatment now that the ambient ring
          // motion itself already reads as a showcase, not a picker.
          Text(
            'REAL SELECTION HAPPENS AFTER SIGNUP',
            textAlign: TextAlign.center,
            style: monoStyle(size: 9, color: kFgMuted),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 230,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => _CarouselRing(controllerValue: _ctrl.value),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 64,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => _Readout(controllerValue: _ctrl.value),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselRing extends StatelessWidget {
  const _CarouselRing({required this.controllerValue});
  final double controllerValue;

  @override
  Widget build(BuildContext context) {
    final entries = List.generate(_kCityCount, (i) {
      final pose = cityCardPose(cityCardPhase(controllerValue, i));
      return (city: kCitiesCatalog[i], pose: pose);
    });
    // Paint strictly back-to-front by depth so nearer cards always occlude
    // farther ones -- no popping at the depth-swap boundary.
    entries.sort((a, b) => a.pose.depth.compareTo(b.pose.depth));

    return Stack(
      alignment: Alignment.center,
      children: [
        for (final e in entries)
          Center(
            child: Transform(
              alignment: Alignment.center,
              // rotateY(-theta) then push out to the ring: places the card
              // at (R*sin(theta), 0, -R*cos(theta)) facing the viewer at
              // the front, exactly the mockup's
              // `rotateY(theta) translateZ(R)` under Flutter's z-away
              // convention. Scale falloff comes from the perspective
              // divide itself -- depth-locked by construction.
              transform: Matrix4.identity()
                ..setEntry(3, 2, _kPerspective)
                ..rotateY(-e.pose.angleRadians)
                ..translateByDouble(0.0, 0.0, -_kRingRadius, 1.0),
              child: Opacity(
                opacity: e.pose.opacity.clamp(0.0, 1.0),
                child: _DepthBlur(
                  sigma: e.pose.blurSigma,
                  child: _RingCard(city: e.city),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Applies the depth blur with the sigma quantized to 0.25 steps, so a new
/// ImageFilter is only built when the card has moved a meaningful depth
/// distance -- not at a fresh sigma on every single frame. Sub-threshold
/// sigmas skip the filter entirely (the front half of the ring pays zero
/// blur cost).
class _DepthBlur extends StatelessWidget {
  const _DepthBlur({required this.sigma, required this.child});
  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final quantized = (sigma * 4).roundToDouble() / 4;
    if (quantized < 0.25) return child;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: quantized, sigmaY: quantized),
      child: child,
    );
  }
}

class _RingCard extends StatelessWidget {
  const _RingCard({required this.city});
  final CityEntry city;

  @override
  Widget build(BuildContext context) {
    final badgeText = city.isUnlocked ? 'OPEN' : 'SOON';
    final badgeColor = city.isUnlocked ? kAccent : kFgMuted;

    return Container(
      width: 104,
      height: 146,
      // Static drop shadow (mockup: 0 10px 22px rgba(0,0,0,.5)) -- fixed
      // blur radius, never animated.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: kFg.withValues(alpha: 0.16)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/cities/${city.slug}.jpg',
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.55),
                colorBlendMode: BlendMode.darken,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.3, 0.88],
                      colors: [
                        kBg.withValues(alpha: 0.05),
                        kBg.withValues(alpha: 0.82),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: city.isUnlocked
                        ? kAccent
                        : kBg.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(3),
                    border: city.isUnlocked
                        ? null
                        : Border.all(color: kFg.withValues(alpha: 0.16)),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 8,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: city.isUnlocked ? kBg : badgeColor,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      city.name,
                      style: displayStyle(size: 17, color: kFg),
                    ),
                    Text(
                      '${city.flag} ${city.country.toUpperCase()}',
                      style: monoStyle(size: 7, color: kFgMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.controllerValue});
  final double controllerValue;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern();
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        for (int i = 0; i < _kCityCount; i++)
          Builder(builder: (context) {
            final pose = cityCardPose(cityCardPhase(controllerValue, i));
            final city = kCitiesCatalog[i];
            final status = city.isUnlocked ? 'OPEN' : 'SOON';
            return Opacity(
              opacity: pose.readoutOpacity.clamp(0.0, 1.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    city.name,
                    textAlign: TextAlign.center,
                    style: displayStyle(size: 22, color: kFg),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    city.tagline,
                    textAlign: TextAlign.center,
                    style: monoStyle(size: 8, color: kAccent),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$status · ${fmt.format(city.totalTarget)} SPOTS',
                    textAlign: TextAlign.center,
                    style: monoStyle(
                      size: 8,
                      color: city.isUnlocked ? kAccent2 : kFgMuted,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
