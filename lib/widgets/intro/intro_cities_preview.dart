// lib/widgets/intro/intro_cities_preview.dart
//
// IntroCitiesPreview -- slide 10 ("Choose your ground."). A non-interactive,
// display-only 3D card carousel previewing the real city roster
// (kCitiesCatalog): "Land and Go" (Variant B), the locked design at
// infra/meta/specs/runwar/onboarding-remake/slide10-redesign-decision.md.
//
// Six cities sit on a horizontal 3D ring. Each card decelerates into the
// center, dwells there for ~1.8s while a synced readout below shows its
// name, tagline and a numeric capacity signal, then accelerates away as the
// next card sweeps in. One continuous loop, 6 landings per cycle.
//
// Ported from the mockup's "vb"/"landB" section
// (infra/meta/specs/runwar/onboarding-remake/mockups/slide10-redesign-variants-v1.html),
// with the numeric readout enhancement folded in from that same mockup's
// Variant D ("War Drum") capacity line, and two craft fixes applied during
// implementation (see the decision doc):
//
//   1. Continuous easing on the return path. The mockup's CSS keyframe only
//      declared an easing function at the arrival (0%) and departure
//      (16.67%) breakpoints; the intermediate return-path waypoints
//      (27% -> 42% -> 62% -> 84% -> 100%) fell back to per-segment default
//      easing, producing a visible stutter at each keyframe boundary. Here
//      the whole return path is driven by ONE continuous curve
//      (`_kReturnCurve`, currently linear) applied across that entire span;
//      only the arrival and departure legs get the deliberate eased
//      "landing" feel.
//   2. Glow via opacity, not blur radius. The landed-card glow is a single
//      static (fixed blur radius) glow layer whose OPACITY is animated --
//      never a box-shadow whose blur radius itself is animated, which is
//      expensive to composite.
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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cities_catalog.dart';
import '../../theme.dart';

/// One full ring cycle -- all 6 cities land once. Matches the mockup's
/// 16.8s loop (2.8s per city slot: 16800 / 6 == 2800).
const Duration kCitiesRingLoopDuration = Duration(milliseconds: 16800);

const int _kCityCount = 6;

// ── Waypoint tables (fractions of one card's own 0..1 phase) ───────────────
// Mirrors the mockup's landB / fadeB / glowB / nameB keyframes.
const List<double> _kWaypointT = [0.0, 0.06, 0.1667, 0.27, 0.42, 0.62, 0.84, 1.0];
const List<double> _kWaypointX = [92.0, 0.0, 0.0, -92.0, -158.0, 0.0, 158.0, 92.0];
const List<double> _kWaypointZ = [-58.0, 52.0, 52.0, -58.0, -160.0, -280.0, -160.0, -58.0];
const List<double> _kWaypointRotDeg = [-33.0, 0.0, 0.0, 33.0, 44.0, 0.0, -44.0, -33.0];

const List<double> _kFadeT = [0.0, 0.06, 0.1667, 0.27, 0.42, 0.47, 0.80, 0.84, 1.0];
const List<double> _kFadeOp = [0.9, 1.0, 1.0, 0.9, 0.5, 0.0, 0.0, 0.5, 0.9];

// Glow-layer opacity -- craft fix #2: animate opacity of a static blur, not
// the blur radius.
const List<double> _kGlowT = [0.0, 0.06, 0.1667, 0.27, 1.0];
const List<double> _kGlowOp = [0.0, 1.0, 1.0, 0.0, 0.0];

// Readout name/tagline/capacity fade.
const List<double> _kNameT = [0.0, 0.065, 0.085, 0.145, 0.17, 1.0];
const List<double> _kNameOp = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0];

const Cubic _kArrivalCurve = Cubic(0.16, 0.84, 0.3, 1.0);
const Cubic _kDepartureCurve = Cubic(0.55, 0.0, 0.8, 0.35);
// Craft fix #1: ONE continuous curve drives the whole off-center return
// path (27% -> 100%). Linear today; tune this single line, never re-ease
// the individual waypoints below it.
const Curve _kReturnCurve = Curves.linear;

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _piecewiseLerp(List<double> ts, List<double> vs, double t) {
  for (int i = 0; i < ts.length - 1; i++) {
    if (t <= ts[i + 1]) {
      final span = ts[i + 1] - ts[i];
      final localT = span == 0 ? 0.0 : (t - ts[i]) / span;
      return _lerp(vs[i], vs[i + 1], localT.clamp(0.0, 1.0));
    }
  }
  return vs.last;
}

