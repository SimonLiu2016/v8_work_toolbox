import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/drama_director_contract.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/breakdown_input.dart';

/// spec: 拆镜入口的输入一致性
///
/// 剧本工作台与分镜看板都有「AI 五维拆镜」按钮。旧实现两边各拼各的：剧本
/// 台传打磨过的文学剧本全文，看板只传 4 行粗大纲文本框的内容——用户在两个
/// 面板点同一个按钮，喂给 AI 的输入源完全不同。
///
/// 这里守 [BreakdownInput] 的取值优先级：同一集从任一面板取值都应一致。
void main() {
  DramaScene sceneOf() => DramaScene(
    id: 'SC001',
    sceneNumber: 1,
    title: '镇魔司大殿',
    location: '大殿',
    beats: [
      DramaBeat(
        id: 'B01',
        sceneId: 'SC001',
        order: 1,
        name: '授刀',
        action: '东方诏将斩妖刀递与沈长青',
        dialogueSpeaker: '东方诏',
        dialogue: '斩妖除魔，护我人族！',
      ),
    ],
  );

  StudioEpisode episodeWith({
    required String screenplayText,
    required String synopsis,
  }) {
    final now = DateTime(2026, 10, 25);
    return StudioEpisode(
      id: 'ep_1',
      seriesId: 's_01',
      index: 1,
      title: '第一集',
      synopsis: synopsis,
      scenes: [sceneOf()],
      screenplayText: screenplayText,
      protectedContract: const ProtectedContract(
        utterances: [
          ProtectedUtterance(
            id: 'U01',
            speaker: '东方诏',
            listener: '沈长青',
            text: '斩妖除魔，护我人族！',
          ),
        ],
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  group('BreakdownInput 取值优先级', () {
    test('screenplayText 非空时优先于 synopsis', () {
      final ep = episodeWith(
        screenplayText: '### 第1场 镇魔司大殿\n沈长青受刀。',
        synopsis: '沈长青入职。',
      );

      expect(
        BreakdownInput.synopsisOf(ep),
        '### 第1场 镇魔司大殿\n沈长青受刀。',
      );
    });

    test('screenplayText 为空时回退到 synopsis', () {
      final ep = episodeWith(screenplayText: '   ', synopsis: '沈长青入职。');

      expect(BreakdownInput.synopsisOf(ep), '沈长青入职。');
    });

    test('rawTextOverride 优先（文本模式下的实时编辑）', () {
      final ep = episodeWith(
        screenplayText: '已保存的剧本文本',
        synopsis: '沈长青入职。',
      );

      expect(
        BreakdownInput.synopsisOf(ep, rawTextOverride: '用户刚敲的未保存文本'),
        '用户刚敲的未保存文本',
      );
    });

    test('rawTextOverride 为空白时回落到 screenplayText', () {
      final ep = episodeWith(
        screenplayText: '已保存的剧本文本',
        synopsis: '沈长青入职。',
      );

      expect(
        BreakdownInput.synopsisOf(ep, rawTextOverride: '   '),
        '已保存的剧本文本',
      );
    });

    test('两个入口对同一集取到相同的 scenes 与 contract', () {
      final ep = episodeWith(screenplayText: '文本', synopsis: '大纲');

      // 剧本工作台与分镜看板分别调这三个取值函数，结果必须一致。
      expect(BreakdownInput.scenesOf(ep), ep.scenes);
      expect(BreakdownInput.contractOf(ep), ep.protectedContract);
      expect(BreakdownInput.contractOf(ep).utterances, hasLength(1));
    });
  });

  group('ShotVariationResolver 三级形态优先级', () {
    CharacterCard cardWith(List<CharacterVariation> variations) => CharacterCard(
      id: 'c1',
      name: '姜七夜',
      variations: variations,
      updatedAt: DateTime(2026),
    );

    StudioEpisode episodeWithOverrides(Map<String, String> overrides) {
      final now = DateTime(2026, 10, 25);
      return StudioEpisode(
        id: 'ep_1',
        seriesId: 's_01',
        index: 1,
        variationOverrides: overrides,
        createdAt: now,
        updatedAt: now,
      );
    }

    StudioShot shotWithVariation(String? variationId) => StudioShot(
      number: 1,
      characterVariations: variationId == null
          ? const {}
          : {'c1': variationId},
    );

    final variations = [
      const CharacterVariation(id: 'v_default', name: '默认', active: true),
      const CharacterVariation(id: 'v_battle', name: '战损'),
    ];

    test('分镜显式指定优先于单集覆盖与默认', () {
      final shot = shotWithVariation('v_battle');
      final ep = episodeWithOverrides({'c1': 'v_default'});

      final resolved = ShotVariationResolver.resolve(
        episode: ep,
        shot: shot,
        character: cardWith(variations),
      );

      expect(resolved?.id, 'v_battle');
    });

    test('分镜未指定时用单集覆盖', () {
      final shot = shotWithVariation(null);
      final ep = episodeWithOverrides({'c1': 'v_battle'});

      final resolved = ShotVariationResolver.resolve(
        episode: ep,
        shot: shot,
        character: cardWith(variations),
      );

      expect(resolved?.id, 'v_battle');
    });

    test('前两级都无时回落到角色默认激活形态', () {
      final shot = shotWithVariation(null);
      final ep = episodeWithOverrides(const {});

      final resolved = ShotVariationResolver.resolve(
        episode: ep,
        shot: shot,
        character: cardWith(variations),
      );

      expect(resolved?.id, 'v_default');
    });

    test('分镜指定的形态 id 不存在时继续往下找', () {
      final shot = shotWithVariation('v_missing');
      final ep = episodeWithOverrides({'c1': 'v_battle'});

      final resolved = ShotVariationResolver.resolve(
        episode: ep,
        shot: shot,
        character: cardWith(variations),
      );

      expect(resolved?.id, 'v_battle');
    });

    test('三级都无（角色没有激活形态）时返回 null', () {
      final shot = shotWithVariation(null);
      final ep = episodeWithOverrides(const {});

      final resolved = ShotVariationResolver.resolve(
        episode: ep,
        shot: shot,
        character: cardWith(const [
          CharacterVariation(id: 'v_a', name: '形态A'),
        ]),
      );

      expect(resolved, isNull);
    });

    test('角色为 null 时返回 null', () {
      final resolved = ShotVariationResolver.resolve(
        episode: episodeWithOverrides(const {}),
        shot: shotWithVariation(null),
        character: null,
      );

      expect(resolved, isNull);
    });
  });
}
