import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

void main() {
  group('Asset Prompt Override and Customization Tests', () {
    test('SceneCard systemPromptOverride and panoramaSystemPromptOverride serialization', () {
      final scene = SceneCard(
        id: 'scene_shihai',
        name: '姜七夜识海',
        descriptionZh: '无边无际，只有凶辰和大海，中间有一个圆形的祭坛',
        systemPromptOverride: '纯粹虚空玄幻空间，绝对无建筑，无亭台楼阁',
        panoramaSystemPromptOverride: '360 degree mystical ethereal ocean panorama, circular ancient stone altar floating in dark cosmic sea, no buildings',
        updatedAt: DateTime.now(),
      );

      final json = scene.toJson();
      expect(json['system_prompt_override'], '纯粹虚空玄幻空间，绝对无建筑，无亭台楼阁');
      expect(json['panorama_system_prompt_override'], contains('mystical ethereal ocean'));

      final restored = SceneCard.fromJson(json);
      expect(restored.systemPromptOverride, scene.systemPromptOverride);
      expect(restored.panoramaSystemPromptOverride, scene.panoramaSystemPromptOverride);

      // copyWith clear test
      final cleared = restored.copyWith(
        clearSystemPromptOverride: true,
        clearPanoramaSystemPromptOverride: true,
      );
      expect(cleared.systemPromptOverride, isNull);
      expect(cleared.panoramaSystemPromptOverride, isNull);
    });

    test('ScenePromptBuilder respects systemPromptOverride and panoramaSystemPromptOverride', () {
      final scene = SceneCard(
        id: 'scene_shihai',
        name: '姜七夜识海',
        descriptionZh: '无边无际，只有凶辰和大海，中间有一个圆形的祭坛',
        systemPromptOverride: '纯粹虚空玄幻空间，绝对无建筑，无亭台楼阁',
        panoramaSystemPromptOverride: '360 degree mystical ethereal cosmic sea panorama, circular stone altar, pure void, absolutely no architecture',
        updatedAt: DateTime.now(),
      );

      // Test directional view prompt with sceneEnvironmentOverride
      final positivePrompt = ScenePromptBuilder.buildPositivePrompt(
        basePrompt: scene.descriptionZh,
        styleTokens: 'UE5渲染，东方暗调玄幻',
        eraGenreId: 'xianxia',
        sceneEnvironmentOverride: scene.systemPromptOverride,
      );

      // Default xianxia contains '古建亭台楼阁，雕梁画栋', but with override it must be replaced!
      expect(positivePrompt, isNot(contains('古建亭台楼阁')));
      expect(positivePrompt, contains('纯粹虚空玄幻空间，绝对无建筑，无亭台楼阁'));

      // Test panorama prompt
      final panoPrompt = ScenePromptBuilder.buildPanoramaPrompt(
        basePrompt: scene.descriptionZh,
        styleTokens: 'UE5渲染，东方暗调玄幻',
        eraGenreId: 'xianxia',
        systemPromptOverride: scene.systemPromptOverride,
        panoramaSystemPromptOverride: scene.panoramaSystemPromptOverride,
      );

      // Default pano contains 'spacious architectural vista' and '古建亭台楼阁', override must replace them!
      expect(panoPrompt, isNot(contains('spacious architectural vista')));
      expect(panoPrompt, isNot(contains('古建亭台楼阁')));
      expect(panoPrompt, contains('360 degree mystical ethereal cosmic sea panorama'));
    });

    test('PropCard systemPromptOverride serialization and PromptBuilder integration', () {
      final prop = PropCard(
        id: 'prop_sword',
        name: '天枢残剑',
        descriptionZh: '生锈的断剑，剑柄镶嵌黯淡灵石',
        systemPromptOverride: '悬浮于深海虚空的孤立神秘法宝，暗部高反差电影级光影',
        updatedAt: DateTime.now(),
      );

      final json = prop.toJson();
      expect(json['system_prompt_override'], contains('悬浮于深海虚空'));

      final restored = PropCard.fromJson(json);
      expect(restored.systemPromptOverride, prop.systemPromptOverride);

      final prompt = PropPromptBuilder.buildPositivePrompt(
        prompt: restored.descriptionZh,
        styleTokens: '次世代CG，PBR物理材质',
        eraGenreId: 'xianxia',
        systemPromptOverride: restored.systemPromptOverride,
      );

      // Default propAssetRequirement contains '道具资产单品设计图，纯白无缝背景'
      expect(prompt, isNot(contains('道具资产单品设计图，纯白无缝背景')));
      expect(prompt, contains('悬浮于深海虚空的孤立神秘法宝'));
    });

    test('CharacterCard and CharacterVariation systemPromptOverride serialization and Turnaround build', () {
      final variation = CharacterVariation(
        id: 'var_battle',
        name: '战损破阵态',
        attirePrompt: '残破锁子甲，血染征袍',
        systemPromptOverride: '暗黑写实战场单人全身立绘，电影级侧光与沙尘飞扬，非纯白底板',
      );

      final varJson = variation.toJson();
      expect(varJson['system_prompt_override'], contains('暗黑写实战场单人全身立绘'));

      final restoredVar = CharacterVariation.fromJson(varJson);
      expect(restoredVar.systemPromptOverride, variation.systemPromptOverride);

      final character = CharacterCard(
        id: 'char_jiang',
        name: '姜七夜',
        descriptionZh: '巡城司狱卒，眼神深邃冷静',
        variations: [restoredVar],
        systemPromptOverride: '冷光影棚单人极简三向特写，无白边',
        updatedAt: DateTime.now(),
      );

      final charJson = character.toJson();
      expect(charJson['system_prompt_override'], contains('冷光影棚单人极简三向特写'));

      final restoredChar = CharacterCard.fromJson(charJson);
      expect(restoredChar.systemPromptOverride, character.systemPromptOverride);

      final xianxia = VisualEraGenre.fromId('xianxia');

      // Base turnaround prompt with override
      final basePrompt = CharacterTurnaroundPrompt.build(
        '姜七夜，巡城司狱卒',
        eraGenre: xianxia,
        systemPromptOverride: restoredChar.systemPromptOverride,
      );
      expect(basePrompt, isNot(contains('角色概念设计三视图标准排版')));
      expect(basePrompt, contains('冷光影棚单人极简三向特写'));

      // Variation turnaround prompt with override
      final varPrompt = CharacterTurnaroundPrompt.buildForVariation(
        character: restoredChar,
        variation: restoredVar,
        eraGenre: xianxia,
        systemPromptOverride: restoredVar.systemPromptOverride,
      );
      expect(varPrompt, isNot(contains('角色概念设计三视图标准排版')));
      expect(varPrompt, contains('暗黑写实战场单人全身立绘'));
    });
  });
}
