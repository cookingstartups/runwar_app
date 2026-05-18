import 'database_service.dart';

class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  /// AC-12. Returns the row map (7 keys) or null if no row exists.
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    final db = DatabaseService.instance.db;
    final rows = await db.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  /// AC-13. Updates only the supplied non-null fields. All-null is a no-op.
  /// Non-matching userId is a no-op (sqflite UPDATE with no rows affected).
  Future<void> updateProfile(
    String userId, {
    String? username,
    String? city,
    String? color,
  }) async {
    final patch = <String, Object?>{};
    if (username != null) patch['username'] = username;
    if (city != null) patch['city'] = city;
    if (color != null) patch['color'] = color;
    if (patch.isEmpty) return; // AC-13 unwanted behaviour: all-null no-op

    final db = DatabaseService.instance.db;
    await db.update('profiles', patch, where: 'id = ?', whereArgs: [userId]);
  }

  /// AC-14. True iff `invited_at IS NOT NULL`. Missing row → false.
  Future<bool> isInvited(String userId) async {
    final db = DatabaseService.instance.db;
    final rows = await db.query(
      'profiles',
      columns: ['invited_at'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return rows.first['invited_at'] != null;
  }
}
