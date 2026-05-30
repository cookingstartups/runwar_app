import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/runs_provider.dart';
import '../providers/zones_provider.dart';
import '../providers/run_recorder_provider.dart';
import '../services/run_recorder_service.dart';
import '../services/ctf_service.dart';
import '../services/realtime_presence_service.dart';
import '../services/superpower_service.dart';
import '../services/supabase_service.dart';
import '../services/territory_service.dart';
import '../theme.dart';

// ── City center lookup ───────────────────────────────────────────────────────

const Map<String, LatLng> _kCityCenter = {
  'Valencia': LatLng(39.4699, -0.3763),
  'Madrid': LatLng(40.4168, -3.7038),
};
const LatLng _kDefaultCenter = LatLng(40.4168, -3.7038); // Madrid
const double _kInitialZoom = 16.0;

// ── Tile configuration ────────────────────────────────────────────────────────

const String _kTileUrl =
    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
const List<String> _kTileSubdomains = ['a', 'b', 'c', 'd'];

// ── Zone styling ──────────────────────────────────────────────────────────────

const Color _kGpsDotColor = Color(0xFF4A9EFF); // blue GPS dot (brief spec)
const Color _kDisputedColor = Color(0xFFC8973A); // amber for disputed zones

// ── Parsed zone data model (§5.1) ────────────────────────────────────────────

class _ParsedZone {
  const _ParsedZone({
    required this.id,
    required this.ownerId,
    required this.status,
    required this.influence,
    required this.points,
  });
  final String id;
  final String ownerId;
  final String status; // 'owned' | 'disputed'
  final int influence;
  final List<LatLng> points;
}

