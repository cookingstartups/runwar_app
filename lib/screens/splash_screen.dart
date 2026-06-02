import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../widgets/grain_overlay.dart';
import '../widgets/pulse_dot.dart';

// ---------------------------------------------------------------------------
// Zone polygon definitions
// ---------------------------------------------------------------------------
List<Polygon> _buildZones() {
  // Helper: build a rectangle polygon from a center + half-extent
  List<LatLng> rect(double lat, double lng, double dLat, double dLng) => [
        LatLng(lat + dLat, lng - dLng),
        LatLng(lat + dLat, lng + dLng),
        LatLng(lat - dLat, lng + dLng),
        LatLng(lat - dLat, lng - dLng),
      ];

  return [
    // Ruzafa — orange
    Polygon(
      points: rect(39.4608, -0.3779, 0.009, 0.012),
      borderColor: kAccent.withValues(alpha: 0.70),
      borderStrokeWidth: 1.5,
      color: kAccent.withValues(alpha: 0.12),
    ),
    // Carmen — sea blue
    Polygon(
      points: rect(39.4730, -0.3795, 0.008, 0.010),
      borderColor: kSea.withValues(alpha: 0.70),
      borderStrokeWidth: 1.5,
      color: kSea.withValues(alpha: 0.12),
    ),
    // Cabanyal — danger red
    Polygon(
      points: rect(39.4695, -0.3327, 0.009, 0.013),
      borderColor: kDanger.withValues(alpha: 0.70),
      borderStrokeWidth: 1.5,
      color: kDanger.withValues(alpha: 0.12),
    ),
    // Benimaclet — accent2 gold
    Polygon(
      points: rect(39.4790, -0.3680, 0.008, 0.011),
      borderColor: kAccent2.withValues(alpha: 0.70),
      borderStrokeWidth: 1.5,
      color: kAccent2.withValues(alpha: 0.12),
    ),
    // Campanar — sea blue
    Polygon(
      points: rect(39.4830, -0.3950, 0.009, 0.012),
      borderColor: kSea.withValues(alpha: 0.60),
      borderStrokeWidth: 1.5,
      color: kSea.withValues(alpha: 0.10),
    ),
  ];
}

// ---------------------------------------------------------------------------
// Runner ping positions
// ---------------------------------------------------------------------------
const List<LatLng> _pingPositions = [
  LatLng(39.4608, -0.3779), // Ruzafa
  LatLng(39.4730, -0.3795), // Carmen
  LatLng(39.4695, -0.3327), // Cabanyal
];

// ---------------------------------------------------------------------------
// Animated ping widget
// ---------------------------------------------------------------------------
class _RunnerPing extends StatefulWidget {
  const _RunnerPing({required this.delay});
  final Duration delay;

  @override
  State<_RunnerPing> createState() => _RunnerPingState();
}

class _RunnerPingState extends State<_RunnerPing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding ring
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Opacity(
              opacity: _opacity.value,
              child: Container(
                width: 12 + _scale.value * 16, // 12 → 28
                height: 12 + _scale.value * 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: kAccent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          // Core dot
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: kAccent,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Splash screen
// ---------------------------------------------------------------------------
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
  late final List<Polygon> _zones;

  @override
  void initState() {
    super.initState();
    _zones = _buildZones();

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

  List<Marker> _buildRunnerMarkers() {
    return [
      for (int i = 0; i < _pingPositions.length; i++)
        Marker(
          point: _pingPositions[i],
          width: 36,
          height: 36,
          child: _RunnerPing(
            delay: Duration(milliseconds: i * 600),
          ),
        ),
    ];
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
          // Layer 1: Embedded live map — CartoDB dark tiles + zone polygons + runner pings
          Positioned.fill(
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(39.4699, -0.3763),
                initialZoom: 13.5,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.cookingstartups.runwar',
                ),
                PolygonLayer(polygons: _zones),
                MarkerLayer(markers: _buildRunnerMarkers()),
              ],
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
                    const Text(
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
                    const PulseDot(color: kAccent, size: 6),
                    const SizedBox(width: 8),
                    Text(
                      widget.statusLabel,
                      style: const TextStyle(
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
