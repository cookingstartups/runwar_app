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
        await txn.insert('users', {
          'id': _demoId,
          'email': _demoEmail,
          'password': '123456',
          'created_at': nowIso,
        });
        await txn.insert('profiles', {
          'id': _demoId,
          'username': 'WARLORD',
          'city': 'Valencia',
          'color': '#FF2D7A',
          'influence_level': 8,
          'invited_at': nowIso,
          'created_at': nowIso,
        });
        // Seed 3 owned zones in Valencia
        for (final z in _demoZones) {
          await txn.insert('zones', {
            'id': _uuidV4(),
            'owner_id': _demoId,
            'city': 'Valencia',
            'geom_json': z,
            'status': 'owned',
            'influence': 8,
            'created_at': nowIso,
            'updated_at': nowIso,
          });
        }
      });
    }

    _currentUser = {'id': _demoId, 'email': _demoEmail, 'created_at': nowIso};
    return _currentUser!;
  }

  // Three GeoJSON polygons around Valencia city centre (lng first — RFC 7946).
  static const List<String> _demoZones = [
    // Plaza del Ayuntamiento
    '{"type":"Polygon","coordinates":[[[-0.3770,39.4695],[-0.3750,39.4695],[-0.3750,39.4710],[-0.3770,39.4710],[-0.3770,39.4695]]]}',
    // El Carmen / Barrio histórico
    '{"type":"Polygon","coordinates":[[[-0.3810,39.4730],[-0.3785,39.4730],[-0.3785,39.4750],[-0.3810,39.4750],[-0.3810,39.4730]]]}',
    // Ciudad de las Artes y Ciencias
    '{"type":"Polygon","coordinates":[[[-0.3535,39.4535],[-0.3495,39.4535],[-0.3495,39.4560],[-0.3535,39.4560],[-0.3535,39.4535]]]}',
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