// ── MapScreen widget ─────────────────────────────────────────────────────────

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _posSub;
  Position? _currentPosition;
  bool _centeredOnGps = false;
  @override
  void initState() {
    super.initState();
    SuperpowerService.instance.onShieldEarned = (grant) {
      if (mounted) _showShieldEarnedModal(grant);
    };
    // request permission once at mount; use addPostFrameCallback
    // so the OS dialog appears after the first frame paints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      CtfService.instance.refresh();
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
    SuperpowerService.instance.onShieldEarned = null;
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

  /// Resolves the user's city and corresponding map center from the profile.
  ({String city, LatLng center}) _resolveCenter() {
    final auth = ref.watch(authProvider);
    final userId = auth.user?['id'] as String?;
    if (userId == null) return (city: '', center: _kDefaultCenter);
    final p = ref.watch(profileGateProvider(userId)).valueOrNull;
    final city = (p?['city'] as String?) ?? '';
    return (city: city, center: _kCityCenter[city] ?? _kDefaultCenter);
  }

  @override
  Widget build(BuildContext context) {
    final (:city, :center) = _resolveCenter();
    final auth = ref.watch(authProvider);
    final userId = (auth.user?['id'] as String?) ?? '';

    // Show spinner while profile is resolving.
    if (city.isEmpty) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(
          child: CircularProgressIndicator(color: kAccent, strokeWidth: 2),
        ),
      );
    }

    // Auto-claim immediately when lasso closes — no button press required.
    ref.listen<RecorderState>(runRecorderProvider, (prev, next) {
      if (next == RecorderState.awaitingClaim &&
          prev != RecorderState.awaitingClaim &&
          context.mounted) {
        _autoClaim(context, city);
      }
    });

    final zonesAsync = ref.watch(zonesProvider(city));

    final mapBody = zonesAsync.when(
      loading: () => _buildMap(context, center, const [],
          showError: false, city: city, userId: userId),
      error: (e, _) => _buildMap(context, center, const [],
          showError: true, city: city, userId: userId),
      data: (rows) => _buildMap(context, center, _parseEmission(rows),
          showError: false, city: city, userId: userId),
    );

    return Scaffold(
      backgroundColor: kBg,
      body: mapBody,
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
              ? () => ref.read(runRecorderProvider.notifier).forceClose()
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
      await notifier.start();
    } else if (s == RecorderState.recording) {
      final result = await notifier.stop();
      if (!context.mounted) return;
      if (result == LoopResult.invalid) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Loop too short or not closed — try again'),
        ));
      }
      // LoopResult.valid → awaitingClaim state triggers the bottom sheet
      // via the ref.listen handler in build().
    }
    // s == awaitingClaim → sheet is isDismissible:false; tap ignored.
  }

  Future<void> _autoClaim(BuildContext context, String city) async {
    final auth = ref.read(authProvider);
    final userId = auth.user?['id'] as String?;
    if (userId == null) {
      ref.read(runRecorderProvider.notifier).discard();
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Claiming territory…'), duration: Duration(seconds: 10)),
    );
    final outcome = await ref
        .read(runRecorderProvider.notifier)
        .confirmClaim(userId, city);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _showResultSnack(context, outcome);
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
    List<_ParsedZone> parsed, {
    required bool showError,
    String city = '',
    String userId = '',
  }) {
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
                _handleMapTap(context, latLng, parsed),
          ),
          children: [
            TileLayer(
              urlTemplate: _kTileUrl,
              subdomains: _kTileSubdomains,
              maxZoom: 19,
              retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
              userAgentPackageName: 'app.runwar.runwar_app',
            ),
            // zone polygon layer.
            PolygonLayer(polygons: _buildPolygons(parsed)),
            // Live Supabase presence markers (real players).
            if (SupabaseService.instance.isConnected)
              StreamBuilder<List<PlayerPresence>>(
                stream: RealtimePresenceService.instance.playersStream,
                builder: (_, snap) {
                  final players = snap.data ?? [];
                  if (players.isEmpty) return const SizedBox.shrink();
                  return MarkerLayer(
                    markers: players.map((p) {
                      final color = _hexToColor(p.color);
                      return Marker(
                        point: p.position,
                        width: 70,
                        height: 40,
                        child: Column(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              p.displayName,
                              style: TextStyle(
                                color: color,
                                fontSize: 7,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
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
                  color: kAccent,
                  strokeWidth: 4,
                ),
              ]);
            }),
            // GPS dot rendered only when position is available.
            if (_currentPosition != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  ),
                  radius: 8,
                  useRadiusInMeter: false,
                  color: _kGpsDotColor,
                  borderColor: kFg,
                  borderStrokeWidth: 2,
                ),
              ]),
            // CTF flag pins from active Supabase events.
            if (SupabaseService.instance.isConnected)
              StreamBuilder<List<CtfEvent>>(
                stream: CtfService.instance.activeEvents,
                builder: (_, snap) {
                  final events = snap.data ?? [];
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
                    color: const Color(0xFFCC2200).withOpacity(0.92),
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

  /// Builds the list of Polygon widgets for the PolygonLayer.
  /// Owned zones: fill opacity and stroke width scale with influence (1–15).
  /// Disputed zones: amber at fixed 15% fill regardless of influence.
  List<Polygon> _buildPolygons(List<_ParsedZone> parsed) {
    final out = <Polygon>[];
    for (final z in parsed) {
      if (z.status == 'owned') {
        final ownerProfile =
            ref.watch(profileCacheProvider(z.ownerId)).valueOrNull;
        final ownerColor =
            _hexToColor((ownerProfile?['color'] as String?) ?? '#FF7A00');
        final level = z.influence.clamp(1, 15);
        final fillAlpha = 0.0633 * level;        // 6.33% … 95%
        final strokeWidth = 1.0 + (level / 15.0) * 2.0;
        out.add(Polygon(
          points: z.points,
          isFilled: true,
          color: ownerColor.withValues(alpha: fillAlpha),
          borderColor: ownerColor,
          borderStrokeWidth: strokeWidth,
          isDotted: false,
        ));
      } else if (z.status == 'disputed') {
        out.add(Polygon(
          points: z.points,
          isFilled: true,
          color: _kDisputedColor.withValues(alpha: 0.15),
          borderColor: _kDisputedColor,
          borderStrokeWidth: 1.5,
          isDotted: true,
        ));
      }
    }
    return out;
  }

  /// Handles a map tap — ray-cast to find zone, then show bottom sheet.
  Future<void> _handleMapTap(
    BuildContext context,
    LatLng latLng,
    List<_ParsedZone> parsed,
  ) async {
    final z = _zoneAtPoint(latLng, parsed);
    if (z == null) return;
    // Fetch owner profile at tap time; cached if already resolved for color.
    final ownerProfile =
        await ref.read(profileCacheProvider(z.ownerId).future);
    if (!context.mounted) return;
    final username = (ownerProfile?['username'] as String?) ?? '';
    final displayName = username.isEmpty ? 'Unknown player' : username;
    _showZoneSheet(context, displayName, z.status, z.influence);
  }

  /// Modal bottom sheet with zone details.
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
}

// ── File-private helpers ─────────────────────────────────────────────────────

/// Parses a GeoJSON Polygon string into an outer ring of LatLng points.
/// Returns null on any malformed input (silent skip).
/// GeoJSON coordinate order is [lng, lat]; LatLng takes (lat, lng) — swap.
List<LatLng>? _parseZoneGeom(String geomJson) {
  try {
    final dynamic decoded = jsonDecode(geomJson);
    if (decoded is! Map) return null;
    if (decoded['type'] != 'Polygon') return null;
    final dynamic coords = decoded['coordinates'];
    if (coords is! List || coords.isEmpty) return null;
    final dynamic ring = coords[0];
    if (ring is! List || ring.length < 3) return null;
    final pts = <LatLng>[];
    for (final pt in ring) {
      if (pt is! List || pt.length < 2) return null;
      final lng = (pt[0] as num).toDouble();
      final lat = (pt[1] as num).toDouble();
      pts.add(LatLng(lat, lng));
    }
    return pts;
  } catch (_) {
    return null;
  }
}

/// Builds a list of _ParsedZone from a raw zones emission.
/// Silently skips any row whose geom_json cannot be parsed.
List<_ParsedZone> _parseEmission(List<Map<String, dynamic>> rows) {
  final out = <_ParsedZone>[];
  for (final r in rows) {
    final geom = r['geom_json'];
    if (geom is! String) continue;
    final points = _parseZoneGeom(geom);
    if (points == null || points.length < 3) continue;
    out.add(_ParsedZone(
      id: r['id'] as String,
      ownerId: r['owner_id'] as String,
      status: (r['status'] as String?) ?? 'owned',
      influence: (r['influence'] as num?)?.toInt() ?? 1,
      points: points,
    ));
  }
  return out;
}

/// Ray-casting point-in-polygon test. Returns first matching zone or null.
/// Used by MapOptions.onTap (no GestureDetector on polygons).
_ParsedZone? _zoneAtPoint(LatLng tap, List<_ParsedZone> zones) {
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
                        .withOpacity(0.7 - 0.5 * _pulse.value),
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
          .withOpacity((0.3 + 0.5 * intensity) * (i.isEven ? 1.0 : 0.6));
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
