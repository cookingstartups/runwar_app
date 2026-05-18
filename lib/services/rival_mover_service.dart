import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Animates 3 rival runners along predefined Valencia GPS routes.
/// Each rival loops its route continuously; positions update every 250 ms
/// via smooth linear interpolation between waypoints.
class RivalMoverService {
  RivalMoverService._();
  static final RivalMoverService instance = RivalMoverService._();

  static const _r1 = '00000000-r001-r001-r001-000000000001'; // RUZAFA_KID
  static const _r2 = '00000000-r002-r002-r002-000000000002'; // BEACH_RAT
  static const _r3 = '00000000-r003-r003-r003-000000000003'; // NORTE

  // Rival display info (matches demo world seed)
  static const rivalInfo = <String, Map<String, String>>{
    _r1: {'name': 'RUZAFA_KID', 'color': '#FF8500'},
    _r2: {'name': 'BEACH_RAT',  'color': '#00CFFF'},
    _r3: {'name': 'NORTE',      'color': '#39FF6B'},
  };

  // GPS routes through real Valencia streets (lat, lng).
  // Each segment ≈ 150–250 m; full loop ≈ 2–3 km.
  static final Map<String, List<LatLng>> _routes = {
    _r1: [ // RUZAFA_KID — Ruzafa grid → Ayuntamiento → back
      const LatLng(39.4638, -0.3742),
      const LatLng(39.4650, -0.3732),
      const LatLng(39.4662, -0.3720),
      const LatLng(39.4675, -0.3708),
      const LatLng(39.4685, -0.3695),
      const LatLng(39.4695, -0.3710),
      const LatLng(39.4702, -0.3728),
      const LatLng(39.4706, -0.3748),
      const LatLng(39.4700, -0.3762),
      const LatLng(39.4690, -0.3758),
      const LatLng(39.4678, -0.3752),
      const LatLng(39.4662, -0.3748),
      const LatLng(39.4648, -0.3745),
    ],
    _r2: [ // BEACH_RAT — Malvarrosa ↔ Cabanyal coastal loop
      const LatLng(39.4792, -0.3275),
      const LatLng(39.4810, -0.3258),
      const LatLng(39.4825, -0.3245),
      const LatLng(39.4840, -0.3238),
      const LatLng(39.4842, -0.3252),
      const LatLng(39.4830, -0.3265),
      const LatLng(39.4815, -0.3272),
      const LatLng(39.4798, -0.3278),
      const LatLng(39.4780, -0.3288),
      const LatLng(39.4762, -0.3298),
      const LatLng(39.4748, -0.3312),
      const LatLng(39.4742, -0.3328),
      const LatLng(39.4750, -0.3340),
      const LatLng(39.4762, -0.3325),
      const LatLng(39.4775, -0.3305),
      const LatLng(39.4785, -0.3285),
    ],
    _r3: [ // NORTE — Benimaclet university loop
      const LatLng(39.4840, -0.3562),
      const LatLng(39.4852, -0.3548),
      const LatLng(39.4862, -0.3532),
      const LatLng(39.4870, -0.3512),
      const LatLng(39.4865, -0.3496),
      const LatLng(39.4852, -0.3505),
      const LatLng(39.4840, -0.3520),
      const LatLng(39.4828, -0.3538),
      const LatLng(39.4820, -0.3555),
      const LatLng(39.4825, -0.3572),
      const LatLng(39.4835, -0.3568),
    ],
  };

  // Per-rival progress [0.0, 1.0) over the full route loop.
  // Staggered so rivals start at different points on their routes.
  final Map<String, double> _progress = {_r1: 0.0, _r2: 0.38, _r3: 0.72};

  final ValueNotifier<Map<String, LatLng>> positions =
      ValueNotifier<Map<String, LatLng>>({});

  Timer? _timer;
  bool get isRunning => _timer != null;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    debugPrint('[RivalMover] started');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('[RivalMover] stopped');
  }

  void _tick() {
    final updated = <String, LatLng>{};
    for (final id in _routes.keys) {
      final route = _routes[id]!;
      final n = route.length;
      // Advance: full loop in n*20 ticks ≈ n*5 s (comfortable running pace).
      _progress[id] = (_progress[id]! + 1.0 / (n * 20)) % 1.0;
      final fp = _progress[id]! * n;
      final seg = fp.floor() % n;
      final t = fp - fp.floor();
      final a = route[seg];
      final b = route[(seg + 1) % n];
      updated[id] = LatLng(
        a.latitude  + (b.latitude  - a.latitude)  * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
    }
    positions.value = Map.unmodifiable(updated);
  }
}
