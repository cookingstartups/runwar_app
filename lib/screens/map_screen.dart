import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/zones_provider.dart';
import '../providers/run_recorder_provider.dart';
import '../services/run_recorder_service.dart';
import '../services/territory_service.dart';
import '../theme.dart';

// ── City center lookup ───────────────────────────────────────────────────────

const Map<String, LatLng> _kCityCenter = {
  'Valencia': LatLng(39.4699, -0.3763),
  'Madrid': LatLng(40.4168, -3.7038),
};
const LatLng _kDefaultCenter = LatLng(40.0, -3.0); // fallback: central Iberian Peninsula
const double _kInitialZoom = 13.0;

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

  @override
  void initState() {
    super.initState();
    // request permission once at mount; use addPostFrameCallback
    // so the OS dialog appears after the first frame paints.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
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
      });
    }
    // denied / deniedForever / unableToDetermine → no stream, no dot, no SnackBar
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
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

    // Listen for awaitingClaim state transition and show claim bottom sheet.
    ref.listen<RecorderState>(runRecorderProvider, (prev, next) {
      if (next == RecorderState.awaitingClaim &&
          prev != RecorderState.awaitingClaim &&
          context.mounted) {
        _showClaimSheet(context, city);
      }
    });

    // city == '' → empty zone layer, no DB query.
    final zonesAsync = city.isEmpty
        ? const AsyncValue<List<Map<String, dynamic>>>.data([])
        : ref.watch(zonesProvider(city));

    return Scaffold(
      backgroundColor: kBg,
      body: zonesAsync.when(
        loading: () => _buildMap(context, center, const [], showError: false),
        error: (e, _) => _buildMap(context, center, const [], showError: true),
        data: (rows) =>
            _buildMap(context, center, _parseEmission(rows), showError: false),
      ),
      // FAB always visible regardless of GPS/zone state.
      floatingActionButton: _buildFab(context, city),
    );
  }

  Widget _buildFab(BuildContext context, String city) {
    final recState = ref.watch(runRecorderProvider);
    final isRecording = recState == RecorderState.recording;
    return GestureDetector(
      onLongPress: isRecording
          ? () => ref.read(runRecorderProvider.notifier).forceClose()
          : null,
      child: FloatingActionButton(
        backgroundColor: kAccent,
        foregroundColor: kBg,
        onPressed: () => _onFabTap(context, recState, city),
        child: Icon(isRecording ? Icons.stop : Icons.play_arrow),
      ),
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

  Future<void> _showClaimSheet(BuildContext context, String city) async {
    final auth = ref.read(authProvider);
    final userId = auth.user?['id'] as String?;
    if (userId == null) {
      ref.read(runRecorderProvider.notifier).discard();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CLAIM TERRITORY?', style: displayStyle(size: 22)),
              const SizedBox(height: 8),
              Text(
                'Your run loop will be submitted as a territory claim.',
                style: bodyStyle(size: 13, color: kFgMuted),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: kBg,
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () async {
                  final outcome = await ref
                      .read(runRecorderProvider.notifier)
                      .confirmClaim(userId, city);
                  if (!sheetCtx.mounted) return;
                  Navigator.of(sheetCtx).pop();
                  if (!context.mounted) return;
                  _showResultSnack(context, outcome);
                },
                child: const Text('CONFIRM CLAIM'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kBorder),
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () {
                  ref.read(runRecorderProvider.notifier).discard();
                  Navigator.of(sheetCtx).pop();
                },
                child: const Text('DISCARD'),
              ),
            ],
          ),
        ),
      ),
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
    List<_ParsedZone> parsed, {
    required bool showError,
  }) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _kInitialZoom,
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
          ],
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
  /// Owned zones use owner color at 25% fill / solid stroke;
  /// disputed zones use amber at 15% fill / dashed stroke.
  List<Polygon> _buildPolygons(List<_ParsedZone> parsed) {
    final out = <Polygon>[];
    for (final z in parsed) {
      if (z.status == 'owned') {
        final ownerProfile =
            ref.watch(profileCacheProvider(z.ownerId)).valueOrNull;
        final ownerColor =
            _hexToColor((ownerProfile?['color'] as String?) ?? '#FF7A00');
        out.add(Polygon(
          points: z.points,
          isFilled: true, // §3.5: must set explicitly in flutter_map 6.x
          color: ownerColor.withValues(alpha: 0.25),
          borderColor: ownerColor,
          borderStrokeWidth: 1.5,
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
