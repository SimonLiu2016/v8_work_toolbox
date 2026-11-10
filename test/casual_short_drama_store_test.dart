import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/casual_short_drama/services/casual_short_drama_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('CasualShortDramaStore Tests', () {
    late Directory tempDir;
    late Database memoryDb;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('casual_short_drama_store_test');
      AppPaths.overrideRootForTesting(tempDir);

      memoryDb = await openDatabase(
        inMemoryDatabasePath,
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

      CasualShortDramaStore.instance.debugOpenOverride = () async => memoryDb;
    });

    tearDown(() async {
      await CasualShortDramaStore.instance.closeForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('toggleFavorite adds and removes favorite drama', () async {
      final store = CasualShortDramaStore.instance;

      expect(await store.isFavorite(101), isFalse);

      final added = await store.toggleFavorite(
        dramaId: 101,
        title: '都市之仙王赘婿',
        cover: 'https://example.com/cover101.jpg',
        episodeCount: 80,
      );
      expect(added, isTrue);
      expect(await store.isFavorite(101), isTrue);

      final favorites = await store.getFavorites();
      expect(favorites.length, 1);
      expect(favorites.first.dramaId, 101);
      expect(favorites.first.title, '都市之仙王赘婿');
      expect(favorites.first.episodeCount, 80);

      final removed = await store.toggleFavorite(
        dramaId: 101,
        title: '都市之仙王赘婿',
        cover: 'https://example.com/cover101.jpg',
      );
      expect(removed, isFalse);
      expect(await store.isFavorite(101), isFalse);
      expect((await store.getFavorites()).isEmpty, isTrue);
    });

    test('recordHistory and resume progress correctly', () async {
      final store = CasualShortDramaStore.instance;

      expect(await store.getHistory(202), isNull);

      await store.recordHistory(
        dramaId: 202,
        title: '重生之商业大亨',
        cover: 'https://example.com/cover202.jpg',
        lastWatchedEp: 5,
        positionMs: 15400,
        durationMs: 95000,
      );

      final item = await store.getHistory(202);
      expect(item, isNotNull);
      expect(item!.dramaId, 202);
      expect(item.title, '重生之商业大亨');
      expect(item.lastWatchedEp, 5);
      expect(item.positionMs, 15400);

      // 更新进度
      await store.recordHistory(
        dramaId: 202,
        title: '重生之商业大亨',
        cover: 'https://example.com/cover202.jpg',
        lastWatchedEp: 6,
        positionMs: 25000,
        durationMs: 98000,
      );

      final updated = await store.getHistory(202);
      expect(updated!.lastWatchedEp, 6);
      expect(updated.positionMs, 25000);

      // 删除单条与清空全部
      await store.removeHistory(202);
      expect(await store.getHistory(202), isNull);

      await store.recordHistory(
        dramaId: 303,
        title: '战神下山',
        cover: 'https://example.com/cover303.jpg',
        lastWatchedEp: 1,
      );
      expect((await store.getAllHistory()).length, 1);
      await store.clearHistory();
      expect((await store.getAllHistory()).isEmpty, isTrue);
    });
  });
}
