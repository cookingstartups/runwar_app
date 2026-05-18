import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // In-memory session map. Lost on process kill. I-5 / AC-16 invariant.
  Map<String, dynamic>? _currentUser;

  /// AC-7. Inserts one `users` row + one `profiles` row in a transaction.
  /// Returns the new user map (id/email/created_at) or null on duplicate email.
  /// Atomic — failure of either insert rolls back both (edge case: two rapid
  /// signUps with same email).
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
      // AC-7 unwanted behaviour: duplicate email returns null without throwing.
      if (e.isUniqueConstraintError()) return null;
      rethrow;
    }

    _currentUser = {'id': id, 'email': email, 'created_at': nowIso};
    return _currentUser;
  }

  /// AC-8. Returns user map on credential match; null otherwise. Never throws.
  Future<Map<String, dynamic>?> signIn(String email, String password) async {
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

  /// AC-9. Idempotent — clears in-memory session only. SQLite untouched.
  Future<void> signOut() async {
    _currentUser = null;
  }

  /// AC-10. PoC no-op. Console log only. No network, no email.
  Future<void> sendPasswordReset(String email) async {
    debugPrint('[AuthService] sendPasswordReset($email) — PoC no-op');
  }

  /// AC-11. Synchronous (I-1 invariant). Never hits DB or network.
  Map<String, dynamic>? getCurrentUser() => _currentUser;

  // ── UUID v4 (RFC 4122) — inline to honour AC-5's enumerated 7-package list.
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
