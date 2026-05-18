import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // In-memory session map. Lost on process kill.
  Map<String, dynamic>? _currentUser;

  /// Inserts one `users` row + one `profiles` row in a transaction.
  /// Returns the new user map (id/email/created_at) or null on duplicate email.
  Future<Map<String, dynamic>?> signUp(String email, String password) async {
    final db = DatabaseService.instance.db;
    final id = _uuidV4();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    try {
      await db.transaction((txn) async {
        await txn.insert('users', {
          'id': id,
          'email': email,
          'password': password,
          'created_at': nowIso,
        });
        await txn.insert('profiles', {
          'id': id,
          'username': '',
          'city': '',
          'color': '#FF7A00',
          'influence_level': 1,
          'invited_at': null,
          'created_at': nowIso,
        });
      });
    } on DatabaseException catch (e) {
      // Duplicate email — return null without throwing.
      if (e.isUniqueConstraintError()) return null;
      rethrow;
    }

    _currentUser = {'id': id, 'email': email, 'created_at': nowIso};
    return _currentUser;
  }

  /// Returns user map on credential match; null otherwise. Never throws.
  /// Special case: admin@test.com / 123456 seeds a demo user with territory on
  /// first login (no prior sign-up required).
  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    if (email == 'demo@user.com' && password == '123456') {
      return _signInDemo();
    }
    final db = DatabaseService.instance.db;
    final rows = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row['password'] != password) return null;
    _currentUser = {
      'id': row['id'],
      'email': row['email'],
      'created_at': row['created_at'],
    };
    return _currentUser;
  }

  static const String _demoId = '00000000-demo-demo-demo-000000000000';
  static const String _demoEmail = 'demo@user.com';

  Future<Map<String, dynamic>> _signInDemo() async {
    final db = DatabaseService.instance.db;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final existing = await db.query('users',
        where: 'id = ?', whereArgs: [_demoId], limit: 1);

    if (existing.isEmpty) {
      await db.transaction((txn) async {
        // ── Users + profiles ─────────────────────────────────────────────────
        for (final u in _allDemoUsers) {
          await txn.insert('users', {
            'id': u['id'],
            'email': u['email'],
            'password': '123456',
            'created_at': nowIso,
          });
          await txn.insert('profiles', {
            'id': u['id'],
            'username': u['username'],
            'city': 'Valencia',
            'color': u['color'],
            'influence_level': u['influence'],
            'invited_at': nowIso,
            'created_at': nowIso,
          });
        }
        // ── Zones ────────────────────────────────────────────────────────────
        for (final z in _allDemoZones) {
          await txn.insert('zones', {
            'id': _uuidV4(),
            'owner_id': z['owner'],
            'city': 'Valencia',
            'geom_json': z['geom'],
            'status': z['status'],
            'influence': z['influence'],
            'created_at': nowIso,
            'updated_at': nowIso,
          });
        }
      });
    }

    _currentUser = {'id': _demoId, 'email': _demoEmail, 'created_at': nowIso};
    return _currentUser!;
  }

  // ── Demo world data (lng first — RFC 7946) ───────────────────────────────────

  static const _r1 = '00000000-r001-r001-r001-000000000001'; // RUZAFA_KID
  static const _r2 = '00000000-r002-r002-r002-000000000002'; // BEACH_RAT
  static const _r3 = '00000000-r003-r003-r003-000000000003'; // NORTE

  static const List<Map<String, dynamic>> _allDemoUsers = [
    {'id': _demoId,  'email': _demoEmail,        'username': 'WARLORD',    'color': '#FF2D7A', 'influence': 8},
    {'id': _r1,      'email': 'r1@runwar.demo',  'username': 'RUZAFA_KID', 'color': '#FF8500', 'influence': 5},
    {'id': _r2,      'email': 'r2@runwar.demo',  'username': 'BEACH_RAT',  'color': '#00CFFF', 'influence': 6},
    {'id': _r3,      'email': 'r3@runwar.demo',  'username': 'NORTE',      'color': '#39FF6B', 'influence': 4},
  ];

  static const List<Map<String, dynamic>> _allDemoZones = [
    // ── WARLORD — incumbent territories ──────────────────────────────────────
    // Plaza del Ayuntamiento — under siege by RUZAFA_KID
    {'owner': _demoId, 'status': 'disputed', 'influence': 8,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3775,39.4695],[-0.3762,39.4692],[-0.3748,39.4696],[-0.3746,39.4706],[-0.3752,39.4712],[-0.3770,39.4711],[-0.3778,39.4703],[-0.3775,39.4695]]]}'},
    // El Carmen — under siege by NORTE
    {'owner': _demoId, 'status': 'disputed', 'influence': 8,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3815,39.4728],[-0.3798,39.4726],[-0.3785,39.4730],[-0.3783,39.4742],[-0.3790,39.4750],[-0.3808,39.4752],[-0.3818,39.4745],[-0.3820,39.4735],[-0.3815,39.4728]]]}'},
    // Ciudad de las Artes — secure
    {'owner': _demoId, 'status': 'owned', 'influence': 8,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3540,39.4530],[-0.3510,39.4528],[-0.3495,39.4535],[-0.3492,39.4548],[-0.3498,39.4558],[-0.3520,39.4562],[-0.3540,39.4555],[-0.3545,39.4542],[-0.3540,39.4530]]]}'},
    // Ruzafa Sur — conquered from RUZAFA_KID
    {'owner': _demoId, 'status': 'owned', 'influence': 6,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3724,39.4618],[-0.3705,39.4615],[-0.3694,39.4620],[-0.3692,39.4632],[-0.3700,39.4640],[-0.3718,39.4642],[-0.3727,39.4636],[-0.3724,39.4618]]]}'},

    // ── RUZAFA_KID — southern runner ─────────────────────────────────────────
    // Ruzafa Central
    {'owner': _r1, 'status': 'owned', 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3742,39.4638],[-0.3726,39.4636],[-0.3708,39.4640],[-0.3702,39.4650],[-0.3706,39.4662],[-0.3722,39.4668],[-0.3740,39.4665],[-0.3746,39.4654],[-0.3742,39.4638]]]}'},
    // Gran Vía
    {'owner': _r1, 'status': 'owned', 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3728,39.4672],[-0.3708,39.4668],[-0.3690,39.4670],[-0.3678,39.4676],[-0.3682,39.4686],[-0.3696,39.4690],[-0.3718,39.4690],[-0.3730,39.4684],[-0.3728,39.4672]]]}'},
    // Challenging WARLORD's Ayuntamiento
    {'owner': _r1, 'status': 'disputed', 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3762,39.4688],[-0.3748,39.4686],[-0.3736,39.4690],[-0.3733,39.4700],[-0.3740,39.4710],[-0.3755,39.4712],[-0.3764,39.4704],[-0.3762,39.4688]]]}'},

    // ── BEACH_RAT — coastal runner ────────────────────────────────────────────
    // Malvarrosa beach
    {'owner': _r2, 'status': 'owned', 'influence': 6,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3278,39.4790],[-0.3255,39.4790],[-0.3240,39.4798],[-0.3235,39.4815],[-0.3240,39.4835],[-0.3258,39.4840],[-0.3278,39.4832],[-0.3282,39.4815],[-0.3278,39.4790]]]}'},
    // Cabanyal
    {'owner': _r2, 'status': 'owned', 'influence': 6,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3345,39.4728],[-0.3320,39.4725],[-0.3298,39.4730],[-0.3290,39.4742],[-0.3294,39.4758],[-0.3312,39.4765],[-0.3335,39.4762],[-0.3345,39.4748],[-0.3345,39.4728]]]}'},
    // Jardines del Turia — park corridor
    {'owner': _r2, 'status': 'owned', 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3688,39.4758],[-0.3665,39.4755],[-0.3645,39.4758],[-0.3640,39.4768],[-0.3648,39.4778],[-0.3668,39.4780],[-0.3688,39.4778],[-0.3692,39.4768],[-0.3688,39.4758]]]}'},

    // ── NORTE — north Valencia runner ─────────────────────────────────────────
    // Benimaclet
    {'owner': _r3, 'status': 'owned', 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3585,39.4838],[-0.3558,39.4835],[-0.3540,39.4840],[-0.3535,39.4852],[-0.3542,39.4865],[-0.3560,39.4870],[-0.3580,39.4868],[-0.3588,39.4855],[-0.3585,39.4838]]]}'},
    // Campanar
    {'owner': _r3, 'status': 'owned', 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3992,39.4808],[-0.3968,39.4805],[-0.3948,39.4810],[-0.3940,39.4822],[-0.3946,39.4836],[-0.3962,39.4842],[-0.3982,39.4840],[-0.3995,39.4828],[-0.3992,39.4808]]]}'},
    // Challenging WARLORD's El Carmen
    {'owner': _r3, 'status': 'disputed', 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3808,39.4718],[-0.3790,39.4715],[-0.3778,39.4720],[-0.3775,39.4730],[-0.3780,39.4742],[-0.3796,39.4745],[-0.3810,39.4740],[-0.3808,39.4718]]]}'},
  ];

  /// Idempotent — clears in-memory session only. SQLite untouched.
  Future<void> signOut() async {
    _currentUser = null;
  }

  /// PoC no-op. Console log only. No network, no email.
  Future<void> sendPasswordReset(String email) async {
    debugPrint('[AuthService] sendPasswordReset($email) — PoC no-op');
  }

  /// Synchronous. Never hits DB or network.
  Map<String, dynamic>? getCurrentUser() => _currentUser;

  // ── UUID v4 (RFC 4122) ───────────────────────────────────────────────────────
  static final Random _rng = Random.secure();
  static String _uuidV4() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 10
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-'
        '${h(4)}${h(5)}-'
        '${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-'
        '${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
