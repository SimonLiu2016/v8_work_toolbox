import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/novel_selector_dialog.dart';
import 'package:V8WorkToolbox/tools/novel_manager/models/novel_models.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/novel_database.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/novel_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late NovelRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_writers_room_novel_test_');
    AppPaths.overrideRootForTesting(tempDir);
    repo = NovelRepository.instance;
  });

  tearDown(() async {
    await NovelDatabase.instance.closeForTesting();
    AppPaths.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('NovelSelectionResult 正文自愈与长文采样 (fix-writers-room-novel-selection-and-text-loading)', () {
    test('若已有 combinedText 则 loadCombinedText 直接返回现有正文', () async {
      const presetText = '直接传入的预设原著大纲与分镜文本';
      final result = NovelSelectionResult(
        novel: NovelMetadata(
          id: 'test_novel_01',
          title: '预设测试小说',
          author: '作者',
          status: NovelStatus.ongoing,
          genre: '仙侠',
          tags: const [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        selectedChapterIndices: const [],
        combinedText: presetText,
      );

      final loaded = await result.loadCombinedText();
      expect(loaded, presetText);
    });

    test('当 combinedText 为空时，loadCombinedText 自动从 NovelRepository 批量提取章节正文', () async {
      final novel = NovelMetadata(
        id: 'novel_xianxia_101',
        title: '凡人修真录',
        author: '忘语',
        status: NovelStatus.completed,
        genre: '修仙',
        tags: const ['修真', '热血'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.saveNovel(novel);

      // 保存两章正文
      await repo.saveChapter(
        novelId: novel.id,
        chapterIndex: 1,
        title: '第一章 拜入七玄',
        content: '少年韩立背负布包，登上了七玄门的山门台阶。',
      );
      await repo.saveChapter(
        novelId: novel.id,
        chapterIndex: 2,
        title: '第二章 墨大夫',
        content: '神手谷内草药飘香，墨大夫面色枯槁坐在竹椅上。',
      );

      // 1. 全本引用（selectedChapterIndices 为空）
      final fullBookResult = NovelSelectionResult(
        novel: novel,
        selectedChapterIndices: const [],
        combinedText: '',
      );

      final fullLoaded = await fullBookResult.loadCombinedText();
      expect(fullLoaded, contains('=== 第一章 拜入七玄 ==='));
      expect(fullLoaded, contains('少年韩立背负布包'));
      expect(fullLoaded, contains('=== 第二章 墨大夫 ==='));
      expect(fullLoaded, contains('神手谷内草药飘香'));

      // 2. 指定单章引用
      final singleChapterResult = NovelSelectionResult(
        novel: novel,
        selectedChapterIndices: const [2],
        combinedText: '',
      );

      final singleLoaded = await singleChapterResult.loadCombinedText();
      expect(singleLoaded, isNot(contains('第一章 拜入七玄')));
      expect(singleLoaded, contains('=== 第二章 墨大夫 ==='));
      expect(singleLoaded, contains('神手谷内草药飘香'));
    });

    test('当章节内容为空时，loadCombinedText 返回空字符串便于前台防御拦截', () async {
      final novel = NovelMetadata(
        id: 'novel_empty_202',
        title: '空正文小说',
        author: '佚名',
        status: NovelStatus.ongoing,
        genre: '都市',
        tags: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.saveNovel(novel);

      final result = NovelSelectionResult(
        novel: novel,
        selectedChapterIndices: const [],
        combinedText: '',
      );

      final loaded = await result.loadCombinedText();
      expect(loaded, isEmpty);
    });

    test('sampleNovelTextForContext 对长篇全本小说实施 35000 字符智能采样防溢出', () {
      // 构造超过 50,000 字的模拟超长小说
      final longTextBuffer = StringBuffer('【序章】这是长篇故事的开端背景铺垫。\n');
      for (var i = 1; i <= 2500; i++) {
        longTextBuffer.writeln('第 $i 段：修仙路上风起云涌，法宝破空飞舞，双方展开了激烈的交锋。');
      }
      longTextBuffer.writeln('【终局】历经万劫，终于飞升仙界，天地归于宁静。');

      final rawLongText = longTextBuffer.toString();
      expect(rawLongText.length, greaterThan(50000));

      final sampled = AiConstraintEngine.sampleNovelTextForContext(rawLongText);
      expect(sampled.length, lessThanOrEqualTo(36000));
      // 必须保留开头与结尾
      expect(sampled, contains('【序章】这是长篇故事的开端'));
      expect(sampled, contains('【终局】历经万劫，终于飞升仙界'));
    });
  });
}
