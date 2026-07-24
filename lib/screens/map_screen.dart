import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../providers/auth_provider.dart';
import '../providers/cities_provider.dart';
import '../providers/profile_provider.dart';
import '../utils/string_utils.dart';
import '../providers/runs_provider.dart';
import '../providers/zones_provider.dart';
import '../providers/zones_repository_provider.dart';
import '../providers/run_recorder_provider.dart';
import '../providers/app_config_provider.dart';
import '../services/error_log_service.dart';
import '../services/run_recorder_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/permission_service.dart';
import '../widgets/battery_warning_banner.dart';
import '../widgets/location_denied_gate.dart';
import '../widgets/territory_overlay_painter.dart';
import '../widgets/zone_level_badge.dart';
import '../widgets/intro/intro_helpers.dart'
    show sharedEdgePolylines, formatSqm, IntroContinuity;
import '../geo/lasso.dart' show polygonArea, pointInPolygon;
import '../geo/polygon_smoothing.dart' show chaikinSmoothClosed;
import '../services/ctf_service.dart';
import '../services/realtime_presence_service.dart';
import '../services/superpower_service.dart';
import '../services/supabase_service.dart';
import '../services/territory_service.dart';
import '../services/tile_cache_service.dart';
import '../services/trial_service.dart';
import '../utils/runwar_constants.dart';
import '../services/database/models/zone.dart';
import '../services/database/models/city_config.dart';
import '../widgets/attack_sheet.dart';
import '../widgets/dispute_countdown_label.dart';
import '../widgets/drop_marker.dart';
import '../widgets/credits_chip.dart';
import '../widgets/streak_chip.dart';
import '../widgets/superpower_inventory_strip.dart';
import '../widgets/mission_mode_overlay.dart';
import '../widgets/first_zone_celebration_overlay.dart';
import '../widgets/beam_pulse_dot.dart';
import '../widgets/rival_runner_marker.dart';
import '../widgets/runner_comet.dart';
import '../widgets/simulation_control_panel.dart';
// Phase 2 providers — written by @Backend-Developer (design.md §5.1).
import '../providers/drops/active_drops_provider.dart';
// Phase 2 repositories — written by @Backend-Developer.
import '../providers/repositories.dart';
import '../services/database/drops_repository.dart';
import '../services/database_service.dart';
import '../services/bot_spawner_service.dart';
import '../models/mission_step.dart';
import '../providers/mission_provider.dart';
import '../theme.dart';
import 'main_shell.dart';
import '../main.dart' show trialStatusProvider;

// ── Constants ────────────────────────────────────────────────────────────────
// City center and bounds are now loaded from cityConfigProvider (design.md §5).
// _kCityCenter and _kDefaultCenter removed; use CityConfig.valencia fallback.

const double _kInitialZoom = 16.0;

// ── Tile configuration ────────────────────────────────────────────────────────

const String _kTileUrl =
    'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png';
const List<String> _kTileSubdomains = ['a', 'b', 'c', 'd'];

// ── Zone styling ──────────────────────────────────────────────────────────────

const Color _kDisputedColor = Color(0xFFC8973A); // amber for disputed zones

