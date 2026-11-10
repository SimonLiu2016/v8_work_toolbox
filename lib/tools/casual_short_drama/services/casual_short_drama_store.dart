import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../services/app_paths.dart';
import '../models/drama_models.dart';

/// 隐私空间随心短剧本地 SQLite 存储管理器
/// 负责管理无痕游客模式下的私密收藏夹与断点播放历史进度
class CasualShortDramaStore {
  CasualShortDramaStore._();
  static final CasualShortDramaStore instance = CasualShortDramaStore._();

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

    final overrideDir = debugOverrideDir;
    final dir = overrideDir ?? AppPaths.casualShortDramaDir;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dbPath = p.join(dir.path, 'CasualShortDrama.sqlite');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        final batch = db.batch();
        batch.execute('''
          CREATE TABLE drama_favorites (
            drama_id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            cover TEXT NOT NULL,
            episode_count INTEGER NOT NULL DEFAULT 0,
            added_at INTEGER NOT NULL
          )
        ''');

        batch.execute('''
          CREATE TABLE drama_history (
            drama_id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            cover TEXT NOT NULL,
            last_watched_ep INTEGER NOT NULL DEFAULT 1,
            position_ms INTEGER NOT NULL DEFAULT 0,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
          )
        ''');
        await batch.commit(noResult: true);
      },
    );
  }

  // ── 收藏管理 ──────────────────────────────────────────

  /// 查询短剧是否已收藏
  Future<bool> isFavorite(int dramaId) async {
    final db = await database;
    final res = await db.query(
      'drama_favorites',
      where: 'drama_id = ?',
      whereArgs: [dramaId],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  /// 切换收藏状态（已收藏则取消，未收藏则加入）
  Future<bool> toggleFavorite({
    required int dramaId,
    required String title,
    required String cover,
    int episodeCount = 0,
  }) async {
    final db = await database;
    final fav = await isFavorite(dramaId);
    if (fav) {
      await db.delete(
        'drama_favorites',
        where: 'drama_id = ?',
        whereArgs: [dramaId],
      );
      return false;
    } else {
      await db.insert(
        'drama_favorites',
        {
          'drama_id': dramaId,
          'title': title,
          'cover': cover,
          'episode_count': episodeCount,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    }
  }

  /// 从收藏列表中移除
  Future<void> removeFavorite(int dramaId) async {
    final db = await database;
    await db.delete(
      'drama_favorites',
      where: 'drama_id = ?',
      whereArgs: [dramaId],
    );
  }

  /// 获取所有收藏列表（按添加时间倒序）
  Future<List<DramaFavoriteItem>> getFavorites() async {
    final db = await database;
    final rows = await db.query(
      'drama_favorites',
      orderBy: 'added_at DESC',
    );
    return rows.map((e) => DramaFavoriteItem.fromMap(e)).toList();
  }

  // ── 历史进度管理 ──────────────────────────────────────────

  /// 记录或更新短剧观看进度
  Future<void> recordHistory({
    required int dramaId,
    required String title,
    required String cover,
    required int lastWatchedEp,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    final db = await database;
    await db.insert(
      'drama_history',
      {
        'drama_id': dramaId,
        'title': title,
        'cover': cover,
        'last_watched_ep': lastWatchedEp,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取单部短剧的历史记录
  Future<DramaHistoryItem?> getHistory(int dramaId) async {
    final db = await database;
    final rows = await db.query(
      'drama_history',
      where: 'drama_id = ?',
      whereArgs: [dramaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DramaHistoryItem.fromMap(rows.first);
  }

  /// 获取全部历史播放记录（按最近观看时间倒序）
  Future<List<DramaHistoryItem>> getAllHistory() async {
    final db = await database;
    final rows = await db.query(
      'drama_history',
      orderBy: 'updated_at DESC',
    );
    return rows.map((e) => DramaHistoryItem.fromMap(e)).toList();
  }

  /// 删除某部短剧的历史记录
  Future<void> removeHistory(int dramaId) async {
    final db = await database;
    await db.delete(
      'drama_history',
      where: 'drama_id = ?',
      whereArgs: [dramaId],
    );
  }

  /// 清空全部历史记录
  Future<void> clearHistory() async {
    final db = await database;
    await db.delete('drama_history');
  }
}
