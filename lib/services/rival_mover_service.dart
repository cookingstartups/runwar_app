import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '_valencia_routes.dart';
import 'territory_service.dart';

enum BotStrategy { deep, wide, balanced, yield_, compounding }

/// Drives 5 simulated runners through real Valencia streets.
/// Active: @RitaBarberà (Ruzafa), @Esmorçaet (Malvarrosa), @Club_Babalà (Jesús),
///         @Visquen_les_FALLES (Campanar), @Cremaet (Histórico — routes pending).
class RivalMoverService {
  RivalMoverService._();
  static final RivalMoverService instance = RivalMoverService._();

  // Legacy alias kept for map_screen.dart which reads rivalInfo.
  static const rivalInfo = valenciaRivalInfo;

  // ── Strategy assignments ───────────────────────────────────────────────────
  static const Map<String, BotStrategy> _strategies = {
    vBotR12: BotStrategy.deep,        // @Visquen_les_FALLES — always home loop
    vBotR2:  BotStrategy.wide,        // @Esmorçaet — cycle through loops
    // vBotRCremaet: BotStrategy.balanced, // @Cremaet — reinforce to 3 then expand
    vBotR1:  BotStrategy.yield_,      // @RitaBarberà — largest-area loop first
    vBotR11: BotStrategy.compounding, // @Club_Babalà — max zone then next
  };

  // ── Per-bot state ──────────────────────────────────────────────────────────
  final Map<String, double> _progress = {
    vBotR1:  0.28,   // @RitaBarberà — Ruzafa
    vBotR2:  0.00,   // @Esmorçaet — Malvarrosa
    // vBotRCremaet: 0.42,  // @Cremaet — Histórico (activate once routes defined)
    vBotR11: 0.75,   // @Club_Babalà — Jesús
    vBotR12: 0.55,   // @Visquen_les_FALLES — Campanar
  };

  final Map<String, int> _loopIdx = {
    vBotR1:  0,
    vBotR2:  0,
    // vBotRCremaet: 0,
    vBotR11: 0,
    vBotR12: 0,
  };

  final Map<String, List<LatLng>> _tails = {
    for (final id in valenciaRivalInfo.keys) id: <LatLng>[],
  };

  // Accumulated running distance per bot tail (metres).
  final Map<String, double> _tailDistM = {};

  // Compounding strategy: how many loops completed on the current zone.
  final Map<String, int> _compoundingLoops = {};

  // Global tick counter for balanced strategy alternation.
  int _tickCount = 0;

  // Passive income accrual: fire every 60 ticks (~15s at 250ms/tick).
  int _incomeTickCount = 0;

  // Published notifiers
  final ValueNotifier<Map<String, LatLng>> positions =
      ValueNotifier<Map<String, LatLng>>({});
  final ValueNotifier<Map<String, List<LatLng>>> tails =
      ValueNotifier<Map<String, List<LatLng>>>({});

  // Callbacks set by SimulationService
  void Function(String city)? onZoneChange;
  void Function(String event)? onEvent;

  double _speedMultiplier = 1.0;
  Timer? _timer;
  bool get isRunning => _timer != null;

  static const int _kMinClaimPts = 5;
  static const double _kMinPerimeterM = 200.0;
  static const double _earthRadiusM = 6371008.8;
  static const double _kMaxTailM = 500.0;

  // ── Public API ─────────────────────────────────────────────────────────────

  void start({double speedMultiplier = 1.0}) {
    _speedMultiplier = speedMultiplier;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    debugPrint('[RivalMover] started — speed×$speedMultiplier');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('[RivalMover] stopped');
  }

  void setSpeed(double multiplier) {
    _speedMultiplier = multiplier;
  }

  void clearTails() {
    for (final id in _tails.keys) {
      _tails[id] = <LatLng>[];
      _tailDistM[id] = 0;
    }
    tails.value = Map.unmodifiable({
      for (final e in _tails.entries) e.key: List.unmodifiable(e.value),
    });
  }

  // ── Tick ───────────────────────────────────────────────────────────────────

