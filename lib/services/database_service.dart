import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;
  Completer<void>? _initCompleter;

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

  /// Idempotent — concurrent callers all await the same Future.
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
      version: 9,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateToV3(db);
        }
        if (oldVersion < 4) {
          await _migrateToV4(db);
        }
        if (oldVersion < 5) {
          await _migrateToV5(db);
        }
        if (oldVersion < 6) {
          await _migrateToV6(db);
        }
        if (oldVersion < 7) {
          await _migrateToV7(db);
        }
        if (oldVersion < 8) {
          await _migrateToV8(db);
        }
        if (oldVersion < 9) {
          await _migrateToV9(db);
        }
      },
      onOpen: (db) async {
        // CREATE TABLE IF NOT EXISTS is a no-op when tables already exist.
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
        id                    TEXT PRIMARY KEY,
        username              TEXT NOT NULL DEFAULT '',
        city                  TEXT NOT NULL DEFAULT '',
        color                 TEXT NOT NULL DEFAULT '#FF7A00',
        influence_level       INTEGER NOT NULL DEFAULT 1,
        invited_at            TEXT,
        is_tester             INTEGER NOT NULL DEFAULT 0,
        phone                 TEXT,
        created_at            TEXT NOT NULL,
        trial_started_at      TEXT,
        trial_days_remaining  INTEGER NOT NULL DEFAULT 14,
        trial_last_tick_date  TEXT,
        freeze_tokens                INTEGER NOT NULL DEFAULT 2,
        freeze_refreshed_at          TEXT,
        current_streak               INTEGER NOT NULL DEFAULT 0,
        first_mission_completed_at   TEXT,
        first_attack_completed_at    TEXT,
        streak_started_at            TEXT,
        is_bot                       INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS zones (
        id                TEXT PRIMARY KEY,
        owner_id          TEXT NOT NULL,
        city              TEXT NOT NULL,
        geom_json         TEXT NOT NULL,
        influence         REAL NOT NULL DEFAULT 1,
        status            TEXT NOT NULL DEFAULT 'owned',
        contested_by_id   TEXT,
        created_at        TEXT NOT NULL,
        updated_at        TEXT NOT NULL,
        credits_earned    REAL NOT NULL DEFAULT 0,
        last_income_at    TEXT,
        last_active_at    TEXT,
        dispute_at        TEXT,
        parent_id         TEXT
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prefs (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS redeemed_codes (
        code        TEXT PRIMARY KEY,
        redeemed_at TEXT NOT NULL,
        user_id     TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id         TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        props_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feedback (
        id         TEXT PRIMARY KEY,
        trigger    TEXT NOT NULL,
        rating     TEXT NOT NULL,
        note       TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS city_waitlists (
        user_id    TEXT NOT NULL,
        city_slug  TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (user_id, city_slug)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_mission_progress (
        id           TEXT PRIMARY KEY,
        user_id      TEXT NOT NULL,
        date         TEXT NOT NULL,
        slug         TEXT NOT NULL,
        progress     INTEGER NOT NULL DEFAULT 0,
        target       INTEGER NOT NULL DEFAULT 1,
        completed_at TEXT,
        synced_at    TEXT,
        UNIQUE(user_id, date, slug)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_dmp_local_date
        ON daily_mission_progress(user_id, date)
    ''');
  }

  Future<void> _migrateToV6(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS city_waitlists (
          user_id    TEXT NOT NULL,
          city_slug  TEXT NOT NULL,
          created_at TEXT NOT NULL,
          PRIMARY KEY (user_id, city_slug)
        )
      ''');
    } catch (_) {}
  }

  Future<void> _migrateToV5(Database db) async {
    try {
      await db.execute('ALTER TABLE profiles ADD COLUMN phone TEXT');
    } catch (_) {}
  }

  Future<void> _migrateToV4(Database db) async {
    // influence → REAL (SQLite ALTER COLUMN not supported; add new columns only;
    // existing INTEGER values are read back as REAL automatically in Dart)
    for (final col in [
      'ALTER TABLE zones ADD COLUMN credits_earned REAL NOT NULL DEFAULT 0',
      'ALTER TABLE zones ADD COLUMN last_income_at TEXT',
      'ALTER TABLE zones ADD COLUMN last_active_at TEXT',
      'ALTER TABLE zones ADD COLUMN dispute_at TEXT',
      'ALTER TABLE zones ADD COLUMN parent_id TEXT',
    ]) {
      try {
        await db.execute(col);
      } catch (_) {}
    }
  }

  Future<void> _migrateToV3(Database db) async {
    try {
      await db.execute('ALTER TABLE zones ADD COLUMN contested_by_id TEXT');
    } catch (_) {}
  }

  Future<void> _migrateToV7(Database db) async {
    for (final col in [
      'ALTER TABLE profiles ADD COLUMN trial_started_at TEXT',
      'ALTER TABLE profiles ADD COLUMN trial_days_remaining INTEGER NOT NULL DEFAULT 14',
      'ALTER TABLE profiles ADD COLUMN trial_last_tick_date TEXT',
      'ALTER TABLE profiles ADD COLUMN freeze_tokens INTEGER NOT NULL DEFAULT 2',
      'ALTER TABLE profiles ADD COLUMN freeze_refreshed_at TEXT',
      'ALTER TABLE profiles ADD COLUMN current_streak INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await db.execute(col);
      } catch (_) {}
    }
  }

  Future<void> _migrateToV8(Database db) async {
    for (final col in [
      'ALTER TABLE profiles ADD COLUMN first_mission_completed_at TEXT',
      'ALTER TABLE profiles ADD COLUMN first_attack_completed_at TEXT',
      'ALTER TABLE profiles ADD COLUMN streak_started_at TEXT',
      'ALTER TABLE profiles ADD COLUMN is_bot INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await db.execute(col);
      } catch (_) {}
    }
    // Backfill bot flag for demo seed accounts.
    try {
      await db.execute(
        "UPDATE profiles SET is_bot = 1 WHERE EXISTS "
        "(SELECT 1 FROM users WHERE users.id = profiles.id AND users.email LIKE '%@runwar.demo')",
      );
    } catch (_) {}
  }

  Future<void> _migrateToV9(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_mission_progress (
          id           TEXT PRIMARY KEY,
          user_id      TEXT NOT NULL,
          date         TEXT NOT NULL,
          slug         TEXT NOT NULL,
          progress     INTEGER NOT NULL DEFAULT 0,
          target       INTEGER NOT NULL DEFAULT 1,
          completed_at TEXT,
          synced_at    TEXT,
          UNIQUE(user_id, date, slug)
        )
      ''');
    } catch (_) {}
    try {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_dmp_local_date
          ON daily_mission_progress(user_id, date)
      ''');
    } catch (_) {}
  }

  Future<void> _migrateToV2(Database db) async {
    try {
      await db.execute('ALTER TABLE profiles ADD COLUMN is_tester INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prefs (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS redeemed_codes (
        code        TEXT PRIMARY KEY,
        redeemed_at TEXT NOT NULL,
        user_id     TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id         TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        props_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feedback (
        id         TEXT PRIMARY KEY,
        trigger    TEXT NOT NULL,
        rating     TEXT NOT NULL,
        note       TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }
}
