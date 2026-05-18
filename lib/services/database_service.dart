import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;
  Completer<void>? _initCompleter;

  /// Throws StateError if accessed before init() completes (AC-6 unwanted behaviour).
  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError(
        'DatabaseService.db accessed before init() completed. '
        'Await DatabaseService.instance.init() in main() before runApp.',
      );
    }
    return d;
  }

  /// Idempotent. Concurrent callers all await the same Future
  /// (AC-1 idempotency + AC-6 single-connection invariant).
  Future<void> init() {
    final existing = _initCompleter;
    if (existing != null) return existing.future;
    final c = Completer<void>();
    _initCompleter = c;
    _doInit().then((_) => c.complete()).catchError((Object e, StackTrace s) {
      _initCompleter = null; // allow retry on failure
      c.completeError(e, s);
    });
    return c.future;
  }

  Future<void> _doInit() async {
    final dbPath = p.join(await getDatabasesPath(), 'runwar.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onOpen: (db) async {
        // AC-1 unwanted behaviour: second init() against an existing file
        // must complete without error and without data loss. CREATE TABLE
        // IF NOT EXISTS is a no-op when tables already exist.
        await _createSchema(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id          TEXT PRIMARY KEY,
        email       TEXT UNIQUE NOT NULL,
        password    TEXT NOT NULL,
        created_at  TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS profiles (
        id               TEXT PRIMARY KEY,
        username         TEXT NOT NULL DEFAULT '',
        city             TEXT NOT NULL DEFAULT '',
        color            TEXT NOT NULL DEFAULT '#FF7A00',
        influence_level  INTEGER NOT NULL DEFAULT 1,
        invited_at       TEXT,
        created_at       TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS zones (
        id          TEXT PRIMARY KEY,
        owner_id    TEXT NOT NULL,
        city        TEXT NOT NULL,
        geom_json   TEXT NOT NULL,
        influence   INTEGER NOT NULL DEFAULT 1,
        status      TEXT NOT NULL DEFAULT 'owned',
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS runs (
        id          TEXT PRIMARY KEY,
        user_id     TEXT NOT NULL,
        city        TEXT NOT NULL,
        track_json  TEXT NOT NULL,
        started_at  TEXT NOT NULL,
        closed_at   TEXT NOT NULL,
        zone_id     TEXT,
        created_at  TEXT NOT NULL
      )
    ''');
  }
}
