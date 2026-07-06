import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Singleton sqflite database for local-only persistence.
/// Opens `runwar_local.db` on first access and creates schema v1.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'runwar_local.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS outbox_queue (
            id              TEXT PRIMARY KEY,
            table_name      TEXT NOT NULL,
            payload         TEXT NOT NULL,
            created_at      INTEGER NOT NULL,
            attempt_count   INTEGER NOT NULL DEFAULT 0,
            next_retry_at   INTEGER NOT NULL DEFAULT 0,
            last_error      TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_outbox_next_retry '
          'ON outbox_queue (next_retry_at)',
        );
        await db.execute('''
          CREATE TABLE IF NOT EXISTS run_scratch (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id     TEXT NOT NULL,
            lat         REAL NOT NULL,
            lng         REAL NOT NULL,
            accuracy    REAL,
            ts          TEXT NOT NULL,
            session_id  TEXT,
            is_mocked   INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_run_scratch_user_ts '
          'ON run_scratch (user_id, ts)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE run_scratch ADD COLUMN session_id TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE run_scratch ADD COLUMN is_mocked INTEGER',
          );
        }
      },
    );
  }
}
