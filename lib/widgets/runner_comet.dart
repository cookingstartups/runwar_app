// lib/widgets/runner_comet.dart
//
// Comet-trail widget for live runner positions.
// Renders a filled circle head at positions.last, with an optional decaying
// tail when isRecording == true and positions.length >= 2.
//
// Hosted inside a MarkerLayer Marker (80x80 px). The head is drawn at the
// marker center (40,40). Tail offsets are projected from lat/lng to screen
// pixels using MapCamera.of(context) when available.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ── Haversine helper ──────────────────────────────────────────────────────────

// ── Pace-dependent tail window (T0600) ────────────────────────────────────────
//
// First-pass default (not pinned by any existing spec - see
// intro-comet-tail/requirements.md for the fixed-window intro comet this
// adapts): the tail's effective time window scales linearly with the
// runner's current speed, between a minimum window at walking pace and a
// maximum window at a fast running pace. This reuses the existing
// head-to-tail alpha gradient and teleport-cut logic in [_CometPainter]
// unchanged - only the distance of track fed into it varies.
//
// Operator-tunable constants; flagged in the T0600 task file as a
// documented first-pass default, not a locked design decision.
const double kCometPaceMinSpeedMps = 1.0; // ~3.6 km/h - walking floor
const double kCometPaceMaxSpeedMps = 4.0; // ~14.4 km/h - fast running
const double kCometPaceTailMinSec = 5.0; // tail window at/below min speed
const double kCometPaceTailMaxSec = 15.0; // tail window at/above max speed

/// Returns the tail time window (seconds) for a given instantaneous speed,
/// linearly interpolated between [kCometPaceTailMinSec] at
/// [kCometPaceMinSpeedMps] and [kCometPaceTailMaxSec] at
/// [kCometPaceMaxSpeedMps], clamped outside that range.
double cometTailWindowSecondsForSpeed(double speedMps) {
  final clamped = speedMps.clamp(kCometPaceMinSpeedMps, kCometPaceMaxSpeedMps);
  final t = (clamped - kCometPaceMinSpeedMps) /
      (kCometPaceMaxSpeedMps - kCometPaceMinSpeedMps);
  return lerpDouble(kCometPaceTailMinSec, kCometPaceTailMaxSec, t)!;
}

/// Returns the tail length in meters for a given instantaneous speed:
/// `max(speedMps, kCometPaceMinSpeedMps) * cometTailWindowSecondsForSpeed(speedMps)`.
/// The speed floor keeps the tail from collapsing to near-zero on a single
/// noisy near-zero GPS speed reading while the runner is still moving.
double cometTailLengthMetersForSpeed(double speedMps) {
  final windowSec = cometTailWindowSecondsForSpeed(speedMps);
  final effectiveSpeed = math.max(speedMps, kCometPaceMinSpeedMps);
  return effectiveSpeed * windowSec;
}

/// Selects the trailing sublist of [track] whose cumulative path length is
/// approximately [meters], walking backward from the newest point. Always
/// returns at least the last 2 points when the track has >= 2 points, so a
/// visible tail segment exists even when [meters] is very small.
List<LatLng> selectCometTailForDistance(List<LatLng> track, double meters) {
  if (track.length <= 2) return List<LatLng>.from(track);
  var acc = 0.0;
  var idx = track.length - 1;
  while (idx > 0) {
    final seg = _haversineMeters(track[idx - 1], track[idx]);
    if (acc > 0 && acc + seg > meters) break;
    acc += seg;
    idx--;
  }
  return track.sublist(idx);
}

double _haversineMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final sinLat = math.sin(dLat / 2);
  final sinLng = math.sin(dLng / 2);
  final a2 = sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
  return r * 2 * math.atan2(math.sqrt(a2), math.sqrt(1 - a2));
}

// ── _CometPainter ─────────────────────────────────────────────────────────────

class _CometPainter extends CustomPainter {
  _CometPainter({
    required this.positions,
    required this.offsets,
    required this.accentColor,
    required this.isRecording,
  });

