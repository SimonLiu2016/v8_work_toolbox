import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import '../../../../services/app_paths.dart';
import '../models/novel_models.dart';

/// 小说管理器 SQLite 数据库底座
class NovelDatabase {
  NovelDatabase._();
  static final NovelDatabase instance = NovelDatabase._();

  Database? _db;

  @visibleForTesting
  Directory? debugOverrideDir;

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

    final libDir = debugOverrideDir ?? AppPaths.novelLibraryDir;
    if (!await libDir.exists()) {
      await libDir.create(recursive: true);
    }
    final dbPath = AppPaths.novelDatabaseFile.path;

    return await openDatabase(
      dbPath,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        _createTables(batch);
        await batch.commit();
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE scraper_rules ADD COLUMN catalog_url TEXT');
            await db.execute('ALTER TABLE scraper_rules ADD COLUMN catalog_selector TEXT');
          } catch (_) {}
        }
      },
    );
  }

  void _createTables(Batch batch) {
    // 1. 小说基本元数据表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS novels (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        description TEXT,
        tags TEXT,
        genre TEXT,
        cover_url TEXT,
        source_url TEXT,
        source_site_id TEXT,
        total_chapters INTEGER DEFAULT 0,
        total_word_count INTEGER DEFAULT 0,
        read_count INTEGER DEFAULT 0,
        heat_score REAL DEFAULT 0.0,
        recommend_score REAL DEFAULT 0.0,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_novels_title ON novels(title)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_novels_author ON novels(author)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_novels_genre ON novels(genre)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_novels_heat ON novels(heat_score DESC)');

    // 2. 章节轻量索引表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS novel_chapters (
        id TEXT PRIMARY KEY,
        novel_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        title TEXT NOT NULL,
        word_count INTEGER DEFAULT 0,
        summary TEXT,
        origin_chapter_url TEXT,
        status TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (novel_id) REFERENCES novels(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_chapters_novel_idx ON novel_chapters(novel_id, chapter_index)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_chapters_origin_url ON novel_chapters(novel_id, origin_chapter_url)');

    // 3. 站点采集规则表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS scraper_rules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        enable_bypass INTEGER DEFAULT 0,
        toc_url_pattern TEXT,
        toc_selector TEXT,
        content_selector TEXT,
        title_selector TEXT,
        catalog_url TEXT,
        catalog_selector TEXT,
        remove_selectors TEXT,
        custom_headers TEXT,
        request_delay_ms INTEGER DEFAULT 500,
        is_cron_enabled INTEGER DEFAULT 0,
        cron_expression TEXT,
        last_crawled_at TEXT
      )
    ''');
  }

  // ---------------------------------------------------------------------------
  // 小说 CRUD
  // ---------------------------------------------------------------------------

  Future<void> insertOrUpdateNovel(NovelMetadata novel) async {
    final db = await database;
    final count = await db.update(
      'novels',
      novel.toMap(),
      where: 'id = ?',
      whereArgs: [novel.id],
    );
    if (count == 0) {
      await db.insert(
        'novels',
        novel.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<NovelMetadata?> getNovelById(String id) async {
    final db = await database;
    final results = await db.query(
      'novels',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return NovelMetadata.fromMap(results.first);
  }

  Future<List<NovelMetadata>> queryNovels({
    String? query,
    String? genre,
    String? tag,
    String orderBy = 'updated_at DESC',
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (query != null && query.trim().isNotEmpty) {
      whereClauses.add('(title LIKE ? OR author LIKE ? OR description LIKE ?)');
      final pattern = '%${query.trim()}%';
      whereArgs.addAll([pattern, pattern, pattern]);
    }

    if (genre != null && genre.trim().isNotEmpty && genre != '全部') {
      whereClauses.add('genre = ?');
      whereArgs.add(genre.trim());
    }

    if (tag != null && tag.trim().isNotEmpty) {
      whereClauses.add('tags LIKE ?');
      whereArgs.add('%"${tag.trim()}"%');
    }

    final where = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final results = await db.query(
      'novels',
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    return results.map(NovelMetadata.fromMap).toList();
  }

  Future<void> deleteNovel(String id) async {
    final db = await database;
    await db.delete('novels', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // 章节索引 CRUD
  // ---------------------------------------------------------------------------

  Future<void> insertOrUpdateChapterIndex(NovelChapterIndex chapter) async {
    final db = await database;
    await db.insert(
      'novel_chapters',
      chapter.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> batchInsertChapterIndices(List<NovelChapterIndex> chapters) async {
    final db = await database;
    final batch = db.batch();
    for (final c in chapters) {
      batch.insert(
        'novel_chapters',
        c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<NovelChapterIndex>> getChapterIndices(String novelId) async {
    final db = await database;
    final results = await db.query(
      'novel_chapters',
      where: 'novel_id = ?',
      whereArgs: [novelId],
      orderBy: 'chapter_index ASC',
    );
    return results.map(NovelChapterIndex.fromMap).toList();
  }

  Future<NovelChapterIndex?> getChapterIndexByNumber(String novelId, int chapterIndex) async {
    final db = await database;
    final results = await db.query(
      'novel_chapters',
      where: 'novel_id = ? AND chapter_index = ?',
      whereArgs: [novelId, chapterIndex],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return NovelChapterIndex.fromMap(results.first);
  }

  Future<void> deleteChapterIndex(String novelId, int chapterIndex) async {
    final db = await database;
    await db.delete(
      'novel_chapters',
      where: 'novel_id = ? AND chapter_index = ?',
      whereArgs: [novelId, chapterIndex],
    );
  }

  // ---------------------------------------------------------------------------
  // 站点源规则 CRUD
  // ---------------------------------------------------------------------------

  Future<void> insertOrUpdateRule(SiteScraperRule rule) async {
    final db = await database;
    await db.insert(
      'scraper_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SiteScraperRule>> getAllRules() async {
    final db = await database;
    final results = await db.query('scraper_rules', orderBy: 'name ASC');
    return results.map(SiteScraperRule.fromMap).toList();
  }

  Future<SiteScraperRule?> getRuleById(String id) async {
    final db = await database;
    final results = await db.query('scraper_rules', where: 'id = ?', whereArgs: [id], limit: 1);
    if (results.isEmpty) return null;
    return SiteScraperRule.fromMap(results.first);
  }

  Future<void> deleteRule(String id) async {
    final db = await database;
    await db.delete('scraper_rules', where: 'id = ?', whereArgs: [id]);
  }
}
