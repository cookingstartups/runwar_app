// lib/widgets/rival_runner_marker.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/realtime_presence_service.dart';
import '../theme.dart';
import 'beam_pulse_dot.dart';

Color _colorFromHex(String hex) {
  try {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  } catch (_) {
    return const Color(0xFFFF7A00);
  }
}

double _distanceM(LatLng a, LatLng b) {
  const r = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final sinLat = math.sin(dLat / 2);
  final sinLng = math.sin(dLng / 2);
  final c = sinLat * sinLat +
      math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
  return r * 2 * math.atan2(math.sqrt(c), math.sqrt(1 - c));
}

/// Renders a rival player's map marker with the beam-pulse intro-slide aesthetic.
class RivalRunnerMarker extends StatelessWidget {
  const RivalRunnerMarker({
    super.key,
    required this.presence,
    required this.myPos,
  });

  final PlayerPresence presence;
  final LatLng myPos;

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(presence.colorHex ?? presence.color);
    final isNearby = _distanceM(myPos, presence.position) < 200;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            if (isNearby)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: kAccent2.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
              ),
            BeamPulseDot(
              color: color,
              size: 10,
              showPulse: presence.isRecording,
            ),
          ],
        ),
        Text(
          presence.displayName,
          style: TextStyle(
            color: color,
            fontSize: 7,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
      ],
    );
  }
}