  final List<LatLng> positions;
  // Screen-relative offsets: offsets[i] = screenPoint(positions[i]) - screenPoint(positions.last)
  // May be empty when MapCamera is unavailable (fallback: head-only).
  final List<Offset> offsets;
  final Color accentColor;
  final bool isRecording;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // -- Tail ----------------------------------------------------------------
    if (isRecording && positions.length >= 2 && offsets.length == positions.length) {
      // Find the contiguous window after any teleport gap (>500 m).
      int cutStart = _findTeleportCut(positions);
      // tail is positions[cutStart..end], at least 2 points needed for segments.
      final tailLen = positions.length - cutStart;
      if (tailLen >= 2) {
        final n = tailLen; // number of points in tail window
        for (var i = cutStart; i < positions.length - 1; i++) {
          // t: 0 = oldest segment, 1 = newest segment (closest to head)
          final segIndex = i - cutStart;
          final t = (segIndex + 1) / (n - 1).toDouble();
          final alpha = lerpDouble(0.1, 0.6, t)!;
          final width = lerpDouble(1.0, 6.0, t)!;
          final paint = Paint()
            ..color = accentColor.withValues(alpha: alpha)
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawLine(
            center + offsets[i],
            center + offsets[i + 1],
            paint,
          );
        }
      }
    }

    // -- Head ----------------------------------------------------------------
    // Always drawn: 14 px diameter = radius 7.
    canvas.drawCircle(
      center,
      7.0,
      Paint()..color = accentColor,
    );
  }

  @override
  bool shouldRepaint(covariant _CometPainter old) {
    if (old.isRecording != isRecording) return true;
    if (old.accentColor != accentColor) return true;
    if (old.positions.length != positions.length) return true;
    if (positions.isNotEmpty && old.positions.isNotEmpty &&
        old.positions.last != positions.last) {
      return true;
    }
    return false;
  }
}

// Find the start index of the contiguous tail window, walking backwards.
// Returns the index after the last teleport gap found, or 0 if none.
int _findTeleportCut(List<LatLng> p) {
  for (var i = p.length - 1; i > 0; i--) {
    if (_haversineMeters(p[i], p[i - 1]) > 500.0) return i;
  }
  return 0;
}

// ── RunnerComet ───────────────────────────────────────────────────────────────

/// Comet marker widget: head circle + optional decaying tail.
///
/// Designed to be hosted inside a 80x80 [Marker] in a [MarkerLayer].
/// The head (positions.last) is drawn at the marker center.
///
/// Tail is rendered only when [isRecording] is true and
/// [positions].length >= 2. Consecutive tail points > 500 m apart
/// trigger the teleport guard (tail is truncated at the gap).
class RunnerComet extends StatelessWidget {
  const RunnerComet({
    super.key,
    required this.positions,
    required this.accentColor,
    required this.isRecording,
  });

  /// Oldest-first list of positions. positions.last is the current head.
  final List<LatLng> positions;

  /// Accent color for both the head and tail segments.
  final Color accentColor;

  /// When false, only the head circle is drawn (tail suppressed).
  final bool isRecording;

  /// Haversine distance between two lat/lng points, in meters.
  /// Exposed as a test seam.
  @visibleForTesting
  static double distanceBetween(LatLng a, LatLng b) => _haversineMeters(a, b);

  @override
  Widget build(BuildContext context) {
    // Project positions to screen-relative offsets using the map camera.
    // Falls back to empty offsets (head-only) when camera is unavailable.
    List<Offset> offsets = const [];
    if (positions.isNotEmpty) {
      try {
        final camera = MapCamera.of(context);
        final headScreen = camera.latLngToScreenPoint(positions.last);
        offsets = positions
            .map((p) {
              final s = camera.latLngToScreenPoint(p);
              return Offset(s.x - headScreen.x, s.y - headScreen.y);
            })
            .toList(growable: false);
      } catch (e) {
        // MapCamera not in tree (unit test / off-map render) - head-only.
        debugPrint('[RunnerComet] MapCamera unavailable - falling back to head-only: $e');
        offsets = List.filled(positions.length, Offset.zero);
      }
    }

    return CustomPaint(
      size: const Size(80, 80),
      painter: _CometPainter(
        positions: positions,
        offsets: offsets,
        accentColor: accentColor,
        isRecording: isRecording,
      ),
    );
  }
}
