import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
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
import '../providers/run_recorder_provider.dart';
import '../providers/app_config_provider.dart';
import '../services/run_recorder_service.dart';
import '../services/battery_optimization_service.dart';
import '../widgets/battery_warning_banner.dart';
import '../widgets/territory_overlay_painter.dart';
import '../widgets/intro/intro_helpers.dart' show sharedEdgePolylines, formatSqm;
import '../geo/lasso.dart' show polygonArea;
import '../services/ctf_service.dart';
import '../services/realtime_presence_service.dart';
import '../services/superpower_service.dart';
import '../services/supabase_service.dart';
import '../services/territory_service.dart';
import '../services/tile_cache_service.dart';
import '../services/trial_service.dart';
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
  late final AnimationController _terrainPulse;

  // Cached city name updated on every build; read at transition time by the
  // stream handler so the auto-claim handler always receives the current value.
  String? _currentCity;
  StreamSubscription<({ClaimOutcome outcome, List<LatLng> polygon})>? _autoClaimSub;

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

  Future<void> _initLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always) {
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
    // denied / deniedForever / unableToDetermine → no stream, no dot, no SnackBar
  }

  @override
  void dispose() {
    _autoClaimSub?.cancel();
    SuperpowerService.instance.onShieldEarned = null;
    _terrainPulse.dispose();
    _euController?.dispose();
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
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: Text('No city joined yet')),
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

    return Scaffold(
      backgroundColor: kBg,
      body: body,
      floatingActionButton: _buildFab(context, city),
    );
  }

  Widget _buildFab(BuildContext context, String city) {
    final recState = ref.watch(runRecorderProvider);
    final isRecording = recState == RecorderState.recording;
    final hasGps = _currentPosition != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Locate button — centres map on player's GPS position ──
        FloatingActionButton.small(
          heroTag: 'locate',
          backgroundColor: kSurface,
          foregroundColor: hasGps ? kFg : kFgMuted,
          onPressed: hasGps
              ? () => _mapController.move(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                    _kInitialZoom,
                  )
              : null,
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
      // Start trial clock on first FAB tap (no-op if already started).
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
      await notifier.start();
      // Fire-and-forget tile pre-download. Run starts regardless.
      TileCacheService.instance.prewarmRunArea(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      ).listen(null);
    } else if (s == RecorderState.recording) {
      // Tap always ends the session unconditionally. No validity gates.
      await notifier.stop();
    }
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

  /// Handles an auto-claim outcome emitted by RunRecorderNotifier.autoClaimOutcomes.
  /// Triggers E&U animation, mission hooks, and result snack.
  /// The recorder remains in `recording` state throughout this handler.
  void _onAutoClaimOutcome(
      ({ClaimOutcome outcome, List<LatLng> polygon}) ev) {
    if (!mounted) return;
    final outcome = ev.outcome;
    final polygon = ev.polygon;
    final auth = ref.read(authProvider);
    final userId = (auth.user?['id'] as String?) ?? '';
    final city = _currentCity ?? '';

    if (outcome.result == TerritoryResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Claim failed - try again')),
      );
      return;
    }

    // E&U animation: use the captured polygon (not raw _track).
    if (outcome.result == TerritoryResult.claimed ||
        outcome.result == TerritoryResult.conquered) {
      final zonesBefore = ref.read(zonesProvider(city)).valueOrNull ?? const [];
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

  void _showResultSnack(BuildContext context, ClaimOutcome outcome) {
    final msg = switch (outcome.result) {
      TerritoryResult.claimed => 'Territory claimed!',
      TerritoryResult.conquered => 'Zone conquered!',
      TerritoryResult.disputed => 'Zone disputed!',
      TerritoryResult.failed => 'Could not claim zone — try again',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            // Own trace: local-only. Rendered from RunRecorderService.trackSnapshot.
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
              final track = RunRecorderService.instance.trackSnapshot;
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
              if (_currentPosition == null) return const SizedBox.shrink();
              final snap = RunRecorderService.instance.trackSnapshot;
              final tail = snap.length <= 6
                  ? List<LatLng>.from(snap)
                  : snap.sublist(snap.length - 6);
              final pos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
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
            // GPS dot — beam-pulse aesthetic matching intro slides.
            if (_currentPosition != null)
              MarkerLayer(markers: [
                Marker(
                  point: LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  ),
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
              currentPosition: _currentPosition,
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
    return markers;
  }

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
          points: z.points,
          isFilled: false,
          color: Colors.transparent,
          borderColor: ownerColor.withValues(alpha: glowAlpha),
          borderStrokeWidth: 8.0,
          isDotted: false,
        ));
      } else if (z.status == ZoneStatus.disputed) {
        final glowAlpha = 0.08 + pulse * 0.10;
        out.add(Polygon(
          points: z.points,
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
  /// Owned zones: fill opacity and stroke width scale with influence (1–15).
  /// Disputed zones: amber at fixed 15% fill regardless of influence.
  List<Polygon> _buildPolygons(List<Zone> zones, double pulse) {
    final out = <Polygon>[];
    for (final z in zones) {
      if (z.status == ZoneStatus.owned) {
        final ownerProfile =
            ref.watch(profileCacheProvider(z.ownerId)).valueOrNull;
        final ownerColor =
            _hexToColor(ownerProfile?['color']?.toString() ?? '#FF7A00');
        final level = z.influenceLevel.clamp(1, 15);
        // Fill breathes between 75% and 100% of base alpha (intro-slide glow).
        final baseAlpha = 0.0633 * level;
        final fillAlpha = baseAlpha * (0.75 + 0.25 * pulse);
        final strokeWidth = 1.0 + (level / 15.0) * 2.0;
        final borderAlpha = 0.60 + 0.40 * pulse; // stroke pulses 60% → 100%
        out.add(Polygon(
          points: z.points,
          isFilled: true,
          color: ownerColor.withValues(alpha: fillAlpha),
          borderColor: ownerColor.withValues(alpha: borderAlpha),
          borderStrokeWidth: strokeWidth,
          isDotted: false,
        ));
      } else if (z.status == ZoneStatus.disputed) {
        final fillAlpha = 0.10 + pulse * 0.08; // 10% → 18%
        final borderAlpha = 0.50 + 0.30 * pulse;
        out.add(Polygon(
          points: z.points,
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
        builder: (_) => AttackSheet(zone: z),
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
    if (_pointInRing(tap, z.points)) return z;
  }
  return null;
}

bool _pointInRing(LatLng p, List<LatLng> ring) {
  bool inside = false;
  final n = ring.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final xi = ring[i].longitude;
    final yi = ring[i].latitude;
    final xj = ring[j].longitude;
    final yj = ring[j].latitude;
    final dy = yj - yi;
    final intersect = ((yi > p.latitude) != (yj > p.latitude)) &&
        (p.longitude <
            (xj - xi) * (p.latitude - yi) / (dy == 0 ? 1e-12 : dy) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
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

// ── Fog visibility helpers ───────────────────────────────────────────────────

/// Returns the centroid of a polygon ring (average of all vertices).
LatLng _centroid(List<LatLng> pts) {
  if (pts.isEmpty) return const LatLng(0, 0);
  final lat = pts.fold(0.0, (s, p) => s + p.latitude) / pts.length;
  final lng = pts.fold(0.0, (s, p) => s + p.longitude) / pts.length;
  return LatLng(lat, lng);
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
  final Position? currentPosition;

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
      centers.add((
        point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        radiusM: 1000,
      ));
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
