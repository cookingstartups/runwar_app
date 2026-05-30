import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'simulation_service.dart';

class WorldResetService {
  WorldResetService._();
  static final WorldResetService instance = WorldResetService._();

  static const resetInterval = Duration(hours: 6);
  static const _prefKey = 'world_reset_at';

  Future<DateTime?> lastResetAt() async {
    final db = DatabaseService.instance.db;
    final rows = await db.query('prefs', where: 'key = ?', whereArgs: [_prefKey], limit: 1);
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  Future<bool> needsReset() async {
    final last = await lastResetAt();
    if (last == null) return true;
    return DateTime.now().toUtc().difference(last) >= resetInterval;
  }

  Future<void> doReset(String city) async {
    await SimulationService.instance.resetWorld();
    final db = DatabaseService.instance.db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'prefs',
      {'key': _prefKey, 'value': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('[WorldReset] reset complete for $city at $now');
  }

  Stream<Duration> countdown(String city) {
    return Stream.periodic(const Duration(seconds: 1), (_) async {
      final last = await lastResetAt();
      if (last == null) return Duration.zero;
      final elapsed = DateTime.now().toUtc().difference(last);
      final remaining = resetInterval - elapsed;
      return remaining.isNegative ? Duration.zero : remaining;
    }).asyncMap((f) => f);
  }
}
