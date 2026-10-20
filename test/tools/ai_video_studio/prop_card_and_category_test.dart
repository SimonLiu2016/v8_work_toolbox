import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/asset_library.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// 道具卡与资产分类的回归。
///
/// 守三件容易回退的事：
/// 1. **旧数据零迁移**——`series_profile.json` 没有 `props`、`asset_index.json`
///    没有 `category`/`tags` 时必须照常加载，否则老用户的工坊一开门就崩；
/// 2. **序列化往返**——道具字段写进 JSON 后能读回同一份；
/// 3. **检索大小写不敏感**——搜 "agnes" 必须命中 "Agnes"，否则用户以为自己
///    存过的图没进来。
void main() {
  group('PropCard 序列化', () {
    test('往返后字段一致', () {
      final card = PropCard(
        id: 'prop_1',
        name: '祖传玉佩',
        descriptionZh: '羊脂白玉，雕龙纹',
        promptEn: 'an antique jade pendant',
        referenceImages: const ['references/a.png'],
        isKeyProp: true,
        updatedAt: DateTime.utc(2026, 10, 13),
      );

      final back = PropCard.fromJson(jsonDecode(jsonEncode(card.toJson())));
      expect(back.id, card.id);
      expect(back.name, card.name);
      expect(back.descriptionZh, card.descriptionZh);
      expect(back.promptEn, card.promptEn);
      expect(back.referenceImages, card.referenceImages);
      expect(back.isKeyProp, isTrue);
    });

    test('旧 JSON 缺字段时回落，不抛异常', () {
      final back = PropCard.fromJson(const {'id': 'p', 'name': '旧道具'});
      expect(back.descriptionZh, '');
      expect(back.promptEn, '');
      expect(back.referenceImages, isEmpty);
      expect(back.isKeyProp, isFalse);
    });

    test('StudioSeries 无 props 字段的旧 JSON 按空列表加载', () {
      final series = StudioSeries.fromJson(const {
        'id': 's1',
        'name': '老剧集',
        'characters': [],
        'commonScenes': [],
      });
      expect(series.props, isEmpty);
    });
  });

  group('StudioAsset 分类与标签', () {
    test('旧 JSON 缺 category/tags 回落 other 与空列表', () {
      final asset = StudioAsset.fromJson(const {
        'id': 'abc12345',
        'kind': 'image',
      });
      expect(asset, isNotNull);
      expect(asset!.category, AssetCategory.other);
      expect(asset.tags, isEmpty);
    });

    test('category 与 tags 可序列化往返', () {
      final asset = StudioAsset(
        id: 'abc12345',
        kind: AssetKind.image,
        source: AssetSource.remote,
        sizeBytes: 2048,
        createdAt: DateTime.utc(2026, 10, 13),
        category: AssetCategory.prop,
        tags: const ['玉佩', '关键道具'],
      );
      final back = StudioAsset.fromJson(jsonDecode(jsonEncode(asset.toJson())));
      expect(back!.category, AssetCategory.prop);
      expect(back.tags, ['玉佩', '关键道具']);
    });

    test('copyWith 可改 category 与 tags', () {
      final asset = StudioAsset(
        id: 'abc12345',
        kind: AssetKind.image,
        source: AssetSource.remote,
        sizeBytes: 1024,
        createdAt: DateTime.utc(2026, 10, 13),
      );
      final updated = asset.copyWith(
        category: AssetCategory.character,
        tags: const ['林晚'],
      );
      expect(updated.category, AssetCategory.character);
      expect(updated.tags, ['林晚']);
      // 改分类不该顺手把 kind 抹掉。
      expect(updated.kind, AssetKind.image);
    });
  });

  group('AssetLibrary 筛选与检索', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('asset_filter_test');
      AppPaths.overrideRootForTesting(tempDir);
      AssetLibrary.instance.resetForTesting();
    });

    tearDown(() {
      AssetLibrary.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<File> makeSource(String name) async {
      final f = File(p.join(tempDir.path, name));
      await f.writeAsBytes(List<int>.filled(512, 9));
      return f;
    }

    test('assetsOf 按分类过滤', () async {
      await AssetLibrary.instance.addAsset(
        await makeSource('char.png'),
        kind: AssetKind.image,
        category: AssetCategory.character,
      );
      await AssetLibrary.instance.addAsset(
        await makeSource('prop.png'),
        kind: AssetKind.image,
        category: AssetCategory.prop,
      );
      await AssetLibrary.instance.addAsset(await makeSource('other.png'), kind: AssetKind.image);

      final characters =
          await AssetLibrary.instance.assetsOf(AssetKind.image, category: AssetCategory.character);
      expect(characters, hasLength(1));
      expect(characters.first.category, AssetCategory.character);

      final all = await AssetLibrary.instance.assetsOf(AssetKind.image);
      expect(all, hasLength(3));
    });

    test('search 命中标签且大小写不敏感', () async {
      await AssetLibrary.instance.addAsset(
        await makeSource('a.png'),
        kind: AssetKind.image,
        prompt: '雨夜天台，少女回眸',
        tags: const ['Agnes'],
      );

      final lower = await AssetLibrary.instance.search('agnes');
      expect(lower, hasLength(1));

      final upper = await AssetLibrary.instance.search('AGNES');
      expect(upper, hasLength(1));

      final prompt = await AssetLibrary.instance.search('天台');
      expect(prompt, hasLength(1));

      final miss = await AssetLibrary.instance.search('玉佩');
      expect(miss, isEmpty);
    });

    test('search 空关键词返回全部', () async {
      await AssetLibrary.instance.addAsset(await makeSource('a.png'), kind: AssetKind.image);
      await AssetLibrary.instance.addAsset(await makeSource('b.png'), kind: AssetKind.clip);

      final all = await AssetLibrary.instance.search('   ');
      expect(all, hasLength(2));
    });

    test('setCategory / setTags 跨重启读回', () async {
      final asset = await AssetLibrary.instance.addAsset(
        await makeSource('c.png'),
        kind: AssetKind.image,
      );

      await AssetLibrary.instance.setCategory(asset.id, AssetCategory.scene);
      await AssetLibrary.instance.setTags(asset.id, const ['雨夜', '巷道']);

      AssetLibrary.instance.resetForTesting();
      final back = await AssetLibrary.instance.findById(asset.id);
      expect(back!.category, AssetCategory.scene);
      expect(back.tags, ['雨夜', '巷道']);
    });

    test('addAsset 的 category/tags 落盘后不丢', () async {
      final asset = await AssetLibrary.instance.addAsset(
        await makeSource('d.png'),
        kind: AssetKind.image,
        category: AssetCategory.frame,
        tags: const ['shot_3'],
      );

      AssetLibrary.instance.resetForTesting();
      final back = await AssetLibrary.instance.findById(asset.id);
      expect(back!.category, AssetCategory.frame);
      expect(back.tags, ['shot_3']);
    });
  });

  group('StudioProjectManager 道具 CRUD', () {
    late Directory tempDir;
    late StudioProjectManager manager;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('prop_crud_test');
      AppPaths.overrideRootForTesting(tempDir);
      AssetLibrary.instance.resetForTesting();
      manager = StudioProjectManager.instance;
      await manager.ensureBaseStructure();
    });

    tearDown(() {
      AssetLibrary.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('新建、保存、读回、删除', () async {
      final series = await manager.createSeries(name: '道具测试剧');
      final prop = await manager.createProp(
        seriesId: series.id,
        name: '祖传玉佩',
        descriptionZh: '羊脂白玉',
        promptEn: 'a jade pendant',
        isKeyProp: true,
      );

      final readBack = await manager.listProps(series.id);
      expect(readBack, hasLength(1));
      expect(readBack.first.name, '祖传玉佩');
      expect(readBack.first.isKeyProp, isTrue);

      // series_profile.json 是事实来源：直接读磁盘验证 props 已序列化。
      final profile = jsonDecode(
        await File(p.join(manager.seriesDir(series.id).path, 'series_profile.json'))
            .readAsString(),
      ) as Map<String, dynamic>;
      expect(profile['props'], isA<List>());
      expect((profile['props'] as List).first['name'], '祖传玉佩');

      await manager.saveProp(
        series.id,
        prop.copyWith(name: '祖传龙纹玉佩'),
      );
      expect((await manager.listProps(series.id)).first.name, '祖传龙纹玉佩');

      await manager.deleteProp(series.id, prop.id);
      expect(await manager.listProps(series.id), isEmpty);
    });

    test('addPropReference 复制进道具目录并返回相对路径', () async {
      final series = await manager.createSeries(name: '道具参考图剧');
      final prop = await manager.createProp(seriesId: series.id, name: '玉佩');

      final src = File(p.join(tempDir.path, 'ref.png'));
      await src.writeAsBytes(List<int>.filled(2048, 5));

      final relative = await manager.addPropReference(
        seriesId: series.id,
        propId: prop.id,
        sourceFilePath: src.path,
      );

      expect(p.isRelative(relative), isTrue,
          reason: '存进 PropCard 的必须是相对路径，绝对路径会让整棵目录树不可搬迁');
      final copied = File(p.join(manager.propDir(series.id, prop.id).path, relative));
      expect(await copied.exists(), isTrue);
      expect(await src.exists(), isTrue, reason: '参考图是复制，原文件不能被动');
    });

    test('删除道具会带走它的参考图目录', () async {
      final series = await manager.createSeries(name: '道具删除剧');
      final prop = await manager.createProp(seriesId: series.id, name: '旧玉佩');
      final src = File(p.join(tempDir.path, 'r.png'));
      await src.writeAsBytes(List<int>.filled(64, 1));
      final relative = await manager.addPropReference(
        seriesId: series.id,
        propId: prop.id,
        sourceFilePath: src.path,
      );

      final dir = manager.propDir(series.id, prop.id);
      expect(await dir.exists(), isTrue);
      await manager.deleteProp(series.id, prop.id);
      expect(await dir.exists(), isFalse,
          reason: '卡片已删，留下的参考图目录就是孤儿文件');
      expect(await File(p.join(dir.path, relative)).exists(), isFalse);
    });

    test('新建剧集无道具时 props 正常落盘', () async {
      final series = await manager.createSeries(name: '空道具剧');
      expect(series.props, isEmpty);
      expect(await manager.listProps(series.id), isEmpty);
    });
  });

  group('CharacterTurnaroundPrompt', () {
    test('三个视角要求与角色描述都进提示词', () {
      final prompt = CharacterTurnaroundPrompt.build('a young woman in red cloak');
      expect(prompt, contains('正面平视'));
      expect(prompt, contains('侧面'));
      expect(prompt, contains('背面'));
      expect(prompt, contains('a young woman in red cloak'));
      expect(prompt, contains('同一角色'));
    });

    test('视角要求在角色描述之前', () {
      // 顺序反了模型会产出单张立绘而不是三视图（见 CharacterTurnaroundPrompt 文档）。
      final prompt = CharacterTurnaroundPrompt.build('林晚');
      expect(prompt.indexOf('正面平视'), lessThan(prompt.indexOf('林晚')));
    });

    test('负面提示词点名视角污染与多出人物', () {
      final negative = CharacterTurnaroundPrompt.turnaroundNegativePrompt;
      expect(negative, contains('多个人物'));
      expect(negative, contains('单重视角'));
    });

    test('空角色描述不产出空提示词', () {
      final prompt = CharacterTurnaroundPrompt.build('   ');
      expect(prompt.trim(), isNotEmpty);
      expect(prompt, contains('正面平视'));
    });
  });
}
