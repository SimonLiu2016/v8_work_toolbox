import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_preset_store.dart';

void main() {
  group('StudioPresetStore 预设库与三层负向词测试', () {
    late Directory tempDir;
    late StudioPresetStore store;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('studio_preset_store_test');
      AppPaths.overrideRootForTesting(tempDir);
      store = StudioPresetStore.instance;
      store.resetForTesting();
      await store.init();
    });

    tearDown(() {
      store.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('出厂自愈并初始化 37 套工业级美学风格与 13 大时代题材', () {
      expect(store.styles.length, 37, reason: '必须加载完整的 37 套工业级美学风格');
      expect(store.eras.length, 13, reason: '必须包含 13 套时代题材预设');

      // 验证 8 大体系分类全覆盖
      final categories = store.stylesByCategory.keys.toList();
      expect(categories.length, 8);
      expect(categories, contains('东方国风'));
      expect(categories, contains('日系二次元'));
      expect(categories, contains('西式CG/3D卡通'));
      expect(categories, contains('科幻赛博废土'));
      expect(categories, contains('实拍电影质感'));
      expect(categories, contains('手工立体美术'));
      expect(categories, contains('暗黑悬疑哥特'));
      expect(categories, contains('小众艺术实验'));

      // 验证新增的真人实拍预设数据结构完整性
      final costumeDrama = store.getStyleById('costume_drama_realism');
      expect(costumeDrama, isNotNull);
      expect(costumeDrama!.nameZh, '真人古装·仙侠影视大片');

      final shortDrama = store.getStyleById('live_action_short_drama');
      expect(shortDrama, isNotNull);
      expect(shortDrama!.nameZh, '真人爆款·实拍短剧');

      // 验证典型风格预设数据结构完整性
      final xianxiaStyle = store.getStyleById('ue5_3d_xianxia');
      expect(xianxiaStyle, isNotNull);
      expect(xianxiaStyle!.nameZh, 'UE5 3D国漫·东方玄幻');
      expect(xianxiaStyle.category, '东方国风');
      expect(xianxiaStyle.positiveAnchor, contains('UE5渲染'));
      expect(xianxiaStyle.negativeBan, contains('2D手绘'));
      expect(xianxiaStyle.isBuiltin, isTrue);

      final movieStyle = store.getStyleById('modern_cinematic_live_action');
      expect(movieStyle, isNotNull);
      expect(movieStyle!.nameZh, '现代院线电影写实');
      expect(movieStyle.negativeBan, contains('卡通，动漫，CG'));

      // 验证新增的题材预设
      final spyEra = store.getEraById('republic_vintage');
      expect(spyEra, isNotNull);
      expect(spyEra!.labelZh, '民国谍战');
      expect(spyEra.negativeBans, contains('当代现代服饰'));

      final suspenseEra = store.getEraById('modern_suspense');
      expect(suspenseEra, isNotNull);
      expect(suspenseEra!.labelZh, '现代悬疑刑侦');
    });

    test('AestheticStyle 与 VisualEraGenre 的 JSON 序列化与反序列化对称', () {
      final style = store.styles.first;
      final jsonMap = style.toJson();
      final restored = AestheticStyle.fromJson(jsonMap);

      expect(restored.id, style.id);
      expect(restored.category, style.category);
      expect(restored.nameZh, style.nameZh);
      expect(restored.descriptionZh, style.descriptionZh);
      expect(restored.positiveAnchor, style.positiveAnchor);
      expect(restored.negativeBan, style.negativeBan);
      expect(restored.defaultRatio, style.defaultRatio);
      expect(restored.isBuiltin, style.isBuiltin);

      final era = store.eras.first;
      final eraJson = era.toJson();
      final restoredEra = VisualEraGenre.fromJson(eraJson);

      expect(restoredEra.id, era.id);
      expect(restoredEra.labelZh, era.labelZh);
      expect(restoredEra.descriptionZh, era.descriptionZh);
      expect(restoredEra.costumeAnchor, era.costumeAnchor);
      expect(restoredEra.environmentAnchor, era.environmentAnchor);
      expect(restoredEra.propMaterialAnchor, era.propMaterialAnchor);
      expect(restoredEra.negativeBans, era.negativeBans);
      expect(restoredEra.isBuiltin, era.isBuiltin);
    });

    test('三层负向词装配逻辑：[时代排他] + [风格专属] + [通用防崩] 与 Token 去重', () {
      final spyEra = store.getEraById('republic_vintage');
      final movieStyle = store.getStyleById('modern_cinematic_live_action');

      final assembled = PromptAssembler.assembleNegativePrompt(
        eraGenre: spyEra,
        aestheticStyle: movieStyle,
        extraNegative: 'custom_bad_artifact, blurry',
        universalNegative: AestheticStyle.universalNegativeBrief,
      );

      // 验证三层词汇均被装配
      expect(assembled, contains('当代现代服饰'), reason: '时代排他词必须注入');
      expect(assembled, contains('卡通, 动漫, CG'), reason: '风格专属排他词必须注入');
      expect(assembled, contains('畸形手部'), reason: '通用防崩词必须注入');
      expect(assembled, contains('custom_bad_artifact'), reason: '用户自定义负向词必须注入');

      // 验证去重逻辑（大小写及前后空格去重）
      final tokens = AestheticStyle.deduplicateTokens(
        'plastic skin, 3D render, PLASTIC SKIN, blurry, 3d render, deformed hands',
      );
      expect(tokens, 'plastic skin, 3D render, blurry, deformed hands');
    });

    test('CRUD 增删改查、磁盘持久化与恢复出厂机制', () async {
      // 1. 新增自定义风格
      final customStyle = AestheticStyle(
        id: 'custom_cyber_steampunk',
        category: '科幻赛博废土',
        nameZh: '赛博蒸汽朋克',
        descriptionZh: '黄铜齿轮与霓虹辉光交织的蒸汽赛博世界',
        positiveAnchor: 'steampunk brass gears, neon glow, atmospheric smoke',
        negativeBan: 'clean plastic minimalism, pure fantasy magic',
        defaultRatio: '16:9',
        isBuiltin: false,
      );

      await store.saveStyle(customStyle);
      expect(store.styles.length, 38);
      expect(store.getStyleById('custom_cyber_steampunk'), isNotNull);

      // 验证持久化落盘
      final fileContent = await AppPaths.aestheticStylesFile.readAsString();
      expect(fileContent, contains('custom_cyber_steampunk'));

      // 2. 模拟重新启动服务，从磁盘重载
      store.resetForTesting();
      await store.init();
      expect(store.styles.length, 38);
      expect(store.getStyleById('custom_cyber_steampunk')!.nameZh, '赛博蒸汽朋克');

      // 3. 内置预设受保护：deleteStyle 返回 false
      final deleteBuiltinResult = await store.deleteStyle('ue5_3d_xianxia');
      expect(deleteBuiltinResult, isFalse, reason: '出厂内置预设严禁删除');
      expect(store.getStyleById('ue5_3d_xianxia'), isNotNull);

      // 4. 删除自定义风格
      final deleteCustomResult = await store.deleteStyle('custom_cyber_steampunk');
      expect(deleteCustomResult, isTrue);
      expect(store.styles.length, 37);
      expect(store.getStyleById('custom_cyber_steampunk'), isNull);

      // 5. 恢复出厂风格预设
      await store.resetStylesToDefault();
      expect(store.styles.length, 37);
    });

    test('Novel Master Extraction 动态 Prompt 注入与题材画风智能匹配', () {
      final extractionPrompt = AiConstraintEngine.buildNovelMasterExtractionPrompt();

      // 验证时代题材列表动态注入
      expect(extractionPrompt, contains('"republic_vintage"（民国谍战'));
      expect(extractionPrompt, contains('"modern_urban"（现代都市豪门'));
      expect(extractionPrompt, contains('"xianxia"（仙侠修真'));

      // 验证 35 套美学风格动态注入
      expect(extractionPrompt, contains('"ue5_3d_xianxia"（[东方国风]'));
      expect(extractionPrompt, contains('"ue5_cyberpunk_cg"（[科幻赛博废土]'));
      expect(extractionPrompt, contains('"modern_cinematic_live_action"（[实拍电影质感]'));
    });

    test('StudioPromptTemplate 提示词模板出厂自愈、修改持久化与恢复默认', () async {
      // 1. 验证出厂自愈已初始化 5 套内置模板
      expect(store.templates.length, 5);
      final turnaround = store.getTemplateById('character_turnaround');
      expect(turnaround, isNotNull);
      expect(turnaround!.name, '角色三视图与资产板规范');
      expect(turnaround.category, '资产生成规范');
      expect(turnaround.effectiveContent, contains('Character turnaround sheet'));
      expect(turnaround.isModified, isFalse);

      final ageStaging = store.getTemplateById('character_age_staging');
      expect(ageStaging, isNotNull);
      expect(ageStaging!.effectiveContent, contains('【年龄阶层自适应规则】'));
      expect(ageStaging.effectiveContent, contains('少年（13~18岁）'));
      expect(ageStaging.effectiveContent, contains('接近成年男性的纵向骨骼身长'));
      expect(ageStaging.effectiveContent, isNot(contains('非低幼儿童')));

      final sceneTemplate = store.getTemplateById('scene_environment');
      expect(sceneTemplate, isNotNull);
      expect(sceneTemplate!.effectiveContent, contains('纯净环境空镜'));

      // 2. 验证用户修改覆盖并持久化
      final modifiedTurnaround = turnaround.copyWith(
        userOverride: '自定义纯中文三视图提示词：左特写右三立绘，哑光肤质。',
        updatedAt: DateTime.now(),
      );
      await store.saveTemplate(modifiedTurnaround);

      // 内存状态检查
      final saved = store.getTemplateById('character_turnaround')!;
      expect(saved.isModified, isTrue);
      expect(saved.effectiveContent, '自定义纯中文三视图提示词：左特写右三立绘，哑光肤质。');

      // 磁盘文件持久化检查
      final diskJson = await AppPaths.promptTemplatesFile.readAsString();
      expect(diskJson, contains('自定义纯中文三视图提示词'));

      // 3. 模拟跨重启加载
      store.resetForTesting();
      await store.init();
      final reloaded = store.getTemplateById('character_turnaround')!;
      expect(reloaded.isModified, isTrue);
      expect(reloaded.effectiveContent, '自定义纯中文三视图提示词：左特写右三立绘，哑光肤质。');
      expect(reloaded.defaultContent, contains('Character turnaround sheet'));

      // 4. 单项恢复出厂默认
      await store.resetTemplateToDefault('character_turnaround');
      final resetOne = store.getTemplateById('character_turnaround')!;
      expect(resetOne.isModified, isFalse);
      expect(resetOne.effectiveContent, contains('Character turnaround sheet'));

      // 5. 校验 StudioImageDimensionPreset 预设
      final p169 = StudioImageDimensionPreset.fromRatio('16:9');
      expect(p169.width, 2624);
      expect(p169.height, 1472);
      expect(p169.size, '2K');

      final p219 = StudioImageDimensionPreset.fromRatio('21:9');
      expect(p219.width, 3136);
      expect(p219.height, 1344);

      final p11 = StudioImageDimensionPreset.fromRatio('1:1');
      expect(p11.width, 2048);
      expect(p11.height, 2048);
    });
  });
}