// ── MapScreen widget ─────────────────────────────────────────────────────────

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.missionStep, this.botZoneId});

  /// When non-null, the map is in guided mission mode and composites
  /// a [MissionModeOverlay] over the map body.
  final MissionStep? missionStep;

  /// Passed only for [MissionStep.mission2Attack] so the overlay can point
  /// at the rival zone. Null for mission1Claim.
  final String? botZoneId;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _posSub;
  Position? _currentPosition;
  bool _centeredOnGps = false;
  // Simulation-aware camera-follow state (SPEC-0144). Mirrors the shape of
  // _centeredOnGps but scoped to the simulated position source; reset on every
  // new simulation (detected via RunRecorderService.simulationGeneration),
  // never persisted.
  bool _simSnapDone = false;
  bool _simAutoFollowSuspended = false;
  // Last simulation generation this screen has reset its camera flags for.
  // Compared against RunRecorderService.instance.simulationGeneration on
  // every tick instead of diffing isSimulationActive, because a simulation
  // that ends via stopRun() (a normal user_stop_pressed fixture event) never
  // flips isSimulationActive on a trackVersion tick and would otherwise leave
  // a missed falling edge: the boolean edge check alone cannot tell "this is
  // a second simulation" from "this is the same simulation still running"
  // once _MapScreenState stays mounted across replays.
  int _lastSimulationGeneration = 0;
  // Revoked-after-priming late guard: true when PermissionService's live
  // recheck (in _initLocation) shows location is no longer granted.
  bool _locationRevoked = false;
  late final AnimationController _terrainPulse;

  // Logs only the first camera-projection failure per session (cheap,
  // no spam) - this loop samples every 8px along every unified-owned-zone
  // contour, so a persistently-not-ready camera would otherwise flood logs.
  bool _cameraProjectionErrorLogged = false;

  // Cached city name updated on every build; read at transition time by the
  // stream handler so the auto-claim handler always receives the current value.
  String? _currentCity;
  StreamSubscription<({ClaimOutcome outcome, List<LatLng> polygon})>? _autoClaimSub;
  StreamSubscription<({GateRejectionReason reason, Map<String, dynamic> details})>?
      _gateRejectionSub;

  // ── Expand & Unify overlay state ──────────────────────────────────────────
  AnimationController? _euController;
  Path _euPriorUnion = Path();
  List<Offset> _euNewBlock = const [];
  Path _euUnionAfter = Path();
  List<List<Offset>>? _euSharedEdges;
  Color? _euAccent;
  List<Offset> _euRoutePoints = const [];
  double _euTailLengthPx = 0.0;
  int _euCapturedSqm = 0;
  ClaimOutcome? _lastClaimOutcome;

  // ── Capture flash overlay state ───────────────────────────────────────────
  // One-shot fill flare + ping ring on a successful claim, layered above the
  // E&U overlay and eased out over IntroContinuity.kCaptureFlashDuration.
  // Purely additive - never mutates the steady level-derived alpha the
  // persistent zone polygon renders underneath.
  AnimationController? _captureFlashController;
  List<Offset> _captureFlashPoly = const [];
  Color _captureFlashColor = kAccent;

  @override
  void initState() {
    super.initState();
    _terrainPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // Subscribe to the auto-claim outcome stream unconditionally in initState
    // so claim results are never lost regardless of build() state.
    _autoClaimSub = ref
        .read(runRecorderProvider.notifier)
        .autoClaimOutcomes
        .listen(_onAutoClaimOutcome);

    // Subscribe to silent gate-rejection feedback (R1) alongside the
    // auto-claim outcome stream, same initState-registration rationale.
    _gateRejectionSub = ref
        .read(runRecorderProvider.notifier)
        .gateRejections
        .listen(_onGateRejected);

    SuperpowerService.instance.onShieldEarned = (grant) {
      if (mounted) _showShieldEarnedModal(grant);
    };
    // request permission once at mount; use addPostFrameCallback
    // so the OS dialog appears after the first frame paints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      CtfService.instance.refresh();
      final userId = ref.read(authProvider).user?['id'] as String?;
      if (userId != null) {
        ref.read(profileGateProvider(userId).future).then((profile) {
          final color = profile?['color']?.toString() ?? '#FF7A00';
          RealtimePresenceService.instance.setColorHex(color);
        }).catchError((_) {});
      }
    });
  }

  /// Location is no longer requested here. The priming screen is the
  /// single place the OS dialog fires; this is a no-op-if-granted late
  /// guard that only starts the position stream when PermissionService
  /// already reports location as granted, or flags the revoked-after-priming
  /// hard gate (build() renders [LocationDeniedGate] when [_locationRevoked]).
  Future<void> _initLocation() async {
    final granted = await PermissionService.instance.isLocationGranted();
    if (!mounted) return;
    if (!granted) {
      setState(() => _locationRevoked = true);
      return;
    }
    setState(() => _locationRevoked = false);
    // Guard against re-entry (e.g. Try Again after a revoked-permission
    // recovery) leaving a duplicate, never-cancelled stream subscription.
    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _currentPosition = pos);
      RealtimePresenceService.instance.updatePosition(LatLng(pos.latitude, pos.longitude));
      if (!_centeredOnGps) {
        _centeredOnGps = true;
        _mapController.move(
          LatLng(pos.latitude, pos.longitude),
          _kInitialZoom,
        );
      }
      CtfService.instance.checkCaptureProximity(pos.latitude, pos.longitude);
    });
  }

  /// Drives the camera during an active simulation. Wired via ref.listen on
  /// runRecorderTrackVersionProvider (SPEC-0144 section 3.2). One-shot
  /// snap-to-start on the first simulated fix, then continuous follow at the
  /// current zoom while the operator has not manually panned/zoomed.
  void _onSimTrackTick() {
    if (!mounted) return;
    final simActive = RunRecorderService.instance.isSimulationActive;
    final currentGeneration = RunRecorderService.instance.simulationGeneration;
    if (currentGeneration != _lastSimulationGeneration) {
      // A new simulation has begun since this screen last reset, regardless
      // of how the previous one ended. Re-arm for it.
      _simAutoFollowSuspended = false;
      _simSnapDone = false;
      _lastSimulationGeneration = currentGeneration;
    }
    if (!simActive) return; // real-run ticks are a no-op past this line
    final snap = RunRecorderService.instance.trackSnapshot;
    if (snap.isEmpty) return; // no fix yet; nothing to snap to
    final last = snap.last;
    if (!_simSnapDone) {
      _simSnapDone = true;
      _mapController.move(last, _kInitialZoom); // one-shot snap-to-start
    } else if (!_simAutoFollowSuspended) {
      _mapController.move(last, _mapController.camera.zoom); // continuous follow
    }
  }

  /// Detects a manual pan/zoom gesture during an active simulation and
  /// suspends auto-follow. Filters out our own programmatic move() calls,
  /// which flutter_map always tags with MapEventSource.mapController - the
  /// package invariant this guard relies on (design.md SPEC-0144 section 2).
  void _handleMapEvent(MapEvent event) {
    if (!RunRecorderService.instance.isSimulationActive) return;
    if (event.source == MapEventSource.mapController) return; // our own move() call, not a gesture
    _simAutoFollowSuspended = true;
  }

  /// Shared own-position derivation (SPEC-0144 section 3.4): the simulated
  /// track's last point while a simulation is active, otherwise real GPS.
  /// Used by widgets outside a Consumer(runRecorderTrackVersionProvider) so
  /// as not to duplicate the own-position ternary inline at every call site.
  LatLng? _simOrRealOwnPosition() {
    final isSimulationActive = RunRecorderService.instance.isSimulationActive;
    final simSnap = isSimulationActive ? RunRecorderService.instance.trackSnapshot : const <LatLng>[];
    return isSimulationActive
        ? (simSnap.isEmpty ? null : simSnap.last)
        : (_currentPosition == null
            ? null
            : LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
  }

  @override
  void dispose() {
    _autoClaimSub?.cancel();
    _gateRejectionSub?.cancel();
    SuperpowerService.instance.onShieldEarned = null;
    _terrainPulse.dispose();
    _euController?.dispose();
    _captureFlashController?.dispose();
    _posSub?.cancel();
    super.dispose();
  }

  void _showShieldEarnedModal(SuperpowerGrant grant) {
    final expiryMins = grant.expiresAt.difference(DateTime.now()).inMinutes;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🛡️ SHIELD EARNED', style: TextStyle(color: Color(0xFFFF7A00), fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            Text('All your zones are now protected for $expiryMins min.',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            Text('Activate 1 extra charge for ${grant.creditsToActivate} credits?',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7A00)),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('CLOSE', style: TextStyle(color: Colors.white, fontFamily: 'monospace')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Resolves the user's city display name and map fallback center.
  /// City comes from joinedCitySlugsProvider (capitalised first slug).
  /// Center comes from cityConfigProvider (falls back to CityConfig.valencia).
  /// Returns slugsAsync so build() can branch on loading/empty without
  /// watching the provider twice.
  ({AsyncValue<List<String>> slugsAsync, LatLng center}) _resolveCenter() {
    final auth = ref.watch(authProvider);
    final userId = auth.user?['id'] as String?;
    final cityConfig =
        ref.watch(cityConfigProvider).valueOrNull ?? CityConfig.valencia;
    if (userId == null) {
      return (
        slugsAsync: const AsyncValue<List<String>>.data([]),
        center: cityConfig.center,
      );
    }
    final slugsAsync = ref.watch(joinedCitySlugsProvider(userId));
    return (slugsAsync: slugsAsync, center: cityConfig.center);
  }

  @override
  Widget build(BuildContext context) {
    // Drives simulation camera-follow ticks. Must be the first statement in
    // build(), before any early return, so it registers on every build call
    // (design.md SPEC-0144 section 3.1 risk register entry 1).
    ref.listen<int>(runRecorderTrackVersionProvider, (prev, next) => _onSimTrackTick());

    final auth = ref.watch(authProvider);
    final userId = (auth.user?['id'] as String?) ?? '';

    // Gate: show spinner only while joinedCitySlugsProvider is loading (AC-2).
    // Once resolved to empty, show an error state — never a permanent spinner (AC-3, Condition C1).
    final (:slugsAsync, :center) = _resolveCenter();
    if (slugsAsync.isLoading) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(
          child: CircularProgressIndicator(color: kAccent, strokeWidth: 2),
        ),
      );
    }
    if ((slugsAsync.valueOrNull ?? []).isEmpty) {
      return Scaffold(
        backgroundColor: kBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No city joined yet', style: bodyStyle(color: kFgMuted)),
              const SizedBox(height: 20),
              ElevatedButton(
                // Re-evaluates _RouteGuard's gate order — invalidating this
                // provider with no joined cities re-renders CitiesSelectionScreen.
                // INVARIANT: never Navigator.pushReplacement over _RouteGuard.
                onPressed: () =>
                    ref.invalidate(joinedCitySlugsProvider(userId)),
                child: const Text('CHOOSE YOUR CITY'),
              ),
            ],
          ),
        ),
      );
    }

    final city = capitalize(slugsAsync.value!.first);
    // Keep _currentCity fresh on every build so the initState listener reads
    // the current city value at transition time, not a stale captured value.
    _currentCity = city;

    final zonesAsync = ref.watch(zonesProvider(city));

    // Build the same revealed-area circles used by _FogLayer so we can
    // hide zones and CTF pins that sit entirely inside unexplored fog.
    final runPoints = ref
        .watch(userRunPointsProvider((userId: userId, city: city)))
        .valueOrNull ?? const [];
    final fogCenters = <({LatLng point, double radiusM})>[
      for (final pt in runPoints) (point: pt, radiusM: 5000),
      if (_currentPosition != null)
        (
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          radiusM: 1000,
        ),
    ];

    final recState = ref.watch(runRecorderProvider);
    final isRecording = recState == RecorderState.recording;

    final mapBody = zonesAsync.when(
      loading: () => _buildMap(context, center, const [],
          showError: false, city: city, userId: userId, fogCenters: fogCenters, isRecording: isRecording),
      error: (e, _) => _buildMap(context, center, const [],
          showError: true, city: city, userId: userId, fogCenters: fogCenters, isRecording: isRecording),
      data: (zones) => _buildMap(context, center, zones,
          showError: false, city: city, userId: userId, fogCenters: fogCenters, isRecording: isRecording),
    );

    // When in mission mode, composite MissionModeOverlay on top of the map.
    final body = widget.missionStep != null
        ? Stack(
            children: [
              mapBody,
              MissionModeOverlay(
                missionStep: widget.missionStep!,
                isRecording: isRecording,
              ),
            ],
          )
        : mapBody;

    final screenBody = _locationRevoked
        ? LocationDeniedGate(
            // Re-run _initLocation (not just clear the flag) so the
            // position stream actually restarts after re-granting -
            // otherwise the map shows with no GPS dot or updates.
            onGranted: _initLocation,
          )
        : body;

    // Tester-only run replay simulation control. Debug builds AND
    // players.is_tester (via isTesterProvider) both gate visibility - a
    // debug build alone never surfaces this to a non-tester, and a tester
    // flag alone never surfaces it in a release build.
    final isTesterAsync =
        kDebugMode && userId.isNotEmpty ? ref.watch(isTesterProvider(userId)) : null;
    final showSimulationControl = kDebugMode && (isTesterAsync?.valueOrNull ?? false);

    return Scaffold(
      backgroundColor: kBg,
      body: showSimulationControl
          ? Stack(
              children: [
                screenBody,
                const SimulationLauncherChip(),
              ],
            )
          : screenBody,
      floatingActionButton: _buildFab(context, city),
    );
  }

  Widget _buildFab(BuildContext context, String city) {
    final recState = ref.watch(runRecorderProvider);
    final isRecording = recState == RecorderState.recording;
    // Simulation-aware own-position derivation, shared with the Locate
    // button and the own-player markers (design.md SPEC-0144 section 3.4).
    final isSimulationActive = RunRecorderService.instance.isSimulationActive;
    final simSnap = isSimulationActive ? RunRecorderService.instance.trackSnapshot : const <LatLng>[];
    final LatLng? ownPos = isSimulationActive
        ? (simSnap.isEmpty ? null : simSnap.last)
        : (_currentPosition == null
            ? null
            : LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
    final hasGps = ownPos != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Locate button — centres map on player's GPS position ──
        FloatingActionButton.small(
          heroTag: 'locate',
          backgroundColor: kSurface,
          foregroundColor: hasGps ? kFg : kFgMuted,
          onPressed: ownPos == null
              ? null
              : () {
                  if (isSimulationActive) _simAutoFollowSuspended = false; // re-arm
                  _mapController.move(ownPos, _kInitialZoom);
                },
          child: const Icon(Icons.my_location, size: 20),
        ),
        const SizedBox(height: 12),
        // ── Run recording FAB ──────────────────────────────────────
        GestureDetector(
          onLongPress: isRecording
              ? () => ref.read(runRecorderProvider.notifier).cancel()
              : null,
          child: FloatingActionButton(
            heroTag: 'run_rec',
            backgroundColor: (hasGps || isRecording) ? kAccent : kSurface,
            foregroundColor: (hasGps || isRecording) ? kBg : kFgMuted,
            onPressed: () => _onFabTap(context, recState, city),
            child: Icon(isRecording ? Icons.stop : Icons.play_arrow),
          ),
        ),
      ],
    );
  }

  Future<void> _onFabTap(
      BuildContext context, RecorderState s, String city) async {
    final notifier = ref.read(runRecorderProvider.notifier);
    if (s == RecorderState.idle) {
      await _startGuardedRun(context);
    } else if (s == RecorderState.recording) {
      // Tap always ends the session unconditionally. No validity gates.
      HapticFeedback.lightImpact();
      await notifier.stop();
    }
  }

  /// Guarded run-start path: permission check, GPS-fix check, trial init,
  /// setActiveUser, battery prompt, tile prewarm, then notifier.start().
  ///
  /// Every entry point that can start a recording — the FAB and
  /// AttackSheet's "Start a run" CTA — must go through this helper so
  /// neither bypasses these guards (a bypass leaves scratch/mission writes
  /// blocked by the null-user guard with no feedback to the runner).
  Future<void> _startGuardedRun(BuildContext context) async {
    final notifier = ref.read(runRecorderProvider.notifier);
    // Verify permission before startRun.
    final perm = await Geolocator.checkPermission();
    final canRecord = perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
    if (!canRecord) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Location permission required to record runs')),
      );
      return;
    }
    if (_currentPosition == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Waiting for GPS fix — step outside and try again')),
      );
      return;
    }
    // Start trial clock on first tap (no-op if already started).
    final fabUserId = ref.read(authProvider).user?['id'] as String?;
    if (fabUserId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not signed in — please restart the app')),
      );
      return;
    }
    await TrialService.instance.initTrial(fabUserId);
    // Wire the active user ID before starting so scratch inserts and
    // DailyMissions progress calls are never blocked by the null guard.
    RunRecorderService.instance.setActiveUser(fabUserId);
    // Request battery optimization exemption exactly once (AC-15).
    await BatteryOptimizationService.requestOnce();
    HapticFeedback.lightImpact();
    await notifier.start();
    // Fire-and-forget tile pre-download. Run starts regardless.
    TileCacheService.instance.prewarmRunArea(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
    ).listen(null);
  }

  /// Projects [latlngs] to screen Offsets using the current map camera.
  /// Returns an empty list if the map camera is not yet ready.
  List<Offset> _projectToScreen(List<LatLng> latlngs) {
    try {
      final cam = _mapController.camera;
      return latlngs.map((ll) {
        final p = cam.latLngToScreenPoint(ll);
        return Offset(p.x.toDouble(), p.y.toDouble());
      }).toList();
    } catch (e) {
      debugPrint('[MapScreen] _projectToScreen failed: $e');
      return const [];
    }
  }

  /// Builds a closed screen-space Path from [pts].
  Path _makePoly(List<Offset> pts) {
    if (pts.isEmpty) return Path();
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path..close();
  }

  /// Starts the 1500 ms E&U overlay animation after a successful claim.
  /// [priorZonePoints] — screen-space vertex lists for all zones owned by the
  ///   player immediately before the claim.
  /// [newBlockPts] — screen-space vertices of the newly-claimed block.
  /// [routePoints] — last 60 projected GPS trail points for comet + runner.
  /// [tailLengthPx] — comet tail length in screen pixels (100 m / mpp).
  /// [capturedSqm] — polygon area in square meters for the HUD chip.
  /// [outcome] — claim result, used to gate the HUD chip on disputes.
  void _startEUAnimation(
    List<List<Offset>> priorZonePoints,
    List<Offset> newBlockPts,
    Color ownerColor, {
    List<Offset> routePoints = const [],
    double tailLengthPx = 0.0,
    int capturedSqm = 0,
    ClaimOutcome? outcome,
  }) {
    if (!mounted) return;

    // Build prior union Path from all pre-claim owned zones.
    var priorUnion = Path();
    for (final pts in priorZonePoints) {
      if (pts.isNotEmpty) {
        priorUnion = Path.combine(
          PathOperation.union,
          priorUnion,
          _makePoly(pts),
        );
      }
    }

    // Union after = prior + new block.
    final newPoly = _makePoly(newBlockPts);
    final unionAfter = priorZonePoints.isEmpty
        ? newPoly
        : Path.combine(PathOperation.union, priorUnion, newPoly);

    // Shared edges — computed once, before animation starts.
    final shared = sharedEdgePolylines(
      priorBlocks: priorZonePoints,
      newBlock: newBlockPts,
    );

    // Dispose any previous controller before creating a new one.
    _euController?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _euController = ctrl;

    setState(() {
      _euPriorUnion = priorUnion;
      _euNewBlock = newBlockPts;
      _euUnionAfter = unionAfter;
      _euSharedEdges = shared.isEmpty ? null : shared;
      _euAccent = ownerColor;
      _euRoutePoints = routePoints;
      _euTailLengthPx = tailLengthPx;
      _euCapturedSqm = capturedSqm;
      _lastClaimOutcome = outcome;
    });

    ctrl.forward().then((_) {
      if (mounted && _euController == ctrl) {
        setState(() {
          _euAccent = null;
          _lastClaimOutcome = null;
        });
      }
    });
  }

  /// Starts the one-shot capture flash: the claimed area's fill flares to
  /// [IntroContinuity.kBlock1EndFillAlpha] and an expanding ping ring plays
  /// from its centroid, both easing back out over
  /// [IntroContinuity.kCaptureFlashDuration]. Purely additive - the
  /// persistent zone polygon underneath keeps rendering its own
  /// level-derived steady alpha throughout (_buildUnifiedOwnedPolygons is
  /// never touched by this), so the visible fill eases back to the steady
  /// value on its own once the flash's own added alpha decays to zero.
  void _startCaptureFlash(List<Offset> claimedPoly, Color color) {
    if (!mounted || claimedPoly.length < 3) return;
    _captureFlashController?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: IntroContinuity.kCaptureFlashDuration,
    );
    _captureFlashController = ctrl;
    setState(() {
      _captureFlashPoly = claimedPoly;
      _captureFlashColor = color;
    });
    ctrl.forward().then((_) {
      if (mounted && _captureFlashController == ctrl) {
        setState(() {
          _captureFlashController = null;
          _captureFlashPoly = const [];
        });
      }
    });
  }

  /// Handles a silent auto-claim gate rejection (R1) — surfaces a distinct,
  /// non-blocking toast per gate. Never fires on the successful claim path
  /// (enforced upstream in RunRecorderService._scanForAutoClaim).
  void _onGateRejected(
      ({GateRejectionReason reason, Map<String, dynamic> details}) ev) {
    if (!mounted) return;
    final msg = switch (ev.reason) {
      GateRejectionReason.areaFloor => 'Loop too small - min 200 m²',
      GateRejectionReason.diagonalFloor => 'Loop too small - run a wider path',
      GateRejectionReason.compactness => 'Loop too thin - run a wider path',
      GateRejectionReason.pathLength => 'Loop too short - keep running',
      GateRejectionReason.sessionElapsed => 'Loop captured - claims unlock 1 min into a run',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Distinct snackbar copy + haptic pulse per claim outcome (guards against
  /// regressing the disputed-outcome message and gives the core claim moment
  /// feel, not just a default-styled toast). Positioned ahead of
  /// _onAutoClaimOutcome (its only call site) so the `TerritoryResult.disputed`
  /// branch reads immediately after the first `_showResultSnack(` occurrence.
  void _showResultSnack(BuildContext context, ClaimOutcome outcome) {
    final (String msg, Color color, IconData icon) = switch (outcome.result) {
      TerritoryResult.claimed => ('Territory claimed!', kAccent, Icons.flag),
      TerritoryResult.conquered => ('Zone conquered!', kAccent2, Icons.bolt),
      TerritoryResult.disputed => ('Zone disputed!', _kDisputedColor, Icons.warning_amber_rounded),
      TerritoryResult.failed => ('Could not claim zone — try again', kDanger, Icons.error_outline),
    };
    switch (outcome.result) {
      case TerritoryResult.claimed:
      case TerritoryResult.conquered:
        HapticFeedback.heavyImpact();
      case TerritoryResult.disputed:
        HapticFeedback.mediumImpact();
      case TerritoryResult.failed:
        HapticFeedback.lightImpact();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kSurface,
      content: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: TextStyle(color: color))),
        ],
      ),
    ));
  }

  /// Handles an auto-claim outcome emitted by RunRecorderNotifier.autoClaimOutcomes.
  /// Triggers E&U animation, mission hooks, and result snack.
  /// The recorder remains in `recording` state throughout this handler.
  Future<void> _onAutoClaimOutcome(
      ({ClaimOutcome outcome, List<LatLng> polygon}) ev) async {
    if (!mounted) return;
    final outcome = ev.outcome;
    final polygon = ev.polygon;
    final auth = ref.read(authProvider);
    final userId = (auth.user?['id'] as String?) ?? '';
    final city = _currentCity ?? '';

    if (outcome.result == TerritoryResult.failed) {
      ErrorLogService.logClientError(
        provider: '_onAutoClaimOutcome.failed',
        error: 'claim failed: reason=${outcome.reason ?? "unknown"}',
        stackTrace: StackTrace.current,
        retryCount: 0,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Claim failed - try again')),
      );
      return;
    }

    // E&U animation: use the captured polygon (not raw _track).
    if (outcome.result == TerritoryResult.claimed ||
        outcome.result == TerritoryResult.conquered) {
      List<Zone> zonesBefore;
      final zonesAsync = ref.read(zonesProvider(city));
      if (zonesAsync.hasValue) {
        zonesBefore = zonesAsync.value!;
      } else {
        // Cold-start fallback: the provider has not emitted its first snapshot yet -
        // fetch directly instead of silently substituting an empty list.
        try {
          final result = await ref.read(zonesRepositoryProvider).fetchByCity(city);
          zonesBefore = result.valueOr(const <Zone>[]);
        } catch (e, st) {
          ErrorLogService.logClientError(
            provider: '_onAutoClaimOutcome.zonesProvider_fallback_fetch',
            error: e,
            stackTrace: st,
            retryCount: 0,
          );
          zonesBefore = const <Zone>[]; // documented degrade - not a spec violation
        }
        if (!mounted) return; // re-check after the await
      }
      final priorZoneScreenPts = zonesBefore
          .where((z) => z.ownerId == userId)
          .map((z) => _projectToScreen(z.points))
          .where((pts) => pts.isNotEmpty)
          .toList();
      final newBlockScreenPts = _projectToScreen(polygon);
      // Snapshot GPS trail for comet + runner (capped to last 60 points).
      final routePointsCapped = newBlockScreenPts.length > 60
          ? newBlockScreenPts.sublist(newBlockScreenPts.length - 60)
          : newBlockScreenPts;
      // Compute captured area in square meters.
      final areaKm2 = polygonArea(polygon);
      final sqm = (areaKm2.isFinite
              ? (areaKm2 * 1e6).clamp(0.0, 0x7FFFFFFF.toDouble())
              : 0.0)
          .round();
      // Comet tail length: 100 m of trail in screen pixels at current zoom.
      double tailPx = 0.0;
      try {
        final cam = _mapController.camera;
        final mpp = _FogPainter._metersPerPixel(
          cam.center.latitude,
          cam.zoom,
        );
        tailPx = mpp > 0 ? (100.0 / mpp) : 0.0;
      } catch (e) {
        debugPrint('[MapScreen] mpp lookup failed: $e');
      }
      // Determine owner color from profile (default to kAccent).
      final ownerProfile = ref.read(profileGateProvider(userId)).valueOrNull;
      final ownerColor =
          _hexToColor(ownerProfile?['color']?.toString() ?? '#FF7A00');
      _startEUAnimation(
        priorZoneScreenPts,
        newBlockScreenPts,
        ownerColor,
        routePoints: routePointsCapped,
        tailLengthPx: tailPx,
        capturedSqm: sqm,
        outcome: outcome,
      );
      // One-shot capture flash - same success gate, evaluated through the
      // shared predicate so it can never drift from the trigger contract.
      if (_isCaptureFlashTrigger(outcome.result)) {
        _startCaptureFlash(newBlockScreenPts, ownerColor);
      }
    }

    // Mission 1: successful claim triggers celebration overlay + edge fn.
    if (widget.missionStep == MissionStep.mission1Claim &&
        (outcome.result == TerritoryResult.claimed ||
            outcome.result == TerritoryResult.conquered)) {
      unawaited(_completeMission1(context, userId, city));
      return;
    }

    // Mission 2: conquest or dispute on a rival zone completes the attack.
    if (widget.missionStep == MissionStep.mission2Attack &&
        (outcome.result == TerritoryResult.conquered ||
            outcome.result == TerritoryResult.disputed) &&
        outcome.affectedZoneId != null) {
      unawaited(_completeMission2(context, userId, outcome.affectedZoneId!));
      return;
    }

    _showResultSnack(context, outcome);
  }

  /// Calls `complete_first_mission`, updates local SQLite, shows the
  /// celebration overlay, then navigates to FirstAttackBriefingScreen.
  Future<void> _completeMission1(
      BuildContext context, String userId, String city) async {
    // 1. Server stamp + credits. On failure, show error and abort - do not show overlay.
    try {
      final resp = await SupabaseService.instance.supabase.functions
          .invoke('complete_first_mission', body: {});
      final data = resp.data as Map<String, dynamic>?;
      if (data != null) {
        // Write stamp + streak to local SQLite so the gate skips on resume.
        final missionAt = data['first_mission_completed_at'] as String?;
        final streakAt = data['streak_started_at'] as String?;
        try {
          final patch = <String, dynamic>{};
          if (missionAt != null) patch['first_mission_completed_at'] = missionAt;
          if (streakAt != null) patch['streak_started_at'] = streakAt;
          if (patch.isNotEmpty) {
            await DatabaseService.instance.updateProfile(userId, patch);
          }
        } catch (e) {
          debugPrint('[MapScreen] updateProfile stamp failed: $e');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mission save failed - please try again')),
        );
      }
      return;
    }

    // 2. Invalidate providers so _RouteGuard reflects new state.
    ref.invalidate(missionStatusProvider(userId));
    ref.invalidate(profileGateProvider(userId));

    if (!context.mounted) return;

    // 3. Show celebration overlay. On dismiss, spawn bot + navigate to briefing.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => FirstZoneCelebrationOverlay(
        onContinue: () => Navigator.of(context).pop(),
      ),
    );

    if (!context.mounted) return;

    // 4. Spawn bot zone and store result for Gate 5b.
    try {
      final pos = _currentPosition;
      final botZoneId = await BotSpawnerService.instance.checkOrSpawn(
        userId: userId,
        lat: pos?.latitude ?? 39.4699,
        lng: pos?.longitude ?? -0.3763,
        city: city.isEmpty ? 'Valencia' : city,
      );
      ref.read(pendingBotZoneIdProvider.notifier).state = botZoneId;
    } catch (e) {
      debugPrint('[MapScreen] BotSpawnerService failed: $e');
      // pendingBotZoneIdProvider stays null; Gate 5b falls back to ''.
    }

    // Clean up the active recording session before navigating away.
    try {
      await ref.read(runRecorderProvider.notifier).cancel();
    } catch (e) {
      debugPrint('[MapScreen] cancel during mission completion failed: $e');
    }

    // Invalidate mission status — _RouteGuard rebuilds and shows Gate 5b (FirstAttackBriefingScreen).
    ref.invalidate(missionStatusProvider(userId));
  }

  /// Calls `complete_first_attack`, updates local SQLite, then clears the
  /// backstack and navigates to MainShell.
  Future<void> _completeMission2(
      BuildContext context, String userId, String zoneId) async {
    try {
      final resp = await SupabaseService.instance.supabase.functions
          .invoke('complete_first_attack', body: {'zone_id': zoneId});
      final data = resp.data as Map<String, dynamic>?;
      if (data != null) {
        final attackAt = data['first_attack_completed_at'] as String?;
        if (attackAt != null) {
          try {
            await DatabaseService.instance.updateProfile(
              userId,
              {'first_attack_completed_at': attackAt},
            );
          } catch (e) {
            debugPrint('[MapScreen] updateProfile stamp failed: $e');
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mission save failed - please try again')),
        );
      }
      return;
    }

    ref.invalidate(missionStatusProvider(userId));

    // Clean up the active recording session before navigating away.
    try {
      await ref.read(runRecorderProvider.notifier).cancel();
    } catch (e) {
      debugPrint('[MapScreen] cancel during mission completion failed: $e');
    }

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
      (_) => false,
    );
  }

  Widget _buildMap(
    BuildContext context,
    LatLng center,
    List<Zone> zones, {
    required bool showError,
    String city = '',
    String userId = '',
    List<({LatLng point, double radiusM})> fogCenters = const [],
    bool isRecording = false,
  }) {
    // Only render zones whose centroid is inside a revealed fog circle.
    final visibleZones = fogCenters.isEmpty
        ? zones
        : zones.where((z) => _isRevealedByFog(_centroid(z.points), fogCenters)).toList();
    // Computed once per build instead of once per marker (null guard and
    // point: previously each called _simOrRealOwnPosition() separately).
    final LatLng? gpsDotOwnPosition = _simOrRealOwnPosition();
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _kInitialZoom,
            maxZoom: 18,
            minZoom: 10,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            // map-level tap → ray-cast hit-test.
            onTap: (TapPosition tapPos, LatLng latLng) =>
                _handleMapTap(context, latLng, visibleZones, userId),
            // Manual-pan detection during a simulation (SPEC-0144 section 2).
            onMapEvent: _handleMapEvent,
          ),
          children: [
            TileLayer(
              urlTemplate: _kTileUrl,
              subdomains: _kTileSubdomains,
              maxZoom: 19,
              retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
              userAgentPackageName: 'app.runwar.runwar_app',
              tileProvider: CachedNetworkTileProvider(),
            ),
            // zone polygon layers — fog-gated, beam-pulse aesthetic.
            AnimatedBuilder(
              animation: _terrainPulse,
              builder: (_, __) {
                final pulse = _terrainPulse.value;
                return Stack(children: [
                  PolygonLayer(polygons: _buildPolygonsGlow(visibleZones, pulse)),
                  PolygonLayer(polygons: _buildPolygons(visibleZones, pulse)),
                ]);
              },
            ),
            // ZoneLevelBadge + DisputeCountdownLabel markers at polygon centroids.
            MarkerLayer(
              markers: _buildZoneMarkers(visibleZones),
            ),
            // Phase 2 — drop pickup markers.
            Consumer(builder: (context, watchRef, _) {
              final drops = watchRef
                  .watch(activeDropsProvider(city))
                  .valueOrNull ?? [];
              return MarkerLayer(markers: [
                for (final d in drops)
                  Marker(
                    point: LatLng(d.lat, d.lng),
                    width: 36,
                    height: 36,
                    child: DropMarker(
                      drop: d,
                      onTap: (drop) => _handleDropTap(context, watchRef, drop),
                    ),
                  ),
              ]);
            }),
            // Live Supabase presence markers (real players).
            if (SupabaseService.instance.isConnected)
              StreamBuilder<List<PlayerPresence>>(
                stream: RealtimePresenceService.instance.playersStream,
                builder: (_, snap) {
                  final players = snap.data ?? [];
                  if (players.isEmpty) return const SizedBox.shrink();
                  return MarkerLayer(
                    markers: players.map((p) {
                      final history = RealtimePresenceService.instance
                          .historyFor(p.playerId)
                          .map((e) => e.position)
                          .toList(growable: false);
                      return Marker(
                        point: p.position,
                        width: 80,
                        height: 80,
                        child: RivalRunnerMarker(
                          presence: p,
                          myPos: _currentPosition != null
                              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                              : p.position,
                          tailPositions: history,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            // Own trace: local-only. Rendered from RunRecorderService.currentSegmentTrack -
            // the trail from the last claim (or run start) onward, so it stays fully
            // painted until the NEXT claim, then visibly resets to the claim point.
            // Never broadcast via presence - see realtime_presence_service.dart broadcast block.
            // Do not add presence fields for track / polyline data.
            // Live track polyline while recording.
            Consumer(builder: (context, watchRef, _) {
              final recState = watchRef.watch(runRecorderProvider);
              // Watch the version tick so the polyline rebuilds on every GPS append.
              watchRef.watch(runRecorderTrackVersionProvider);
              if (recState != RecorderState.recording) {
                return const SizedBox.shrink();
              }
              final track = RunRecorderService.instance.currentSegmentTrack;
              if (track.length < 2) return const SizedBox.shrink();
              return PolylineLayer(polylines: [
                Polyline(
                  points: track,
                  color: _hexToColor(
                    ref.watch(profileGateProvider(userId)).valueOrNull?['color']?.toString()
                      ?? '#FF7A00',
                  ),
                  strokeWidth: 4,
                ),
              ]);
            }),
            // Own player comet - sits below BeamPulseDot in z-order; visible only while recording.
            // Tail derived from local RunRecorderService.trackSnapshot (NOT presence history).
            Consumer(builder: (context, watchRef, _) {
              final recState = watchRef.watch(runRecorderProvider);
              watchRef.watch(runRecorderTrackVersionProvider);
              if (recState != RecorderState.recording) return const SizedBox.shrink();
              final LatLng? ownPos = _simOrRealOwnPosition();
              if (ownPos == null) return const SizedBox.shrink();
              // Comet tail derived from the same current-segment trail as the
              // persistent polyline above, so the comet never trails behind
              // points from a loop that already claimed and reset.
              final snap = RunRecorderService.instance.currentSegmentTrack;
              final tail = snap.length <= 6
                  ? List<LatLng>.from(snap)
                  : snap.sublist(snap.length - 6);
              final pos = ownPos;
              final positions = tail.isEmpty || tail.last == pos
                  ? tail.isEmpty ? [pos] : tail
                  : [...tail, pos];
              final color = _hexToColor(
                ref.watch(profileGateProvider(userId)).valueOrNull?['color']?.toString()
                  ?? '#FF7A00',
              );
              return MarkerLayer(markers: [
                Marker(
                  point: pos,
                  width: 80,
                  height: 80,
                  child: RunnerComet(
                    positions: positions,
                    accentColor: color,
                    isRecording: true,
                  ),
                ),
              ]);
            }),
            // GPS dot - beam-pulse aesthetic matching intro slides.
            if (gpsDotOwnPosition != null)
              MarkerLayer(markers: [
                Marker(
                  point: gpsDotOwnPosition,
                  width: 60,
                  height: 60,
                  child: Center(
                    child: BeamPulseDot(
                      color: _hexToColor(
                        ref.watch(profileGateProvider(userId)).valueOrNull?['color']?.toString()
                          ?? '#FF7A00',
                      ),
                      size: 11,
                    ),
                  ),
                ),
              ]),
            // CTF flag pins — fog-gated: only render if the pin is revealed.
            if (SupabaseService.instance.isConnected)
              StreamBuilder<List<CtfEvent>>(
                stream: CtfService.instance.activeEvents,
                builder: (_, snap) {
                  final all = snap.data ?? [];
                  final events = fogCenters.isEmpty
                      ? all
                      : all.where((e) => _isRevealedByFog(e.position, fogCenters)).toList();
                  if (events.isEmpty) return const SizedBox.shrink();
                  return MarkerLayer(
                    markers: events.map((e) {
                      return Marker(
                        point: e.position,
                        width: 90,
                        height: 90,
                        child: _CtfFlagMarker(
                          event: e,
                          onTap: () => _showCtfSheet(e),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            // Fog-of-war overlay — drawn last so it sits above all map layers.
            _FogLayer(
              userId: userId,
              city: city,
              currentPosition: _simOrRealOwnPosition(),
            ),
          ],
        ),
        // HUD chip -- visible for animT in [0.0, 0.12] on clean claims only.
        if (_euController != null &&
            _euController!.isAnimating &&
            _lastClaimOutcome != null &&
            !_lastClaimOutcome!.disputeResolved)
          AnimatedBuilder(
            animation: _euController!,
            builder: (context, _) {
              final t = _euController!.value;
              if (t > 0.12) return const SizedBox.shrink();
              final windowT = t / 0.12;
              final opacity = windowT < 0.15
                  ? windowT / 0.15
                  : windowT > 0.85
                      ? (1.0 - windowT) / 0.15
                      : 1.0;
              final chipColor = _euAccent ?? _hexToColor(
                ref.watch(profileGateProvider(userId)).valueOrNull?['color']?.toString()
                  ?? '#FF7A00',
              );
              return Positioned(
                top: 64,
                left: 16,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '+${formatSqm(_euCapturedSqm)} sqm',
                      style: const TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ).copyWith(color: chipColor),
                    ),
                  ),
                ),
              );
            },
          ),
        // Expand & Unify overlay -- rendered above the fog, transitions away in 1500 ms.
        if (_euController != null && _euController!.isAnimating)
          CustomPaint(
            painter: TerritoryOverlayPainter(
              ownerColor: _euAccent ?? _hexToColor(
                ref.watch(profileGateProvider(userId)).valueOrNull?['color']?.toString()
                  ?? '#FF7A00',
              ),
              priorUnion: _euPriorUnion,
              newBlock: _euNewBlock,
              unionAfter: _euUnionAfter,
              sharedEdgesList: _euSharedEdges,
              animT: _euController!.value,
              routePoints: _euRoutePoints,
              tailLengthPx: _euTailLengthPx,
              capturedSqm: _euCapturedSqm,
              repaint: _euController,
            ),
            child: const SizedBox.expand(),
          ),
        // One-shot capture flash -- fill flare + ping ring on the claimed
        // area, easing back to the persistent polygon's own steady alpha.
        if (_captureFlashController != null)
          AnimatedBuilder(
            animation: _captureFlashController!,
            builder: (_, __) => CustomPaint(
              painter: _CaptureFlashPainter(
                polyPts: _captureFlashPoly,
                color: _captureFlashColor,
                t: _captureFlashController!.value,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        // Runners nearby chip — top-left, only visible when rivals within 1 km.
        StreamBuilder<List<PlayerPresence>>(
          stream: RealtimePresenceService.instance.playersStream,
          builder: (_, snap) {
            final players = snap.data ?? [];
            if (players.isEmpty) return const SizedBox.shrink();
            // Count rivals within 1 km.
            final myPos = _currentPosition;
            final nearby = myPos == null
                ? players.length
                : players.where((p) {
                    final dlat = (p.position.latitude - myPos.latitude).abs();
                    final dlng = (p.position.longitude - myPos.longitude).abs();
                    return dlat < 0.009 && dlng < 0.009; // ~1 km
                  }).length;
            if (nearby == 0) return const SizedBox.shrink();
            return Positioned(
              top: 48,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kBg.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kAccent.withValues(alpha: 0.4), width: 1),
                ),
                child: Text(
                  '$nearby RUNNER${nearby == 1 ? '' : 'S'} NEARBY',
                  style: monoStyle(size: 9, color: kAccent),
                ),
              ),
            );
          },
        ),
        // Pre-announce CTF banner — shown when there are pending events to join.
        if (SupabaseService.instance.isConnected)
          StreamBuilder<List<CtfEvent>>(
            stream: CtfService.instance.pendingEvents,
            builder: (_, snap) {
              final pending = snap.data ?? [];
              if (pending.isEmpty) return const SizedBox.shrink();
              final first = pending.first;
              return Positioned(
                top: 48,
                left: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () => _showCtfSheet(first),
                  child: Material(
                    color: const Color(0xFFCC2200).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const Text('🔔', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'CTF incoming in ${first.city} — tap to join',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        // Battery warning banner (AC-16) — visible during active run when
        // battery optimization exemption is not granted.
        if (isRecording)
          FutureBuilder<bool>(
            future: BatteryOptimizationService.isOptimizationActive(),
            builder: (_, snap) {
              if (snap.data != true) return const SizedBox.shrink();
              return const Positioned(
                top: 100,
                left: 16,
                right: 16,
                child: BatteryWarningBanner(),
              );
            },
          ),
        // Daily streak chip + credit balance chip (top-right).
        // Pushed down during mission mode to clear the instruction banner.
        Positioned(
          top: widget.missionStep != null ? 100 : 48,
          right: 16,
          child: Opacity(
            opacity: widget.missionStep != null && !isRecording ? 0.35 : 1.0,
            child: IgnorePointer(
              ignoring: widget.missionStep != null && !isRecording,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreakChip(
                    streak: ref
                        .watch(trialStatusProvider(userId))
                        .valueOrNull
                        ?.streak ?? 0,
                    userId: userId,
                  ),
                  const SizedBox(width: 8),
                  CreditsChip(playerId: userId),
                ],
              ),
            ),
          ),
        ),
        // Phase 2 — superpower inventory strip.
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: SuperpowerInventoryStrip(playerId: userId),
        ),
        // error banner above map; does not block FAB or tiles.
        if (showError)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Material(
              color: kDanger.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Could not load zone data',
                  style: bodyStyle(size: 13, color: kFg),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Builds zone level badge markers and dispute countdown markers.
  List<Marker> _buildZoneMarkers(List<Zone> zones) {
    final markers = <Marker>[];
    for (final z in zones) {
      final centroid = _centroid(z.points);
      // The GestureDetector key ('zone-<id>') is used by integration tests
      // to tap a zone badge directly without relying on flutter_map's
      // coordinate projection (which is unreliable in test viewports).
      final currentUserId =
          (ref.read(authProvider).user?['id'] as String?) ?? '';
      markers.add(Marker(
        point: centroid,
        width: 28,
        height: 28,
        child: GestureDetector(
          key: ValueKey('zone-${z.id}'),
          onTap: () => _handleMapTap(context, centroid, zones, currentUserId),
          child: const SizedBox(width: 28, height: 28),
        ),
      ));
      if (z.status == ZoneStatus.disputed) {
        markers.add(Marker(
          point: LatLng(centroid.latitude + 0.0002, centroid.longitude),
          width: 60,
          height: 24,
          child: DisputeCountdownLabel(zoneId: z.id),
        ));
      }
    }
    // One numeric influence-level badge per rendered holding (contiguity
    // group, same grouping the fill uses) - never one per zone or outline.
    // Non-interactive: the per-zone GestureDetector above already owns taps.
    for (final label in _computeZoneLevelLabels(zones)) {
      markers.add(Marker(
        point: label.anchor,
        width: 28,
        height: 28,
        child: IgnorePointer(child: ZoneLevelBadge(level: label.level)),
      ));
    }
    return markers;
  }

  /// Render-only corner smoothing for a zone outline - see
  /// lib/geo/polygon_smoothing.dart's header for why this must never touch
  /// stored/dispatched geometry. Every Polygon widget built from raw zone
  /// geometry below should route its points through this helper.
  List<LatLng> _smoothedForRender(List<LatLng> ring) =>
      chaikinSmoothClosed(ring, iterations: kZoneRenderSmoothingIterations);

  /// Builds the glow (background) polygon layer — wide low-alpha stroke per zone.
  List<Polygon> _buildPolygonsGlow(List<Zone> zones, double pulse) {
    final out = <Polygon>[];
    for (final z in zones) {
      if (z.status == ZoneStatus.owned) {
        final ownerProfile =
            ref.watch(profileCacheProvider(z.ownerId)).valueOrNull;
        final ownerColor =
            _hexToColor(ownerProfile?['color']?.toString() ?? '#FF7A00');
        final glowAlpha = 0.12 + pulse * 0.14; // 12% → 26%
        out.add(Polygon(
          points: _smoothedForRender(z.points),
          isFilled: false,
          color: Colors.transparent,
          borderColor: ownerColor.withValues(alpha: glowAlpha),
          borderStrokeWidth: 8.0,
          isDotted: false,
        ));
      } else if (z.status == ZoneStatus.disputed) {
        final glowAlpha = 0.08 + pulse * 0.10;
        out.add(Polygon(
          points: _smoothedForRender(z.points),
          isFilled: false,
          color: Colors.transparent,
          borderColor: _kDisputedColor.withValues(alpha: glowAlpha),
          borderStrokeWidth: 6.0,
          isDotted: false,
        ));
      }
    }
    return out;
  }

  /// Builds the main polygon layer.
  /// Owned zones render as one unified shape per same-owner adjacency group
  /// (R3 - no visible internal seam between adjacent same-owner zones).
  /// Disputed zones: amber at fixed 15% fill regardless of influence,
  /// always rendered independently (never part of an owned union group).
  List<Polygon> _buildPolygons(List<Zone> zones, double pulse) {
    final out = <Polygon>[..._buildUnifiedOwnedPolygons(zones, pulse)];
    for (final z in zones) {
      if (z.status == ZoneStatus.disputed) {
        final fillAlpha = 0.10 + pulse * 0.08; // 10% → 18%
        final borderAlpha = 0.50 + 0.30 * pulse;
        out.add(Polygon(
          points: _smoothedForRender(z.points),
          isFilled: true,
          color: _kDisputedColor.withValues(alpha: fillAlpha),
          borderColor: _kDisputedColor.withValues(alpha: borderAlpha),
          borderStrokeWidth: 1.5,
          isDotted: true,
        ));
      }
    }
    return out;
  }

  /// Groups same-owner `owned` zones into one Path.combine union per group
  /// and converts each resulting screen-space contour back into a
  /// flutter_map [Polygon] (the render-time zone union and its single-zone fast path). A group of size 1 skips the union
  /// (fast path, identical output to the pre-R3 per-zone render). A group
  /// whose Path.combine union yields disjoint contours (e.g. a member zone
  /// carries MultiPolygon-shaped source geometry, design.md Section 4/
  /// Consequences #4) emits one flutter_map Polygon per contour — this is
  /// the natural, unmodified behavior of iterating `Path.computeMetrics()`,
  /// no special-casing required.
  List<Polygon> _buildUnifiedOwnedPolygons(List<Zone> zones, double pulse) {
    final out = <Polygon>[];
    final owned = zones.where((z) => z.status == ZoneStatus.owned).toList();
    if (owned.isEmpty) return out;

    final byOwner = <String, List<Zone>>{};
    for (final z in owned) {
      byOwner.putIfAbsent(z.ownerId, () => []).add(z);
    }

    for (final entry in byOwner.entries) {
      final ownerId = entry.key;
      final ownerProfile = ref.watch(profileCacheProvider(ownerId)).valueOrNull;
      final ownerColor = _hexToColor(ownerProfile?['color']?.toString() ?? '#FF7A00');

      final groups = _groupAdjacentZonesImpl(entry.value);
      for (final group in groups) {
        final level = group.map((z) => z.influenceLevel).reduce(math.max).clamp(1, 15);
        final baseAlpha = 0.0633 * level;
        final fillAlpha = baseAlpha * (0.75 + 0.25 * pulse);
        final strokeWidth = 1.0 + (level / 15.0) * 2.0;
        final borderAlpha = 0.60 + 0.40 * pulse;

        if (group.length == 1 && group.first.outlines.length <= 1) {
          out.add(Polygon(
            points: _smoothedForRender(group.first.points),
            isFilled: true,
            color: ownerColor.withValues(alpha: fillAlpha),
            borderColor: ownerColor.withValues(alpha: borderAlpha),
            borderStrokeWidth: strokeWidth,
            isDotted: false,
          ));
          continue;
        }

        // Per-zone fill pass (fill-only, no border of its own): each
        // sub-area keeps its own alpha, derived from its own
        // influenceLevel rather than the group's max, so unequal-level
        // adjacent zones stay visually distinguishable even while they
        // share one outline below.
        for (final z in group) {
          final zLevel = z.influenceLevel.clamp(1, 15);
          final zFillAlpha = 0.0633 * zLevel * (0.75 + 0.25 * pulse);
          for (final outline in z.outlines) {
            out.add(Polygon(
              points: _smoothedForRender(outline),
              isFilled: true,
              color: ownerColor.withValues(alpha: zFillAlpha),
              borderStrokeWidth: 0,
              isDotted: false,
            ));
          }
        }

        // Shared-outline pass (unchanged geometry computation): union every
        // outline of every zone in this group as its own disjoint subpath
        // (design.md Section 4/Consequences #4). A zone whose own geometry
        // is already a MultiPolygon (a Tier-2 server merge) contributes one
        // subpath per member outline, with NO bridging between them;
        // Path.combine(PathOperation.union, ...) composes disjoint contours
        // correctly on its own, so this only requires feeding it every
        // outline instead of assuming one per zone. Only the stroke is
        // emitted here now - fill was moved to the per-zone pass above, so
        // this reads as one continuous edge with no interior seam and no
        // competing per-sub-area border underneath it.
        final cam = _mapController.camera;
        var unified = Path();
        for (final z in group) {
          for (final outline in z.outlines) {
            final screenPts = _projectToScreen(_smoothedForRender(outline));
            if (screenPts.isEmpty) continue;
            unified = Path.combine(PathOperation.union, unified, _makePoly(screenPts));
          }
        }
        for (final metric in unified.computeMetrics()) {
          final contourPts = <LatLng>[];
          const step = 8.0; // px sampling step along the contour
          for (double d = 0; d < metric.length; d += step) {
            final tangent = metric.getTangentForOffset(d);
            if (tangent == null) continue;
            try {
              contourPts.add(cam.pointToLatLng(
                  math.Point(tangent.position.dx, tangent.position.dy)));
            } catch (e, st) {
              // Camera not ready - skip this sample point. Log only the
              // first occurrence per session so a persistently-not-ready
              // camera cannot flood logs (this loop samples every 8px along
              // every unified-owned-zone contour).
              if (!_cameraProjectionErrorLogged) {
                _cameraProjectionErrorLogged = true;
                ErrorLogService.logClientError(
                  provider: '_buildUnifiedOwnedPolygons.camera_projection',
                  error: e,
                  stackTrace: st,
                  retryCount: 0,
                );
              }
            }
          }
          if (contourPts.length >= 3) {
            out.add(Polygon(
              points: contourPts,
              isFilled: false,
              color: Colors.transparent,
              borderColor: ownerColor.withValues(alpha: borderAlpha),
              borderStrokeWidth: strokeWidth,
              isDotted: false,
            ));
          }
        }
      }
    }
    return out;
  }

  /// Handles a map tap — ray-cast to find zone, then show appropriate sheet.
  /// Own zone → info sheet; rival zone → AttackSheet (design.md §4).
  Future<void> _handleMapTap(
    BuildContext context,
    LatLng latLng,
    List<Zone> zones,
    String currentUserId,
  ) async {
    final z = _zoneAtPoint(latLng, zones);
    if (z == null) return;
    if (!context.mounted) return;

    if (z.ownerId == currentUserId) {
      // Own zone: show legacy info sheet.
      final ownerProfile =
          await ref.read(profileCacheProvider(z.ownerId).future);
      if (!context.mounted) return;
      final username = (ownerProfile?['username'] as String?) ?? '';
      final displayName = username.isEmpty ? 'Unknown player' : username;
      _showZoneSheet(context, displayName, z.status.name, z.influenceLevel);
    } else {
      // Rival zone: show AttackSheet (design.md §4).
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: kSurface,
        isScrollControlled: true,
        builder: (_) => AttackSheet(
          zone: z,
          onStartRun: () => _startGuardedRun(context),
        ),
      );
    }
  }

  /// Modal bottom sheet with own-zone details (legacy info sheet).
  void _showZoneSheet(
    BuildContext context,
    String username,
    String status,
    int influence,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(username.toUpperCase(), style: displayStyle(size: 24)),
              const SizedBox(height: 12),
              Text('Status', style: monoStyle()),
              Text(status, style: bodyStyle(size: 16, color: kFg)),
              const SizedBox(height: 12),
              Text('Influence', style: monoStyle()),
              Text('$influence', style: bodyStyle(size: 16, color: kFg)),
            ],
          ),
        ),
      ),
    );
  }

  void _showCtfSheet(CtfEvent event) {
    final minsLeft = event.expiresAt.difference(DateTime.now()).inMinutes;
    final thresholdM = CtfService.instance.captureThresholdM.toInt();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚩 CAPTURE THE FLAG',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace')),
            const SizedBox(height: 8),
            if (event.isActive)
              Text('$minsLeft minutes remaining',
                  style: const TextStyle(color: Colors.white70))
            else
              const Text('Flag drops soon — join now to see it on the map',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center),
            const SizedBox(height: 8),
            if (event.isJoined && event.isActive) ...[
              Text(
                'You\'re racing — capture auto-triggers at ${thresholdM}m',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF4AFF91), fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A2F)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('CLOSE',
                      style: TextStyle(color: Colors.white, fontFamily: 'monospace')),
                ),
              ),
            ] else ...[
              Text(
                event.isJoined
                    ? 'You\'re registered — flag pin will appear when it drops'
                    : 'Join now to see the flag pin when it drops',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (!event.isJoined)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final joined =
                          await CtfService.instance.joinEvent(event.id);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(joined
                            ? 'You joined the CTF! Race to the pin when it drops.'
                            : 'Could not join CTF — try again.'),
                        backgroundColor:
                            joined ? Colors.redAccent : Colors.grey,
                      ));
                    },
                    child: const Text('JOIN CTF',
                        style: TextStyle(
                            color: Colors.white, fontFamily: 'monospace')),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Phase 2 — handles a tap on a drop marker.
  /// Shows a bottom sheet with drop info and a Claim button.
  Future<void> _handleDropTap(
    BuildContext context,
    WidgetRef watchRef,
    Drop drop,
  ) async {
    if (!context.mounted) return;
    final dropTypeLabel = switch (drop.dropType) {
      'influence_crystal' => 'Influence Crystal',
      'credits_cache' => 'Credits Cache',
      'power_core' => 'Power Core',
      _ => drop.dropType,
    };
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dropTypeLabel.toUpperCase(),
                style: displayStyle(size: 22, color: kAccent),
              ),
              const SizedBox(height: 8),
              Text(
                'Move close to claim this drop.',
                style: bodyStyle(size: 14, color: kFgMuted),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(sheetCtx).pop();
                  final pos = _currentPosition;
                  if (pos == null) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No GPS fix — step outside and try again')),
                    );
                    return;
                  }
                  try {
                    final result = await watchRef
                        .read(dropsRepoProvider)
                        .claim(drop.id, pos.latitude, pos.longitude);
                    if (!context.mounted) return;
                    final msg = switch (result) {
                      ClaimDropCash(:final credits) =>
                        'Claimed! +$credits credits',
                      ClaimDropCrystal(:final newInfluence) =>
                        'Crystal absorbed! Influence +$newInfluence',
                      ClaimDropPower(:final grantedPower) =>
                        '$grantedPower charge unlocked!',
                      ClaimDropFailure(:final reason) => switch (reason) {
                          'too_far' => 'You are too far away.',
                          'already_claimed' => 'Already claimed.',
                          'expired' => 'Drop has expired.',
                          'no_zone_nearby' => 'No zone nearby for crystal.',
                          _ => 'Could not claim: $reason',
                        },
                    };
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                },
                child: const Text('CLAIM'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── File-private helpers ─────────────────────────────────────────────────────

/// Ray-casting point-in-polygon test. Returns first matching Zone or null.
/// Used by MapOptions.onTap (no GestureDetector on polygons).
Zone? _zoneAtPoint(LatLng tap, List<Zone> zones) {
  for (final z in zones) {
    if (pointInPolygon(tap, z.points)) return z;
  }
  return null;
}

/// Parses '#RRGGBB' or '#AARRGGBB' hex color strings.
/// Returns kAccent on any parse failure.
Color _hexToColor(String hex) {
  try {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return kAccent;
  }
}

// ── Render-time zone adjacency grouping (R3) ────────────────────────────────
//
// Groups same-owner OWNED zones that are actually contiguous (edge-to-edge
// distance within the threshold below) so _buildUnifiedOwnedPolygons can
// render them as one Path.combine union with no visible internal seam.
//
// The threshold intentionally matches kProximityTriggerM
// (lib/utils/runwar_constants.dart) - the app's existing loop-closure
// proximity-trigger radius - rather than the server merge's separate 5 m
// jitter epsilon (design.md Section 4's Tier-1/Tier-2 boundary). A gap up to
// this size is still plausibly the same continuous claim run (the server's
// Tier-2 rule reaches the same one-identity conclusion at this radius), so
// the steady-state render shows it as one shape even though the
// stored geometry for a Tier-2 pair remains an unbridged MultiPolygon with
// no filled area added between the two outlines - see
// _buildUnifiedOwnedPolygons's per-outline subpath handling below. Disputed
// zones are never considered here (filtered out before grouping) so they
// can never bridge two owned zones into one render group (the persistent render union invariant).
const double _kRenderUnionEpsilonM = kProximityTriggerM;

/// Bounding box for a polygon ring, in lat/lng degrees.
({double minLat, double maxLat, double minLng, double maxLng}) _bboxOfPoints(
    List<LatLng> pts) {
  var nLat = pts.first.latitude, xLat = pts.first.latitude;
  var nLng = pts.first.longitude, xLng = pts.first.longitude;
  for (final p in pts) {
    if (p.latitude < nLat) nLat = p.latitude;
    if (p.latitude > xLat) xLat = p.latitude;
    if (p.longitude < nLng) nLng = p.longitude;
    if (p.longitude > xLng) xLng = p.longitude;
  }
  return (minLat: nLat, maxLat: xLat, minLng: nLng, maxLng: xLng);
}

/// Approximate edge-to-edge gap in metres between two zone bounding boxes.
/// Zero when the boxes overlap or touch on a given axis. Good enough as a
/// render-time contiguity pre-filter (not used for any stored geometry).
double _bboxGapM(
  ({double minLat, double maxLat, double minLng, double maxLng}) a,
  ({double minLat, double maxLat, double minLng, double maxLng}) b,
) {
  final latGapDeg = a.maxLat < b.minLat
      ? b.minLat - a.maxLat
      : (b.maxLat < a.minLat ? a.minLat - b.maxLat : 0.0);
  final lngGapDeg = a.maxLng < b.minLng
      ? b.minLng - a.maxLng
      : (b.maxLng < a.minLng ? a.minLng - b.maxLng : 0.0);
  final midLat =
      (a.minLat + a.maxLat + b.minLat + b.maxLat) / 4 * math.pi / 180;
  final latGapM = latGapDeg * 110540.0;
  final lngGapM = lngGapDeg * 111320.0 * math.cos(midLat);
  return math.sqrt(latGapM * latGapM + lngGapM * lngGapM);
}

/// Union-find grouping of the OWNED subset of [zones] by real contiguity
/// (touching, or within [_kRenderUnionEpsilonM]). Disputed zones are
/// filtered out before grouping starts, so they can never join a group or
/// bridge two owned zones together (the persistent render union invariant, and the disputed-zone exclusion edge case).
List<List<Zone>> _groupAdjacentZonesImpl(List<Zone> zones) {
  final owned = zones.where((z) => z.status == ZoneStatus.owned).toList();
  if (owned.isEmpty) return const [];

  // Bbox spans EVERY outline of a zone (not just the first) so a
  // MultiPolygon-shaped zone's adjacency test considers its full extent,
  // not merely its first member outline.
  final bboxes =
      owned.map((z) => _bboxOfPoints(z.outlines.expand((o) => o).toList())).toList();
  final parent = List<int>.generate(owned.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  for (var i = 0; i < owned.length; i++) {
    for (var j = i + 1; j < owned.length; j++) {
      if (_bboxGapM(bboxes[i], bboxes[j]) <= _kRenderUnionEpsilonM) {
        union(i, j);
      }
    }
  }

  final groups = <int, List<Zone>>{};
  for (var i = 0; i < owned.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(owned[i]);
  }
  return groups.values.toList();
}

/// Test-only seam (mirrors run_recorder_service.dart's `...ForTesting`
/// convention) so widget/unit tests can assert the adjacency grouping
/// independent of rendering (design.md Section 5, the persistent render union and its disputed-zone exclusion edge case).
@visibleForTesting
List<List<Zone>> groupAdjacentZonesForTesting(List<Zone> zones) =>
    _groupAdjacentZonesImpl(zones);

// ── Fog visibility helpers ───────────────────────────────────────────────────

/// Returns the centroid of a polygon ring (average of all vertices).
LatLng _centroid(List<LatLng> pts) {
  if (pts.isEmpty) return const LatLng(0, 0);
  final lat = pts.fold(0.0, (s, p) => s + p.latitude) / pts.length;
  final lng = pts.fold(0.0, (s, p) => s + p.longitude) / pts.length;
  return LatLng(lat, lng);
}

// ── Capture flash trigger + per-holding level labels ────────────────────────

/// True when [result] represents a real territorial gain (a first claim or
/// a successful conquest) - the only outcomes that play the one-shot
/// capture flash. A dispute has not resolved into a gain yet, and a failed
/// claim landed nothing, so neither ever flashes.
bool _isCaptureFlashTrigger(TerritoryResult result) =>
    result == TerritoryResult.claimed || result == TerritoryResult.conquered;

/// Test-only seam for [_isCaptureFlashTrigger] (mirrors the `...ForTesting`
/// convention used by [groupAdjacentZonesForTesting]).
@visibleForTesting
bool isCaptureFlashTriggerForTesting(TerritoryResult result) =>
    _isCaptureFlashTrigger(result);

/// One rendered holding's numeric influence-level label: an anchor point
/// and the level to display there.
typedef ZoneLevelLabel = ({LatLng anchor, int level});

/// The group's displayed influence level: the max across its member zones,
/// clamped 1..15 - identical to the reduction _buildUnifiedOwnedPolygons
/// performs for the fill alpha (map_screen.dart's own steady-state formula),
/// extracted here so the fill and the label always agree on the same number.
int _groupInfluenceLevel(List<Zone> group) =>
    group.map((z) => z.influenceLevel).reduce(math.max).clamp(1, 15);

/// Test-only seam for [_groupInfluenceLevel].
@visibleForTesting
int groupInfluenceLevelForTesting(List<Zone> group) =>
    _groupInfluenceLevel(group);

/// Anchor point for a group's level label. Tries the group-wide average
/// centroid first (correct for the common convex / single-outline case); if
/// that lands outside every member outline (a concave or MultiPolygon-shaped
/// group), falls back to each outline's own local centroid in turn, then
/// finally to the largest outline's own centroid even if it still fails the
/// containment check - a label anchor is always returned, never left
/// unresolved.
LatLng _groupLabelAnchor(List<Zone> group) {
  final outlines = <List<LatLng>>[
    for (final z in group)
      ...(z.outlines.isNotEmpty ? z.outlines : [z.points]),
  ];
  if (outlines.isEmpty) return const LatLng(0, 0);

  final groupCentroid = _centroid(outlines.expand((o) => o).toList());
  for (final outline in outlines) {
    if (pointInPolygon(groupCentroid, outline)) return groupCentroid;
  }

  List<LatLng>? largest;
  for (final outline in outlines) {
    if (largest == null || outline.length > largest.length) largest = outline;
    final localCentroid = _centroid(outline);
    if (pointInPolygon(localCentroid, outline)) return localCentroid;
  }
  return _centroid(largest!);
}

/// Test-only seam for [_groupLabelAnchor].
@visibleForTesting
LatLng groupLabelAnchorForTesting(List<Zone> group) => _groupLabelAnchor(group);

/// One label per rendered holding: groups owned zones the same way the fill
/// does (same-owner + [_groupAdjacentZonesImpl]) and returns one
/// (anchor, level) pair per group - never one per zone and never one per
/// outline within a group. Disputed zones are never labeled (they are not a
/// held holding).
List<ZoneLevelLabel> _computeZoneLevelLabels(List<Zone> zones) {
  final owned = zones.where((z) => z.status == ZoneStatus.owned).toList();
  final byOwner = <String, List<Zone>>{};
  for (final z in owned) {
    byOwner.putIfAbsent(z.ownerId, () => []).add(z);
  }
  final out = <ZoneLevelLabel>[];
  for (final entry in byOwner.entries) {
    for (final group in _groupAdjacentZonesImpl(entry.value)) {
      out.add((
        anchor: _groupLabelAnchor(group),
        level: _groupInfluenceLevel(group),
      ));
    }
  }
  return out;
}

/// Test-only seam for [_computeZoneLevelLabels].
@visibleForTesting
List<ZoneLevelLabel> zoneLevelLabelsForTesting(List<Zone> zones) =>
    _computeZoneLevelLabels(zones);

/// Screen-space centroid (average of vertices) - the capture flash
/// painter's own analogue of [_centroid], operating on [Offset] instead of
/// [LatLng].
Offset _offsetCentroid(List<Offset> pts) {
  if (pts.isEmpty) return Offset.zero;
  final dx = pts.fold(0.0, (s, p) => s + p.dx) / pts.length;
  final dy = pts.fold(0.0, (s, p) => s + p.dy) / pts.length;
  return Offset(dx, dy);
}

/// Paints the one-shot capture flash: the claimed polygon's fill flares to
/// [IntroContinuity.kBlock1EndFillAlpha] and a ping ring expands from its
/// centroid, both easing out to zero over the controller's duration. Purely
/// additive over the persistent PolygonLayer fill - never mutates the
/// steady level-derived alpha _buildUnifiedOwnedPolygons computes.
class _CaptureFlashPainter extends CustomPainter {
  const _CaptureFlashPainter({
    required this.polyPts,
    required this.color,
    required this.t,
  });

  /// Screen-space vertices of the claimed area.
  final List<Offset> polyPts;
  final Color color;

  /// Animation progress in [0.0, 1.0] over the flash duration.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (polyPts.length < 3) return;
    final eased = Curves.easeOut.transform(t.clamp(0.0, 1.0));

    final flashAlpha = IntroContinuity.kBlock1EndFillAlpha * (1.0 - eased);
    if (flashAlpha > 0.001) {
      final path = Path()..addPolygon(polyPts, true);
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: flashAlpha),
      );
    }

    final ringAlpha =
        ((1.0 - eased) * IntroContinuity.kCaptureFlashRingPeakAlpha)
            .clamp(0.0, 1.0);
    if (ringAlpha > 0.001) {
      final centroid = _offsetCentroid(polyPts);
      final radius = eased * IntroContinuity.kCaptureFlashRingMaxRadius;
      canvas.drawCircle(
        centroid,
        radius,
        Paint()
          ..color = color.withValues(alpha: ringAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(_CaptureFlashPainter old) =>
      old.t != t || old.polyPts != polyPts || old.color != color;
}

/// Haversine distance in metres between two lat/lng points.
double _haversineM(LatLng a, LatLng b) {
  const R = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(a.latitude * math.pi / 180) *
          math.cos(b.latitude * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * R * math.asin(math.sqrt(s));
}

/// True if [point] falls inside at least one revealed fog circle.
/// If [centers] is empty (no runs, no GPS) every point is hidden — fail-closed.
bool _isRevealedByFog(
  LatLng point,
  List<({LatLng point, double radiusM})> centers,
) {
  for (final c in centers) {
    if (_haversineM(point, c.point) <= c.radiusM) return true;
  }
  return false;
}

// ── Countdown badge ───────────────────────────────────────────────────────────

// ── Fog-of-war overlay ────────────────────────────────────────────────────────

/// Map layer drawn on top of all other layers.
/// Covers the entire viewport with a dark overlay. Visibility holes are punched:
///   • Along the player's past run tracks (400 m radius per sampled point).
///   • At the live GPS position (500 m radius).
/// Full fog is shown until the player's first run or GPS fix.
class _FogLayer extends ConsumerWidget {
  final String userId;
  final String city;
  final LatLng? currentPosition;

  const _FogLayer({
    required this.userId,
    required this.city,
    required this.currentPosition,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camera = MapCamera.of(context);
    final runPoints = ref
        .watch(userRunPointsProvider((userId: userId, city: city)))
        .valueOrNull ?? const [];

    final centers = <({LatLng point, double radiusM})>[];

    // Past run tracks → 5 km visibility around each sampled position.
    for (final pt in runPoints) {
      centers.add((point: pt, radiusM: 5000));
    }

    // Live GPS → 1 km immediate visibility even before any run is saved.
    if (currentPosition != null) {
      centers.add((point: currentPosition!, radiusM: 1000));
    }

    // Cap for performance (200 holes is plenty for any realistic run history).
    final capped = centers.length > 200 ? centers.sublist(0, 200) : centers;

    return CustomPaint(
      painter: _FogPainter(camera: camera, centers: capped),
      child: const SizedBox.expand(),
    );
  }
}

class _FogPainter extends CustomPainter {
  final MapCamera camera;
  final List<({LatLng point, double radiusM})> centers;

  const _FogPainter({required this.camera, required this.centers});

  static double _metersPerPixel(double latDeg, double zoom) =>
      156543.03392 * math.cos(latDeg * math.pi / 180.0) / math.pow(2, zoom);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    // Dark fog covering the entire map.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xEE08060F) // ~93% opacity
        ..style = PaintingStyle.fill,
    );

    // Punch circular holes using dstOut blend mode.
    for (final c in centers) {
      final screenPt = camera.latLngToScreenPoint(c.point);
      final mpp = _metersPerPixel(c.point.latitude, camera.zoom);
      final radiusPx = (c.radiusM / mpp).clamp(20.0, 4000.0);
      final center = Offset(screenPt.x.toDouble(), screenPt.y.toDouble());

      // Feathered gradient so the edge blends softly (300 m blend zone).
      final blendFraction = (1 - (300 / c.radiusM).clamp(0.0, 0.35));
      final gradient = RadialGradient(
        colors: const [Colors.black, Colors.black, Colors.transparent],
        stops: [0.0, blendFraction, 1.0],
      );
      canvas.drawCircle(
        center,
        radiusPx,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = gradient.createShader(
            Rect.fromCircle(center: center, radius: radiusPx),
          ),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FogPainter old) => true;
}

// ── CTF flag marker — animated beams + pulsing ring ──────────────────────────

class _CtfFlagMarker extends StatefulWidget {
  const _CtfFlagMarker({required this.event, required this.onTap});
  final CtfEvent event;
  final VoidCallback onTap;

  @override
  State<_CtfFlagMarker> createState() => _CtfFlagMarkerState();
}

class _CtfFlagMarkerState extends State<_CtfFlagMarker>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minsLeft = widget.event.expiresAt.difference(DateTime.now()).inMinutes;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 90,
        height: 90,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rotating beams layer
            AnimatedBuilder(
              animation: _rotation,
              builder: (_, __) => Transform.rotate(
                angle: _rotation.value * 2 * math.pi,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => CustomPaint(
                    size: const Size(90, 90),
                    painter: _BeamsPainter(intensity: _pulse.value),
                  ),
                ),
              ),
            ),
            // Pulsing outer ring
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 36 + 10 * _pulse.value,
                height: 36 + 10 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFF3B3B)
                        .withValues(alpha: 0.7 - 0.5 * _pulse.value),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            // Flag + timer
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🚩', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${minsLeft}m',
                    style: const TextStyle(
                      color: Color(0xFFFF3B3B),
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BeamsPainter extends CustomPainter {
  const _BeamsPainter({required this.intensity});
  final double intensity; // 0..1 from pulse animation

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const innerR = 20.0;
    const outerR = 42.0;
    const beams = 8;

    final paint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < beams; i++) {
      final angle = (2 * math.pi * i) / beams;
      // Alternate beams slightly different length for visual interest
      final end = outerR - (i.isOdd ? 6.0 : 0.0);
      paint.color = const Color(0xFFFF3B3B)
          .withValues(alpha: (0.3 + 0.5 * intensity) * (i.isEven ? 1.0 : 0.6));
      canvas.drawLine(
        Offset(center.dx + math.cos(angle) * innerR,
            center.dy + math.sin(angle) * innerR),
        Offset(center.dx + math.cos(angle) * end,
            center.dy + math.sin(angle) * end),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BeamsPainter old) => old.intensity != intensity;
}
