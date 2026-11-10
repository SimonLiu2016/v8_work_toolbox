import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/novel_manager/models/novel_models.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/novel_database.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/site_scraper_rule_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('NovelDatabase 版本迁移与 category_map 持久化自愈', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('novel_db_test_');
      AppPaths.overrideRootForTesting(tempDir);
      await NovelDatabase.instance.resetForTesting(dir: tempDir);
    });

    tearDown(() async {
      await NovelDatabase.instance.closeForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('从版本 2 升级到版本 3 自动添加 category_map 列并完整保留老规则', () async {
      final dbFile = AppPaths.novelDatabaseFile;
      await dbFile.parent.create(recursive: true);

      // 1. 手动创建一个 Version 2 的旧数据库，无 category_map 列
      final oldDb = await openDatabase(
        dbFile.path,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE scraper_rules (
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
          // 插入一条用户的旧规则
          await db.insert('scraper_rules', {
            'id': 'my_custom_site',
            'name': '用户自定义旧站点',
            'base_url': 'https://my-novel-site.com',
          });
        },
      );
      await oldDb.close();

      // 2. 通过 NovelDatabase 打开（自动触发 onUpgrade 到 version 3）
      final novelDb = NovelDatabase.instance;
      final db = await novelDb.database;

      // 验证版本号已更新为 3
      final version = await db.getVersion();
      expect(version, 3);

      // 验证旧规则依然存在
      final oldRule = await novelDb.getRuleById('my_custom_site');
      expect(oldRule, isNotNull);
      expect(oldRule!.name, '用户自定义旧站点');

      // 3. 验证可以无损存取带有 categoryMap 的新规则
      const newRule = SiteScraperRule(
        id: 'new_site_with_cat',
        name: '带有分类字典的新站点',
        baseUrl: 'https://new-site.com',
        categoryMap: {
          '1': '玄幻',
          '2': '修真',
        },
      );

      await novelDb.insertOrUpdateRule(newRule);

      final fetchedNewRule = await novelDb.getRuleById('new_site_with_cat');
      expect(fetchedNewRule, isNotNull);
      expect(fetchedNewRule!.categoryMap['1'], '玄幻');
      expect(fetchedNewRule.categoryMap['2'], '修真');
    });

    test('SiteScraperRuleService.getRules() 在注入新规则时平滑成功且不丢失老规则', () async {
      final dbFile = AppPaths.novelDatabaseFile;
      await dbFile.parent.create(recursive: true);

      // 模拟老数据库已存在 szlajc
      final oldDb = await openDatabase(
        dbFile.path,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE scraper_rules (
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
          await db.insert('scraper_rules', {
            'id': 'szlajc',
            'name': '神州中文网',
            'base_url': 'https://www.szlajc.com',
          });
        },
      );
      await oldDb.close();

      final service = SiteScraperRuleService.instance;
      final rules = await service.getRules();

      // 必须包含老规则 szlajc 和系统自动补充的 piaotia
      expect(rules.any((r) => r.id == 'szlajc'), isTrue);
      expect(rules.any((r) => r.id == 'piaotia'), isTrue);
    });
  });
}
