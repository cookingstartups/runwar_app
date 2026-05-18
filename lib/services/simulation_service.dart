import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'database_service.dart';

typedef ZoneRefresh = void Function(String city);

/// Simulates rival runners claiming, contesting, and losing territory in
/// accelerated time. Each tick (~6 s) one rival player performs an action:
///   • claim  — occupy an unclaimed zone from the pool
///   • attack — dispute a zone owned by another player
///   • resolve — a disputed zone changes hands or is defended
///
/// WARLORD (demo user) is never controlled by the simulation — the human plays
/// that role. Rivals (RUZAFA_KID, BEACH_RAT, NORTE) act autonomously.
class SimulationService {
  SimulationService._();
  static final SimulationService instance = SimulationService._();

  static final _rng = Random();
  Timer? _timer;
  ZoneRefresh? _onZoneChange;

  final _isRunning = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isRunning => _isRunning;

  // ── IDs ────────────────────────────────────────────────────────────────────
  static const _demoId = '00000000-demo-demo-demo-000000000000'; // WARLORD
  static const _r1 = '00000000-r001-r001-r001-000000000001'; // RUZAFA_KID
  static const _r2 = '00000000-r002-r002-r002-000000000002'; // BEACH_RAT
  static const _r3 = '00000000-r003-r003-r003-000000000003'; // NORTE
  static const _rivals = [_r1, _r2, _r3];