  void _tick() {
    _tickCount++;
    _incomeTickCount++;

    final updatedPositions = <String, LatLng>{};

    for (final id in valenciaRivalInfo.keys) {
      final routes = valenciaRoutes[id];
      if (routes == null || routes.isEmpty) continue;
      final loopIdx = _loopIdx[id];
      if (loopIdx == null) continue;
      final route = routes[loopIdx];
      if (route.isEmpty) continue;
      final n = route.length;

      final advance = _speedMultiplier / (n * 20);
      _progress[id] = (_progress[id]! + advance);

      final wrapped = _progress[id]! >= 1.0;
      if (wrapped) _progress[id] = _progress[id]! - 1.0;

      final fp = _progress[id]! * n;
      final seg = fp.floor() % n;
      final t = fp - fp.floor();
      final a = route[seg];
      final b = route[(seg + 1) % n];
      final pos = LatLng(
        a.latitude  + (b.latitude  - a.latitude)  * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      updatedPositions[id] = pos;

      // Append to tail; maintain 500m cumulative distance window.
      final tail = _tails[id]!;
      if (tail.isNotEmpty) {
        final segDist = _haversine(tail.last, pos);
        _tailDistM[id] = (_tailDistM[id] ?? 0) + segDist;
      }
      tail.add(pos);
      while ((_tailDistM[id] ?? 0) > _kMaxTailM && tail.length > 2) {
        final removed = tail.removeAt(0);
        if (tail.isNotEmpty) {
          _tailDistM[id] =
              (_tailDistM[id] ?? 0) - _haversine(removed, tail.first);
        }
      }

      if (wrapped) {
        _onLoopComplete(id);
      }
    }

    positions.value = Map.unmodifiable(updatedPositions);
    tails.value = Map.unmodifiable({
      for (final e in _tails.entries) e.key: List.unmodifiable(e.value),
    });

    // Accrue passive income every 60 ticks (~15s).
    if (_incomeTickCount >= 60) {
      _incomeTickCount = 0;
      TerritoryService.instance.accruePassiveIncome('Valencia').catchError(
        (Object e) => debugPrint('[RivalMover] income error: $e'),
      );
    }
  }

  // ── Loop closure ───────────────────────────────────────────────────────────

  void _onLoopComplete(String id) {
    final tail = List<LatLng>.from(_tails[id]!);
    _tails[id] = <LatLng>[];
    _tailDistM[id] = 0;

    if (tail.length < _kMinClaimPts) return;
    final perimeter = _computePerimeter(tail);
    if (perimeter < _kMinPerimeterM) return;

    _loopIdx[id] = _nextLoopIdx(id, _loopIdx[id]!);

    final name = valenciaRivalInfo[id]?['name'] ?? id;
    _claimAsync(id, tail, name);
  }

  // ── Strategy-based loop selection ─────────────────────────────────────────

  int _nextLoopIdx(String id, int currentIdx) {
    final routes = valenciaRoutes[id];
    if (routes == null || routes.isEmpty) return 0;
    final n = routes.length;
    final strategy = _strategies[id] ?? BotStrategy.wide;
    switch (strategy) {
      case BotStrategy.deep:
        return 0;
      case BotStrategy.wide:
        return (currentIdx + 1) % n;
      case BotStrategy.balanced:
        return _tickCount % 3 == 0 ? currentIdx : (currentIdx + 1) % n;
      case BotStrategy.yield_:
        var bestIdx = 0;
        var bestPts = 0;
        for (var i = 0; i < n; i++) {
          if (routes[i].length > bestPts) {
            bestPts = routes[i].length;
            bestIdx = i;
          }
        }
        return bestIdx;
      case BotStrategy.compounding:
        _compoundingLoops[id] = (_compoundingLoops[id] ?? 0) + 1;
        if (_compoundingLoops[id]! >= 3) {
          _compoundingLoops[id] = 0;
          return (currentIdx + 1) % n;
        }
        return currentIdx;
    }
  }

  // ── Async claim ────────────────────────────────────────────────────────────

  Future<void> _claimAsync(
    String botId,
    List<LatLng> polygon,
    String botName,
  ) async {
    try {
      final outcome = await TerritoryService.instance.evaluateClaim(
        botId,
        'Valencia',
        polygon,
      );
      final verb = switch (outcome.result) {
        TerritoryResult.claimed   => 'claimed',
        TerritoryResult.conquered => 'conquered',
        TerritoryResult.disputed  => 'disputed',
        TerritoryResult.failed    => null,
      };
      if (verb != null) {
        final label = _neighborhoodOf(botId);
        onEvent?.call('$botName $verb $label');
        onZoneChange?.call('Valencia');
      }
    } catch (e) {
      debugPrint('[RivalMover] claim error for $botId: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  double _computePerimeter(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    var sum = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      sum += _haversine(pts[i], pts[i + 1]);
    }
    return sum;
  }

  double _haversine(LatLng a, LatLng b) {
    final p1 = a.latitude  * math.pi / 180.0;
    final p2 = b.latitude  * math.pi / 180.0;
    final dp = (b.latitude  - a.latitude)  * math.pi / 180.0;
    final dl = (b.longitude - a.longitude) * math.pi / 180.0;
    final h  = math.sin(dp / 2) * math.sin(dp / 2) +
               math.cos(p1) * math.cos(p2) *
               math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static const _neighborhoods = <String, String>{
    vBotR1:  'Ruzafa',      // @RitaBarberà
    vBotR2:  'Malvarrosa',  // @Esmorçaet
    // vBotRCremaet: 'Histórico',  // @Cremaet
    vBotR11: 'Jesús',       // @Club_Babalà
    vBotR12: 'Campanar',    // @Visquen_les_FALLES
  };

  static String _neighborhoodOf(String id) =>
      _neighborhoods[id] ?? 'Valencia';
}
