import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/private_browser/services/ai_library_assistant_service.dart';
import 'package:V8WorkToolbox/tools/private_browser/services/private_browser_repository.dart';
import 'package:V8WorkToolbox/tools/private_browser/services/private_browser_service.dart';
import 'package:V8WorkToolbox/tools/private_browser/services/private_browser_store.dart';
import 'package:V8WorkToolbox/tools/private_player/services/download_queue_manager.dart';
import 'package:V8WorkToolbox/tools/private_player/services/media_history_store.dart';
import 'package:V8WorkToolbox/tools/registry.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Private Browser Integration & Acceptance Tests', () {
    late Directory tempDir;
    late Database memoryDb;
    late PrivateBrowserRepository repo;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('private_browser_integration_test');
      AppPaths.overrideRootForTesting(tempDir);

      memoryDb = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          final batch = db.batch();
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
          batch.execute('''
            CREATE TABLE IF NOT EXISTS browser_bookmarks (
              id TEXT PRIMARY KEY,
              url TEXT NOT NULL,
              title TEXT NOT NULL,
              favicon_path TEXT,
              created_at TEXT NOT NULL
            )
          ''');
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
          batch.execute('''
            CREATE TABLE IF NOT EXISTS tags (
              id TEXT PRIMARY KEY,
              name TEXT UNIQUE NOT NULL,
              color TEXT,
              usage_count INTEGER DEFAULT 0
            )
          ''');
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
          batch.execute('''
            CREATE TABLE IF NOT EXISTS bookmark_tags (
              bookmark_id TEXT NOT NULL,
              tag_id TEXT NOT NULL,
              PRIMARY KEY (bookmark_id, tag_id),
              FOREIGN KEY (bookmark_id) REFERENCES video_bookmarks (id) ON DELETE CASCADE,
              FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
            )
          ''');
          await batch.commit(noResult: true);
        },
      );

      PrivateBrowserStore.instance.debugOpenOverride = () async => memoryDb;
      await PrivateBrowserStore.instance.resetForTesting(dir: tempDir);
      repo = PrivateBrowserRepository(PrivateBrowserStore.instance);
    });

    tearDown(() async {
      await PrivateBrowserStore.instance.resetForTesting();
      await memoryDb.close();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('10.1 & 10.2 隐私空间工具注册与隔离性检验', () {
      final browserTool = ToolRegistry.findById('private-browser');
      expect(browserTool, isNotNull);
      expect(browserTool!.title, '私密浏览器');
      expect(browserTool.category, ToolCategory.privacy);

      final libraryTool = ToolRegistry.findById('video-library');
      expect(libraryTool, isNotNull);
      expect(libraryTool!.title, '私密视频库');
      expect(libraryTool.category, ToolCategory.privacy);

      // 全局普通搜索中排他性断言 (exclude from global search)
      final publicTools = ToolRegistry.publicTools;
      expect(publicTools.any((t) => t.id == 'private-browser'), isFalse);
      expect(publicTools.any((t) => t.id == 'video-library'), isFalse);
    });

    test('10.3 下载队列集成扩展断言', () {
      final task = DownloadQueueManager.instance.addTask(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: '测试视频',
        triggeredBy: 'browser',
      );
      expect(task.triggeredBy, 'browser');
      expect(task.title, '测试视频');
    });

    test('10.4 播放记录模型扩展与兼容性断言', () {
      final record = MediaPlayRecord(
        id: 'rec-1',
        title: '在线收藏视频',
        urlOrPath: 'https://missav.ai/dm123',
        isOnline: true,
        durationMs: 3600000,
        lastPositionMs: 120000,
        lastPlayedAt: DateTime.now(),
        isFavorite: true,
        sourceUrl: 'https://missav.ai/dm123',
        platform: 'MissAV',
        aiSummary: '这是一段精彩的高清精选视频',
      );

      final json = record.toJson();
      expect(json['platform'], 'MissAV');
      expect(json['sourceUrl'], 'https://missav.ai/dm123');
      expect(json['aiSummary'], contains('精彩的高清精选'));

      final fromJson = MediaPlayRecord.fromJson(json);
      expect(fromJson.platform, 'MissAV');
      expect(fromJson.sourceUrl, 'https://missav.ai/dm123');
      expect(fromJson.aiSummary, record.aiSummary);
    });

    test('10.5 跨会话标签页持久化模拟', () async {
      await repo.saveTabs([
        BrowserTabItem(
          id: 'tab-persisted-1',
          url: 'https://jav.sb',
          title: 'jav.sb 首页',
          createdAt: DateTime.now(),
        ),
      ]);

      final restored = await repo.getTabs();
      expect(restored.length, 1);
      expect(restored.first.url, 'https://jav.sb');
    });

    test('10.8 语义检索与多级分类树 CRUD 完整链路', () async {
      // 创建分类
      final cat = VideoCategoryItem(id: 'cat-music', name: '音乐');
      await repo.addCategory(cat);

      // 创建标签
      final tag = await repo.getOrCreateTag('MV');

      // 创建书签
      final bm = VideoBookmarkItem(
        id: 'v-bm-1',
        title: '周杰伦 晴天 4K 高清 MV 中文字幕',
        url: 'https://youtube.com/watch?v=123',
        platform: 'YouTube',
        categoryId: cat.id,
        tagIds: [tag.id],
        rating: 5,
        notes: '经典回忆',
        aiTags: ['4K', '中文字幕', '音乐'],
        addedAt: DateTime.now(),
      );
      await repo.addVideoBookmark(bm);

      // 验证检索
      final list = await repo.getBookmarksFiltered(categoryId: 'cat-music');
      expect(list.length, 1);
      expect(list.first.title, contains('周杰伦'));
      expect(list.first.aiTags.contains('中文字幕'), isTrue);
    });
  });
}