  // ── Zone pool — areas the rivals compete over (lng first, RFC 7946) ────────
  // Each entry: id (stable), geom, preferred rival (first to try claiming it),
  // influence level.
  static const _pool = <Map<String, dynamic>>[
    // ── Ruzafa / South ──────────────────────────────────────────────────────
    {'id': 'sim-z01', 'preferred': _r1, 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3754,39.4595],[-0.3728,39.4592],[-0.3715,39.4598],[-0.3712,39.4610],[-0.3718,39.4620],[-0.3740,39.4622],[-0.3755,39.4616],[-0.3754,39.4595]]]}'},
    {'id': 'sim-z02', 'preferred': _r1, 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3700,39.4642],[-0.3675,39.4640],[-0.3660,39.4645],[-0.3658,39.4658],[-0.3665,39.4668],[-0.3685,39.4670],[-0.3702,39.4665],[-0.3700,39.4642]]]}'},
    {'id': 'sim-z03', 'preferred': _r1, 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3666,39.4696],[-0.3645,39.4694],[-0.3630,39.4700],[-0.3628,39.4712],[-0.3636,39.4722],[-0.3655,39.4724],[-0.3668,39.4718],[-0.3666,39.4696]]]}'},
    // ── Coastal / East ──────────────────────────────────────────────────────
    {'id': 'sim-z04', 'preferred': _r2, 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3398,39.4686],[-0.3372,39.4684],[-0.3355,39.4690],[-0.3350,39.4702],[-0.3358,39.4715],[-0.3378,39.4718],[-0.3395,39.4712],[-0.3398,39.4686]]]}'},
    {'id': 'sim-z05', 'preferred': _r2, 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3438,39.4736],[-0.3415,39.4734],[-0.3395,39.4740],[-0.3390,39.4752],[-0.3398,39.4765],[-0.3420,39.4768],[-0.3438,39.4760],[-0.3438,39.4736]]]}'},
    {'id': 'sim-z06', 'preferred': _r2, 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3508,39.4696],[-0.3482,39.4694],[-0.3465,39.4700],[-0.3462,39.4712],[-0.3470,39.4722],[-0.3490,39.4724],[-0.3508,39.4718],[-0.3508,39.4696]]]}'},
    // ── North ───────────────────────────────────────────────────────────────
    {'id': 'sim-z07', 'preferred': _r3, 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3708,39.4876],[-0.3685,39.4874],[-0.3665,39.4880],[-0.3662,39.4892],[-0.3668,39.4905],[-0.3688,39.4908],[-0.3708,39.4902],[-0.3708,39.4876]]]}'},
    {'id': 'sim-z08', 'preferred': _r3, 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3858,39.4866],[-0.3832,39.4864],[-0.3815,39.4870],[-0.3812,39.4882],[-0.3820,39.4895],[-0.3842,39.4898],[-0.3860,39.4890],[-0.3858,39.4866]]]}'},
    {'id': 'sim-z09', 'preferred': _r3, 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3648,39.4896],[-0.3622,39.4894],[-0.3605,39.4900],[-0.3602,39.4912],[-0.3610,39.4925],[-0.3632,39.4928],[-0.3650,39.4920],[-0.3648,39.4896]]]}'},
    // ── Contested central — all rivals fight over these ──────────────────────
    {'id': 'sim-z10', 'preferred': _r1, 'influence': 6,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3748,39.4712],[-0.3725,39.4710],[-0.3712,39.4715],[-0.3710,39.4728],[-0.3718,39.4738],[-0.3738,39.4740],[-0.3750,39.4732],[-0.3748,39.4712]]]}'},
    {'id': 'sim-z11', 'preferred': _r2, 'influence': 6,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3622,39.4768],[-0.3598,39.4766],[-0.3578,39.4772],[-0.3575,39.4784],[-0.3582,39.4795],[-0.3602,39.4798],[-0.3622,39.4792],[-0.3622,39.4768]]]}'},
    {'id': 'sim-z12', 'preferred': _r3, 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3838,39.4788],[-0.3812,39.4786],[-0.3798,39.4792],[-0.3795,39.4805],[-0.3802,39.4816],[-0.3822,39.4818],[-0.3840,39.4810],[-0.3838,39.4788]]]}'},
    // ── Near WARLORD — rivals will probe WARLORD territory ──────────────────
    {'id': 'sim-z13', 'preferred': _r1, 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3782,39.4666],[-0.3762,39.4664],[-0.3750,39.4670],[-0.3748,39.4682],[-0.3756,39.4692],[-0.3775,39.4694],[-0.3784,39.4684],[-0.3782,39.4666]]]}'},
    {'id': 'sim-z14', 'preferred': _r3, 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3828,39.4752],[-0.3805,39.4750],[-0.3792,39.4756],[-0.3790,39.4768],[-0.3798,39.4778],[-0.3818,39.4780],[-0.3830,39.4772],[-0.3828,39.4752]]]}'},
    {'id': 'sim-z15', 'preferred': _r2, 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3568,39.4556],[-0.3545,39.4554],[-0.3532,39.4560],[-0.3530,39.4572],[-0.3538,39.4582],[-0.3558,39.4584],[-0.3570,39.4576],[-0.3568,39.4556]]]}'},
  ];

  // ── Public API ─────────────────────────────────────────────────────────────

  void start({
    required ZoneRefresh onZoneChange,
    Duration interval = const Duration(seconds: 6),
  }) {
    _onZoneChange = onZoneChange;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
    _isRunning.value = true;
    debugPrint('[Sim] started — tick every ${interval.inSeconds}s');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning.value = false;
    debugPrint('[Sim] stopped');
  }

  // ── Internal tick ──────────────────────────────────────────────────────────

  Future<void> _tick() async {
    final db = DatabaseService.instance.db;
    final now = DateTime.now().toUtc().toIso8601String();

    // Weight: 50% claim, 30% attack rival zone, 20% resolve dispute
    final roll = _rng.nextInt(10);

    if (roll < 5) {
      await _doClaim(db, now);
    } else if (roll < 8) {
      await _doAttack(db, now);
    } else {
      await _doResolve(db, now);
    }

    _onZoneChange?.call('Valencia');
  }

  // Rival claims a free zone (or one of their preferred zones).
  Future<void> _doClaim(dynamic db, String now) async {
    final rival = _rivals[_rng.nextInt(_rivals.length)];
    // Prefer zones matching this rival; fall back to any
    final preferred = _pool.where((z) => z['preferred'] == rival).toList()
      ..shuffle(_rng);
    final others = _pool.where((z) => z['preferred'] != rival).toList()
      ..shuffle(_rng);
    final candidates = [...preferred, ...others];

    for (final spec in candidates) {
      final rows = await db.query('zones',
          where: "id = ? AND city = 'Valencia'",
          whereArgs: [spec['id']],
          limit: 1);
      if (rows.isEmpty) {
        // Unclaimed — take it
        await db.insert('zones', {
          'id': spec['id'],
          'owner_id': rival,
          'city': 'Valencia',
          'geom_json': spec['geom'],
          'status': 'owned',
          'influence': spec['influence'],
          'created_at': now,
          'updated_at': now,
        });
        return;
      }
      final z = rows.first;
      if (z['owner_id'] == rival && z['status'] == 'owned') continue;
      if (z['owner_id'] != rival && z['status'] == 'owned') {
        // Start a dispute
        await db.update('zones',
            {'status': 'disputed', 'updated_at': now},
            where: 'id = ?', whereArgs: [spec['id']]);
        return;
      }
    }
  }

  // Rival attacks a zone currently owned by a different player.
  Future<void> _doAttack(dynamic db, String now) async {
    final rival = _rivals[_rng.nextInt(_rivals.length)];
    // Find zones owned by others (not WARLORD, to keep the demo fun)
    final targets = await db.query('zones',
        where: "city = 'Valencia' AND status = 'owned' AND owner_id != ? AND owner_id != ?",
        whereArgs: [rival, _demoId],
        limit: 10);
    if (targets.isEmpty) return;
    final target = targets[_rng.nextInt(targets.length)];
    await db.update('zones',
        {'status': 'disputed', 'updated_at': now},
        where: 'id = ?', whereArgs: [target['id']]);
  }

  // Resolve a dispute — attacker wins 60% of the time, defender reclaims 40%.
  Future<void> _doResolve(dynamic db, String now) async {
    final disputed = await db.query('zones',
        where: "city = 'Valencia' AND status = 'disputed' AND owner_id != ?",
        whereArgs: [_demoId], // never auto-resolve WARLORD zones
        limit: 10);
    if (disputed.isEmpty) return;
    final zone = disputed[_rng.nextInt(disputed.length)];
    final currentOwner = zone['owner_id'] as String;

    if (_rng.nextDouble() < 0.6) {
      // Challenger wins — pick a rival that isn't the owner
      final challengers = _rivals.where((r) => r != currentOwner).toList();
      final winner = challengers[_rng.nextInt(challengers.length)];
      await db.update('zones', {
        'owner_id': winner,
        'status': 'owned',
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [zone['id']]);
    } else {
      // Defender holds
      await db.update('zones',
          {'status': 'owned', 'updated_at': now},
          where: 'id = ?', whereArgs: [zone['id']]);
    }
  }
}
