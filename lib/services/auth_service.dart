import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'supabase_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // In-memory session map. Lost on process kill.
  Map<String, dynamic>? _currentUser;

  /// Anonymous sign-in for PoC alpha testers.
  /// Uses Supabase anonymous auth when connected; falls back to a local UUID.
  /// Creates SQLite user+profile with invited_at set so the route guard passes.
  /// Idempotent — safe to call on every app launch.
  Future<Map<String, dynamic>> signInAnonymously() async {
    final db = DatabaseService.instance.db;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Get (or create) the Supabase anonymous session.
    final supabaseUid = await SupabaseService.instance.signIn();

    // Use Supabase UID when connected; otherwise generate a stable local UUID.
    final localId = supabaseUid ?? _uuidV4();

    // Check if this device already has a local profile.
    final existing = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      _currentUser = {
        'id': localId,
        'email': existing.first['email'] as String? ?? '',
        'created_at': existing.first['created_at'] as String? ?? nowIso,
        if (supabaseUid != null) 'supabase_uid': supabaseUid,
      };
      return _currentUser!;
    }

    // First launch — create user + profile.
    final shortId = localId.replaceAll('-', '').substring(0, 6).toUpperCase();
    final username = 'RUNNER-$shortId';
    final email = '${localId.substring(0, 8)}@runwar.anon';

    await db.transaction((txn) async {
      await txn.insert('users', {
        'id': localId,
        'email': email,
        'password': '',
        'created_at': nowIso,
      });
      await txn.insert('profiles', {
        'id': localId,
        'username': username,
        'city': 'Valencia',
        'color': '#FF7A00',
        'influence_level': 1,
        'invited_at': nowIso, // bypasses waitlist gate for PoC
        'is_tester': 1,
        'created_at': nowIso,
      });
    });

    _currentUser = {
      'id': localId,
      'email': email,
      'created_at': nowIso,
      if (supabaseUid != null) 'supabase_uid': supabaseUid,
    };
    debugPrint('[AuthService] anonymous sign-in complete: $username ($localId)');
    return _currentUser!;
  }

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
          'is_tester': 0,
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
  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    final Map<String, dynamic>? user;
    if (email == _demoEmail && password == '123456') {
      user = await _signInDemo();
    } else {
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
      user = _currentUser;
    }
    if (user != null) {
      // Establish Supabase Auth session using the actual form credentials.
      await SupabaseService.instance.signInWithPassword(email, password);
    }
    return user;
  }

  static const String _demoId    = '3510bc04-8b4c-4d1d-8a5c-250875ae2c30'; // WARLORD
  static const String _demoEmail = 'demo@user.com';

  /// Called once from main.dart after DB init. Idempotent — safe to call
  /// on every launch; users/profiles use INSERT OR IGNORE; zones/runs are
  /// guarded by an existence check so they are inserted at most once.
  Future<void> seedDemoDataIfNeeded() async {
    final db = DatabaseService.instance.db;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Remove any stale rows that share an email with a demo user but have a
    // different id (prevents UNIQUE email constraint silently blocking insert).
    for (final u in _allDemoUsers) {
      await db.delete('users',
          where: 'email = ? AND id != ?', whereArgs: [u['email'] as String, u['id'] as String]);
    }
    // Users + profiles: idempotent via INSERT OR IGNORE on primary key.
    await db.transaction((txn) async {
      for (final u in _allDemoUsers) {
        await txn.insert('users',
            {'id': u['id'], 'email': u['email'], 'password': '123456', 'created_at': nowIso},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert('profiles',
            {
              'id': u['id'],
              'username': u['username'],
              'city': 'Valencia',
              'color': u['color'],
              'influence_level': u['influence'],
              'invited_at': nowIso,
              'is_tester': 0,
              'created_at': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });

    // Zones use random UUIDs — guard with existence check to avoid duplicates.
    final existingZones = await db.query('zones',
        where: 'owner_id = ?', whereArgs: [_demoId], limit: 1);
    if (existingZones.isEmpty) {
      await db.transaction((txn) async {
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

    // Seed WARLORD runs separately (runs table added after initial schema).
    final existingRuns = await db.query('runs',
        where: 'user_id = ?', whereArgs: [_demoId], limit: 1);
    if (existingRuns.isEmpty) {
      for (final r in _demoRuns) {
        await db.insert('runs', {
          'id': _uuidV4(),
          'user_id': _demoId,
          'city': 'Valencia',
          'track_json': r,
          'started_at': nowIso,
          'closed_at': nowIso,
          'zone_id': null,
          'created_at': nowIso,
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _signInDemo() async {
    final db = DatabaseService.instance.db;
    final rows = await db.query('users',
        where: 'id = ?', whereArgs: [_demoId], limit: 1);
    if (rows.isEmpty) return null;
    _currentUser = {
      'id': _demoId,
      'email': _demoEmail,
      'created_at': rows.first['created_at'],
    };
    return _currentUser;
  }

  // WARLORD's pre-seeded run tracks — one loop per territory cluster.
  // Coordinates: [lng, lat] per RFC 7946.
  static const List<String> _demoRuns = [
    // City centre loop — Ayuntamiento + El Carmen + Mercado Central
    '{"type":"LineString","coordinates":[[-0.3780,39.4690],[-0.3765,39.4688],[-0.3748,39.4692],[-0.3744,39.4703],[-0.3748,39.4714],[-0.3762,39.4718],[-0.3780,39.4752],[-0.3800,39.4753],[-0.3820,39.4745],[-0.3820,39.4728],[-0.3808,39.4722],[-0.3790,39.4719],[-0.3775,39.4723],[-0.3768,39.4735],[-0.3775,39.4748],[-0.3795,39.4750],[-0.3808,39.4743],[-0.3810,39.4730],[-0.3800,39.4726]]}',
    // Xàtiva corridor + Ruzafa Sur
    '{"type":"LineString","coordinates":[[-0.3820,39.4660],[-0.3800,39.4656],[-0.3775,39.4655],[-0.3755,39.4660],[-0.3755,39.4672],[-0.3768,39.4677],[-0.3728,39.4616],[-0.3710,39.4613],[-0.3694,39.4619],[-0.3692,39.4631],[-0.3700,39.4642],[-0.3720,39.4644],[-0.3728,39.4636]]}',
    // Jardines del Real — north corridor
    '{"type":"LineString","coordinates":[[-0.3688,39.4762],[-0.3675,39.4759],[-0.3660,39.4760],[-0.3654,39.4770],[-0.3654,39.4784],[-0.3660,39.4800],[-0.3672,39.4807],[-0.3685,39.4806],[-0.3690,39.4795],[-0.3690,39.4778],[-0.3688,39.4762]]}',
    // Ciudad de las Artes — southeast
    '{"type":"LineString","coordinates":[[-0.3548,39.4528],[-0.3525,39.4525],[-0.3497,39.4534],[-0.3492,39.4548],[-0.3498,39.4562],[-0.3520,39.4566],[-0.3542,39.4558],[-0.3548,39.4542],[-0.3548,39.4528]]}',
  ];

  // ── Demo world data (lng first — RFC 7946) ───────────────────────────────────

  static const _r1  = '60b22465-ccbd-424b-a694-397f1c4468a5'; // SOCARRAT
  static const _r2  = 'a49c23d7-6450-43ac-901d-81a6b1f0313a'; // MASCLETÀ
  static const _r3  = 'f52d155c-ea42-459c-905d-2f4f9b2b4919'; // FALLERA
  static const _r4  = 'ff6061b1-1f20-4cdc-ac56-17b1b3b08dac'; // PILOTARI
  static const _r5  = 'f42c552f-65f3-4520-8cac-bc3a83040e32'; // TARONGERO
  static const _r6  = '0d6a1a29-5944-4b58-9d0e-1466a352302c'; // NINOT
  static const _r7  = '824d028e-1c0f-4703-ac61-c923d051c03f'; // SEQUIERO
  static const _r8  = 'ad9be266-849f-4869-837c-30eaa133a40f'; // ARROSSER
  static const _r9  = '14500c6b-940f-4092-9f20-8b65b5896b64'; // MICALET
  static const _r10 = '706dc524-a47a-43b6-a819-452b6ffd3363'; // LLOTGER
  static const _r11 = '67a16f98-c0f6-4e9f-8ae1-1e3b18382edf'; // BUNYOLERO
  static const _r12 = 'ed21d846-3c96-4af0-892c-311064a6884d'; // HORCHATER
  static const _r13 = 'cceae57c-48c8-49b1-94b0-59c51a18484f'; // SOROLLÀ
  static const _r14 = 'c8b1e559-6785-40f6-84cd-dae6176f0ceb'; // BARQUERO
  static const _r15 = '0cab1f1a-21b3-46f8-a367-a309337ea4bf'; // PESCAILLA

  static const List<Map<String, dynamic>> _allDemoUsers = [
    {'id': _demoId,  'email': _demoEmail,        'username': 'WARLORD',    'color': '#FF2D7A', 'influence': 8},
    {'id': _r1,  'email': 'r1@runwar.demo',  'username': 'SOCARRAT',  'color': '#FF8500', 'influence': 5},
    {'id': _r2,  'email': 'r2@runwar.demo',  'username': 'MASCLETÀ',  'color': '#00CFFF', 'influence': 6},
    {'id': _r3,  'email': 'r3@runwar.demo',  'username': 'FALLERA',   'color': '#39FF6B', 'influence': 4},
    {'id': _r4,  'email': 'r4@runwar.demo',  'username': 'PILOTARI',  'color': '#FF4500', 'influence': 3},
    {'id': _r5,  'email': 'r5@runwar.demo',  'username': 'TARONGERO', 'color': '#FFD700', 'influence': 4},
    {'id': _r6,  'email': 'r6@runwar.demo',  'username': 'NINOT',     'color': '#FF69B4', 'influence': 3},
    {'id': _r7,  'email': 'r7@runwar.demo',  'username': 'SEQUIERO',  'color': '#9370DB', 'influence': 3},
    {'id': _r8,  'email': 'r8@runwar.demo',  'username': 'ARROSSER',  'color': '#20B2AA', 'influence': 3},
    {'id': _r9,  'email': 'r9@runwar.demo',  'username': 'MICALET',   'color': '#FF1493', 'influence': 3},
    {'id': _r10, 'email': 'r10@runwar.demo', 'username': 'LLOTGER',   'color': '#00CED1', 'influence': 3},
    {'id': _r11, 'email': 'r11@runwar.demo', 'username': 'BUNYOLERO', 'color': '#ADFF2F', 'influence': 3},
    {'id': _r12, 'email': 'r12@runwar.demo', 'username': 'HORCHATER', 'color': '#FF6347', 'influence': 3},
    {'id': _r13, 'email': 'r13@runwar.demo', 'username': 'SOROLLÀ',   'color': '#BA55D3', 'influence': 3},
    {'id': _r14, 'email': 'r14@runwar.demo', 'username': 'BARQUERO',  'color': '#F0E68C', 'influence': 3},
    {'id': _r15, 'email': 'r15@runwar.demo', 'username': 'PESCAILLA', 'color': '#7FFFD4', 'influence': 3},
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
    // Xàtiva corridor — EW along C/ Xàtiva toward train station
    {'owner': _demoId, 'status': 'owned', 'influence': 7,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3818,39.4660],[-0.3790,39.4656],[-0.3768,39.4658],[-0.3755,39.4663],[-0.3755,39.4670],[-0.3768,39.4675],[-0.3790,39.4677],[-0.3818,39.4673],[-0.3818,39.4660]]]}'},
    // Mercado Central district
    {'owner': _demoId, 'status': 'owned', 'influence': 7,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3800,39.4725],[-0.3782,39.4722],[-0.3770,39.4728],[-0.3768,39.4738],[-0.3775,39.4746],[-0.3795,39.4748],[-0.3808,39.4742],[-0.3810,39.4730],[-0.3800,39.4725]]]}'},
    // Jardines del Real — NS park corridor northeast
    {'owner': _demoId, 'status': 'owned', 'influence': 5,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3682,39.4765],[-0.3668,39.4762],[-0.3658,39.4768],[-0.3655,39.4782],[-0.3660,39.4800],[-0.3672,39.4805],[-0.3685,39.4800],[-0.3688,39.4782],[-0.3685,39.4768],[-0.3682,39.4765]]]}'},

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

    // ── PILOTARI — Garrofera/Patraix south-west: elongated WE oval ~1.3 km ─
    {'owner': _r4, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.4020,39.4545],[-0.3975,39.4510],[-0.3920,39.4495],[-0.3868,39.4502],[-0.3840,39.4528],[-0.3842,39.4562],[-0.3878,39.4585],[-0.3935,39.4592],[-0.3988,39.4580],[-0.4020,39.4558],[-0.4020,39.4545]]]}'},

    // ── TARONGERO — Mestalla stadium district: compact rounded square ~800m
    {'owner': _r5, 'status': 'owned', 'influence': 4,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3655,39.4720],[-0.3615,39.4712],[-0.3568,39.4718],[-0.3540,39.4740],[-0.3542,39.4768],[-0.3572,39.4788],[-0.3618,39.4795],[-0.3658,39.4782],[-0.3675,39.4758],[-0.3665,39.4733],[-0.3655,39.4720]]]}'},

    // ── NINOT — Quatre Carreres south-east: wide shallow rectangle ~1.4 km
    {'owner': _r6, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3792,39.4488],[-0.3728,39.4462],[-0.3658,39.4458],[-0.3608,39.4472],[-0.3592,39.4502],[-0.3600,39.4538],[-0.3648,39.4562],[-0.3718,39.4568],[-0.3778,39.4555],[-0.3810,39.4528],[-0.3812,39.4498],[-0.3792,39.4488]]]}'},

    // ── SEQUIERO — Nazaret port: tall narrow NS strip ~1.5 km ────────────
    {'owner': _r7, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3345,39.4550],[-0.3302,39.4540],[-0.3268,39.4522],[-0.3248,39.4488],[-0.3252,39.4445],[-0.3282,39.4412],[-0.3325,39.4408],[-0.3358,39.4428],[-0.3368,39.4468],[-0.3362,39.4512],[-0.3348,39.4542],[-0.3345,39.4550]]]}'},

    // ── ARROSSER — Trinitat/Poblets Marítims: diagonal coastal strip ~1.3 km
    {'owner': _r8, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3438,39.4730],[-0.3392,39.4718],[-0.3345,39.4702],[-0.3308,39.4682],[-0.3288,39.4652],[-0.3292,39.4622],[-0.3322,39.4610],[-0.3368,39.4618],[-0.3410,39.4638],[-0.3450,39.4660],[-0.3462,39.4692],[-0.3455,39.4718],[-0.3438,39.4730]]]}'},

    // ── MICALET — El Carmen old town: small irregular pentagon ~600m ──────
    {'owner': _r9, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3858,39.4782],[-0.3820,39.4775],[-0.3788,39.4752],[-0.3778,39.4728],[-0.3788,39.4706],[-0.3818,39.4698],[-0.3852,39.4702],[-0.3872,39.4722],[-0.3875,39.4750],[-0.3865,39.4772],[-0.3858,39.4782]]]}'},

    // ── LLOTGER — Extramurs west of old town: medium irregular ~1.0 km ───
    {'owner': _r10, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3968,39.4712],[-0.3918,39.4695],[-0.3872,39.4685],[-0.3838,39.4668],[-0.3830,39.4638],[-0.3848,39.4612],[-0.3895,39.4598],[-0.3948,39.4602],[-0.3990,39.4622],[-0.4008,39.4652],[-0.4000,39.4688],[-0.3978,39.4708],[-0.3968,39.4712]]]}'},

    // ── BUNYOLERO — Jesús south: compact slightly trapezoidal ~900m ───────
    {'owner': _r11, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3862,39.4578],[-0.3812,39.4558],[-0.3758,39.4545],[-0.3718,39.4548],[-0.3700,39.4572],[-0.3705,39.4600],[-0.3742,39.4620],[-0.3798,39.4628],[-0.3848,39.4620],[-0.3872,39.4598],[-0.3862,39.4578]]]}'},

    // ── HORCHATER — Campanar NW: wide trapezoid ~1.4 km ──────────────────
    {'owner': _r12, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.4100,39.4932],[-0.4038,39.4905],[-0.3968,39.4885],[-0.3918,39.4868],[-0.3898,39.4838],[-0.3918,39.4808],[-0.3972,39.4792],[-0.4042,39.4792],[-0.4112,39.4818],[-0.4150,39.4852],[-0.4148,39.4898],[-0.4118,39.4922],[-0.4100,39.4932]]]}'},

    // ── SOROLLÀ — Algirós east-central: irregular pentagon ~1.1 km ───────
    {'owner': _r13, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3595,39.4858],[-0.3545,39.4848],[-0.3490,39.4835],[-0.3445,39.4808],[-0.3428,39.4772],[-0.3440,39.4738],[-0.3482,39.4715],[-0.3542,39.4708],[-0.3595,39.4720],[-0.3630,39.4750],[-0.3628,39.4798],[-0.3608,39.4838],[-0.3595,39.4858]]]}'},

    // ── BARQUERO — Patraix south-west: roughly square ~1.1 km ───────────
    {'owner': _r14, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.4025,39.4648],[-0.3972,39.4628],[-0.3918,39.4612],[-0.3868,39.4608],[-0.3845,39.4580],[-0.3858,39.4550],[-0.3898,39.4532],[-0.3952,39.4528],[-0.4012,39.4542],[-0.4055,39.4572],[-0.4062,39.4610],[-0.4042,39.4638],[-0.4025,39.4648]]]}'},

    // ── PESCAILLA — Cabanyal/Grau coastal: tall NS strip ~1.5 km ─────────
    {'owner': _r15, 'status': 'owned', 'influence': 3,
     'geom': '{"type":"Polygon","coordinates":[[[-0.3338,39.4752],[-0.3298,39.4740],[-0.3265,39.4718],[-0.3248,39.4692],[-0.3248,39.4662],[-0.3265,39.4632],[-0.3295,39.4610],[-0.3330,39.4602],[-0.3362,39.4612],[-0.3380,39.4642],[-0.3380,39.4678],[-0.3368,39.4712],[-0.3352,39.4740],[-0.3338,39.4752]]]}'},
  ];

  Future<bool> redeemTesterCode(String code, String userId) async {
    final upper = code.trim().toUpperCase();
    final validCodes = List.generate(50, (i) => 'FOUNDING-VLCR-${(i + 1).toString().padLeft(3, '0')}').toSet();
    if (!validCodes.contains(upper)) return false;

    final db = DatabaseService.instance.db;
    final existing = await db.query(
      'redeemed_codes',
      where: 'code = ?',
      whereArgs: [upper],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert('redeemed_codes', {
        'code': upper,
        'redeemed_at': now,
        'user_id': userId,
      });
      await txn.update(
        'profiles',
        {'invited_at': now, 'is_tester': 1},
        where: 'id = ?',
        whereArgs: [userId],
      );
    });
    return true;
  }

  /// Clears in-memory session and signs out of Supabase Auth. SQLite untouched.
  Future<void> signOut() async {
    _currentUser = null;
    await SupabaseService.instance.signOut();
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
