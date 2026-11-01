import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Central SQLite Database management for PureTube v3.0.
/// Manages subscriptions, custom playlists, playlist items, and watch history.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static Database? _database;
  static Completer<Database>? _initCompleter;

  /// Returns the singleton database instance, initializing it if necessary.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = null;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    final completer = Completer<Database>();
    _initCompleter = completer;

    try {
      _database = await _initDatabase();
      completer.complete(_database!);
      return _database!;
    } catch (e, st) {
      _initCompleter = null;
      completer.completeError(e, st);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'pure_tube.db');

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        // Enable foreign key constraints for SQLite
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Subscriptions Table
    await db.execute('''
      CREATE TABLE subscriptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT UNIQUE,
        channel_name TEXT,
        avatar_url TEXT,
        subscriber_count TEXT,
        created_at INTEGER
      )
    ''');

    // 2. Playlists Table
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        description TEXT,
        created_at INTEGER
      )
    ''');

    // 3. Playlist Items Table
    await db.execute('''
      CREATE TABLE playlist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER,
        video_id TEXT,
        title TEXT,
        author TEXT,
        thumbnail_url TEXT,
        duration_ms INTEGER,
        added_at INTEGER,
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE
      )
    ''');

    // 4. Watch History Table
    await db.execute('''
      CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_id TEXT UNIQUE,
        title TEXT,
        author TEXT,
        thumbnail_url TEXT,
        position_ms INTEGER,
        duration_ms INTEGER,
        updated_at INTEGER
      )
    ''');

    // Indices for optimal query speed
    await db.execute('CREATE INDEX IF NOT EXISTS idx_playlist_items_playlist_id ON playlist_items(playlist_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_history_updated_at ON history(updated_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_subscriptions_channel_id ON subscriptions(channel_id)');
  }

  /// Closes database connection cleanly if open.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
    _initCompleter = null;
  }
}
