import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/private_browser/services/private_browser_store.dart';
import 'package:V8WorkToolbox/tools/private_browser/services/private_browser_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('PrivateBrowser Store & Repository Tests', () {
    late Directory tempDir;
    late Database memoryDb;
    late PrivateBrowserRepository repo;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('private_browser_test');
      AppPaths.overrideRootForTesting(tempDir);

      // 创建纯内存 SQLite 供测试
      memoryDb = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          // 手动执行 PrivateBrowserStore 中的建表逻辑
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

    test('1. 标签页持久化 CRUD 往返一致性', () async {
      final tab1 = BrowserTabItem(
        id: 'tab-1',
        url: 'https://youtube.com',
        title: 'YouTube',
        orderIndex: 0,
        createdAt: DateTime.now(),
      );
      final tab2 = BrowserTabItem(
        id: 'tab-2',
        url: 'https://missav.ai',
        title: 'MissAV',
        orderIndex: 1,
        createdAt: DateTime.now(),
      );

      await repo.saveTabs([tab1, tab2]);

      final loaded = await repo.getTabs();
      expect(loaded.length, 2);
      expect(loaded[0].id, 'tab-1');
      expect(loaded[0].url, 'https://youtube.com');
      expect(loaded[1].title, 'MissAV');

      // 更新 tab-1
      await repo.updateTab(loaded[0].copyWith(title: 'YouTube Video Page'));
      final updated = await repo.getTabs();
      expect(updated[0].title, 'YouTube Video Page');

      // 删除 tab-2
      await repo.removeTab('tab-2');
      final remaining = await repo.getTabs();
      expect(remaining.length, 1);
      expect(remaining[0].id, 'tab-1');
    });

    test('2. 书签 CRUD 与已收藏查询', () async {
      final bm = BrowserBookmarkItem(
        id: 'bm-1',
        url: 'https://jav.sb',
        title: 'Jav Library',
        createdAt: DateTime.now(),
      );
      expect(await repo.isBookmarked('https://jav.sb'), isFalse);

      await repo.addBookmark(bm);
      expect(await repo.isBookmarked('https://jav.sb'), isTrue);

      final list = await repo.getBookmarks();
      expect(list.length, 1);
      expect(list.first.title, 'Jav Library');

      await repo.removeBookmark('bm-1');
      expect(await repo.isBookmarked('https://jav.sb'), isFalse);
    });

    test('3. N 宫格快捷方式预置与管理', () async {
      final initial = await repo.getShortcuts();
      expect(initial.length, greaterThanOrEqualTo(6));
      expect(initial.any((s) => s.name == 'YouTube'), isTrue);

      final custom = HomepageShortcutItem(
        id: 'custom-1',
        name: 'Custom Portal',
        url: 'https://example.com',
        orderIndex: 99,
      );
      await repo.addShortcut(custom);

      final list = await repo.getShortcuts();
      expect(list.any((s) => s.name == 'Custom Portal'), isTrue);

      await repo.removeShortcut('custom-1');
      final afterRemove = await repo.getShortcuts();
      expect(afterRemove.any((s) => s.name == 'Custom Portal'), isFalse);
    });

    test('4. 分类树层级与级联解除关联', () async {
      final parentCat = VideoCategoryItem(id: 'cat-jp', name: '日本');
      final subCat = VideoCategoryItem(id: 'cat-av', name: 'AV系列', parentId: 'cat-jp');

      await repo.addCategory(parentCat);
      await repo.addCategory(subCat);

      var cats = await repo.getCategories();
      expect(cats.length, 2);

      // 添加一个属于子分类的视频书签
      final bookmark = VideoBookmarkItem(
        id: 'v-1',
        title: '测试片 1',
        url: 'https://test.com/v1',
        platform: 'TestPlatform',
        categoryId: 'cat-av',
        addedAt: DateTime.now(),
      );
      await repo.addVideoBookmark(bookmark);

      // 删除子分类 -> 视频的 categoryId 应被 SET NULL，而不级联删除视频
      await repo.deleteCategory('cat-av');
      final afterCatDelete = await repo.getVideoBookmarkById('v-1');
      expect(afterCatDelete, isNotNull);
      expect(afterCatDelete!.categoryId, isNull);
    });

    test('5. 标签创建、多对多绑定与 usage_count 维护', () async {
      final tag1 = await repo.getOrCreateTag('女优');
      final tag2 = await repo.getOrCreateTag('中文字幕');

      expect(tag1.name, '女优');
      expect(tag2.name, '中文字幕');

      final v = VideoBookmarkItem(
        id: 'v-tags-test',
        title: '高质量影片',
        url: 'https://test.com/v2',
        platform: 'YouTube',
        addedAt: DateTime.now(),
        tagIds: [tag1.id, tag2.id],
      );
      await repo.addVideoBookmark(v);

      var tags = await repo.getTags();
      final t1Loaded = tags.firstWhere((t) => t.id == tag1.id);
      expect(t1Loaded.usageCount, 1);

      // 按标签筛选
      final filtered = await repo.getBookmarksFiltered(tagId: tag1.id);
      expect(filtered.length, 1);
      expect(filtered.first.id, 'v-tags-test');
      expect(filtered.first.tagIds.contains(tag2.id), isTrue);

      // 删除视频 -> usageCount 应减 1
      await repo.deleteVideoBookmark('v-tags-test');
      tags = await repo.getTags();
      final t1After = tags.firstWhere((t) => t.id == tag1.id);
      expect(t1After.usageCount, 0);
    });
  });
}