/// This card's own phase within [0,1), given the shared controller value and
/// the card's index (each of the 6 cards is offset by 1/6 of the loop).
double cityCardPhase(double controllerValue, int index) {
  final p = controllerValue + index / _kCityCount;
  return p - p.floorToDouble();
}

@immutable
class CityCardPose {
  const CityCardPose({
    required this.x,
    required this.z,
    required this.rotYRadians,
    required this.opacity,
    required this.glowOpacity,
    required this.readoutOpacity,
  });

  final double x;
  final double z;
  final double rotYRadians;
  final double opacity;
  final double glowOpacity;
  final double readoutOpacity;
}

/// Pure pose function for a single card's own phase. Exposed at library
/// (non-private) scope so widget tests can assert the schedule directly.
CityCardPose cityCardPose(double phase) {
  double x, z, rotDeg;
  if (phase <= 0.06) {
    final eased = _kArrivalCurve.transform((phase / 0.06).clamp(0.0, 1.0));
    x = _lerp(92.0, 0.0, eased);
    z = _lerp(-58.0, 52.0, eased);
    rotDeg = _lerp(-33.0, 0.0, eased);
  } else if (phase <= 0.1667) {
    x = 0.0;
    z = 52.0;
    rotDeg = 0.0; // dwell -- landed and holding
  } else if (phase <= 0.27) {
    final eased = _kDepartureCurve
        .transform(((phase - 0.1667) / (0.27 - 0.1667)).clamp(0.0, 1.0));
    x = _lerp(0.0, -92.0, eased);
    z = _lerp(52.0, -58.0, eased);
    rotDeg = _lerp(0.0, 33.0, eased);
  } else {
    // Return path -- one continuous curve across the whole [0.27, 1.0]
    // span (craft fix #1), then piecewise-linear across the raw waypoints
    // using that single eased progress.
    final u = ((phase - 0.27) / (1.0 - 0.27)).clamp(0.0, 1.0);
    final eased = _kReturnCurve.transform(u);
    final t = 0.27 + eased * (1.0 - 0.27);
    x = _piecewiseLerp(_kWaypointT, _kWaypointX, t);
    z = _piecewiseLerp(_kWaypointT, _kWaypointZ, t);
    rotDeg = _piecewiseLerp(_kWaypointT, _kWaypointRotDeg, t);
  }

  return CityCardPose(
    x: x,
    z: z,
    rotYRadians: rotDeg * 3.14159265358979 / 180.0,
    opacity: _piecewiseLerp(_kFadeT, _kFadeOp, phase),
    glowOpacity: _piecewiseLerp(_kGlowT, _kGlowOp, phase),
    readoutOpacity: _piecewiseLerp(_kNameT, _kNameOp, phase),
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
      final phase = cityCardPhase(controllerValue, i);
      final pose = cityCardPose(phase);
      return (city: kCitiesCatalog[i], pose: pose);
    });
    // Paint back-to-front so nearer (higher z) cards draw over farther ones.
    entries.sort((a, b) => a.pose.z.compareTo(b.pose.z));

    return Stack(
      alignment: Alignment.center,
      children: [
        for (final e in entries)
          Center(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0016)
                ..translateByDouble(e.pose.x, 0.0, e.pose.z, 1.0)
                ..rotateY(e.pose.rotYRadians),
              child: Opacity(
                opacity: e.pose.opacity.clamp(0.0, 1.0),
                child: _RingCard(city: e.city, glowOpacity: e.pose.glowOpacity),
              ),
            ),
          ),
      ],
    );
  }
}

class _RingCard extends StatelessWidget {
  const _RingCard({required this.city, required this.glowOpacity});
  final CityEntry city;
  final double glowOpacity;

  @override
  Widget build(BuildContext context) {
    final badgeText = city.isUnlocked ? 'OPEN' : 'SOON';
    final badgeColor = city.isUnlocked ? kAccent : kFgMuted;

    return SizedBox(
      width: 128,
      height: 182,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Static, pre-blurred glow layer -- craft fix #2: only its
          // opacity is animated, never the blur radius itself.
          Opacity(
            opacity: glowOpacity.clamp(0.0, 1.0),
            child: Container(
              width: 128,
              height: 182,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: kAccent, blurRadius: 34, spreadRadius: 2),
                ],
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
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
                          style: displayStyle(size: 19, color: kFg),
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
        ],
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
            final phase = cityCardPhase(controllerValue, i);
            final pose = cityCardPose(phase);
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
