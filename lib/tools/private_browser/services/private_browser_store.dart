import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../services/app_paths.dart';

/// 隐私空间私密浏览器与私密视频收藏库底层 SQLite 存储
class PrivateBrowserStore {
  PrivateBrowserStore._();
  static final PrivateBrowserStore instance = PrivateBrowserStore._();

  Database? _db;

  /// 仅供测试注入指定数据库目录
  @visibleForTesting
  Directory? debugOverrideDir;

  /// 仅供测试：直接注入已打开的内存数据库替身
  @visibleForTesting
  Future<Database> Function()? debugOpenOverride;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  @visibleForTesting
  Future<void> resetForTesting({Directory? dir}) async {
    await closeForTesting();
    debugOverrideDir = dir;
    debugOpenOverride = null;
  }

  @visibleForTesting
  Future<void> closeForTesting() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _initDatabase() async {
    final injected = debugOpenOverride;
    if (injected != null) return await injected();

    final overrideDir = debugOverrideDir;
    final browserDir = overrideDir ?? AppPaths.privateBrowserDir;
    if (!await browserDir.exists()) {
      await browserDir.create(recursive: true);
    }
    final dbPath = p.join(browserDir.path, 'PrivateBrowser.sqlite');

    return await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        _createTables(batch);
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // 后续版本迁移
      },
    );
  }

  void _createTables(Batch batch) {
    // 1.2 浏览器标签页持久化表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS browser_tabs (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        scroll_x REAL DEFAULT 0,
        scroll_y REAL DEFAULT 0,
        order_index INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 1.3 书签表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS browser_bookmarks (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        favicon_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 1.4 首页 N 宫格快捷方式表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS homepage_shortcuts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        favicon_url TEXT,
        favicon_path TEXT,
        order_index INTEGER DEFAULT 0
      )
    ''');

    // 1.5 视频收藏多级分类表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT,
        icon TEXT,
        display_order INTEGER DEFAULT 0,
        FOREIGN KEY (parent_id) REFERENCES categories (id) ON DELETE SET NULL
      )
    ''');

    // 1.6 标签表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        color TEXT,
        usage_count INTEGER DEFAULT 0
      )
    ''');

    // 1.7 视频收藏记录表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS video_bookmarks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        platform TEXT NOT NULL,
        thumbnail_path TEXT,
        duration INTEGER DEFAULT 0,
        added_at TEXT NOT NULL,
        category_id TEXT,
        rating INTEGER DEFAULT 0,
        notes TEXT,
        ai_summary TEXT,
        ai_tags_json TEXT,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
      )
    ''');

    // 1.8 书签与标签多对多关联表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS bookmark_tags (
        bookmark_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (bookmark_id, tag_id),
        FOREIGN KEY (bookmark_id) REFERENCES video_bookmarks (id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
      )
    ''');

    // FTS5 全文搜索虚拟表 (针对 title 与 notes)
    try {
      batch.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS video_bookmarks_fts USING fts5(
          title,
          notes,
          content='video_bookmarks',
          content_rowid='rowid'
        )
      ''');

      // 触发器保持 FTS 与主体表同步
      batch.execute('''
        CREATE TRIGGER IF NOT EXISTS video_bookmarks_ai AFTER INSERT ON video_bookmarks BEGIN
          INSERT INTO video_bookmarks_fts(rowid, title, notes) VALUES (new.rowid, new.title, new.notes);
        END;
      ''');
      batch.execute('''
        CREATE TRIGGER IF NOT EXISTS video_bookmarks_ad AFTER DELETE ON video_bookmarks BEGIN
          INSERT INTO video_bookmarks_fts(video_bookmarks_fts, rowid, title, notes) VALUES('delete', old.rowid, old.title, old.notes);
        END;
      ''');
      batch.execute('''
        CREATE TRIGGER IF NOT EXISTS video_bookmarks_au AFTER UPDATE ON video_bookmarks BEGIN
          INSERT INTO video_bookmarks_fts(video_bookmarks_fts, rowid, title, notes) VALUES('delete', old.rowid, old.title, old.notes);
          INSERT INTO video_bookmarks_fts(rowid, title, notes) VALUES (new.rowid, new.title, new.notes);
        END;
      ''');
    } catch (_) {
      // 容错处理
    }
  }
}
