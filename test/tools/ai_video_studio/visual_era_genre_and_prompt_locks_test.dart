import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';

void main() {
  group('VisualEraGenre 设定与检索', () {
    test('内置预设包含修真、古装、穿越、都市、废土等核心题材', () {
      final ids = VisualEraGenre.presets.map((p) => p.id).toSet();
      expect(ids.contains('xianxia'), isTrue);
      expect(ids.contains('ancient_costume'), isTrue);
      expect(ids.contains('ancient_transmigration'), isTrue);
      expect(ids.contains('modern_urban'), isTrue);
      expect(ids.contains('sci_fi_superpower'), isTrue);
      expect(ids.contains('wasteland'), isTrue);
      expect(ids.contains('cyberpunk_sci_fi'), isTrue);
      expect(ids.contains('isekai_fantasy'), isTrue);
    });

    test('仙侠修真预设严密禁绝现代沙滩裤与现代服饰', () {
      final xianxia = VisualEraGenre.fromId('xianxia');
      expect(xianxia, isNotNull);
      expect(xianxia!.costumeAnchor, contains('中式传统古装仙侠服饰'));
      expect(xianxia.costumeAnchor, contains('宽袍大袖'));
      expect(xianxia.negativeBans, contains('短袖短裤'));
      expect(xianxia.negativeBans, contains('现代服饰'));
      expect(xianxia.negativeBans, contains('牛仔裤'));
    });

    test('fromId 在未知或空 ID 时安全回退 null', () {
      expect(VisualEraGenre.fromId(''), isNull);
      expect(VisualEraGenre.fromId('unknown_id'), isNull);
      expect(VisualEraGenre.fromId('   '), isNull);
    });
  });

  group('StudioSeries eraGenre 序列化与向后兼容', () {
    test('序列化与反序列化往返保留 eraGenre', () {
      final series = StudioSeries(
        id: 's_001',
        name: '凡人修仙传',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        eraGenre: 'xianxia',
        styleTokens: 'traditional ink wash style, cinematic lighting',
      );

      final json = series.toJson();
      expect(json['era_genre'], equals('xianxia'));

      final restored = StudioSeries.fromJson(json);
      expect(restored.eraGenre, equals('xianxia'));
      expect(restored.name, equals('凡人修仙传'));
    });

    test('旧版缺失 era_genre 的 JSON 自动安全回落空字符串', () {
      final oldJson = {
        'id': 's_old',
        'name': '旧剧集',
        'created_at': DateTime(2025, 1, 1).toIso8601String(),
        'worldview': '远古传说',
      };

      final restored = StudioSeries.fromJson(oldJson);
      expect(restored.eraGenre, isEmpty);
      expect(restored.name, equals('旧剧集'));
    });

    test('copyWith 可自由变更 eraGenre', () {
      final series = StudioSeries(
        id: 's_001',
        name: '测试',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        eraGenre: 'ancient_costume',
      );
      final updated = series.copyWith(eraGenre: 'cyberpunk_sci_fi');
      expect(updated.eraGenre, equals('cyberpunk_sci_fi'));
      expect(series.eraGenre, equals('ancient_costume'));
    });
  });

  group('CharacterTurnaroundPrompt 时代锁与负向避雷锁组装', () {
    test('组装三视图正向提示词时融入时代服饰锚点与风格锁', () {
      final xianxia = VisualEraGenre.fromId('xianxia');
      final prompt = CharacterTurnaroundPrompt.build(
        '韩立，青年修士，相貌普通，皮肤微黑',
        styleTokens: '电影布光，8K超高清',
        eraGenre: xianxia,
      );

      // 验证必须包含4区块专业资产图基础约束与去塑料光影
      expect(prompt, contains('Character turnaround sheet'));
      expect(prompt, contains('分4个区块：左侧大图是正面脸部胸像特写'));
      expect(prompt, contains('正面平视全身、标准90度侧面全身、背面全身'));
      expect(prompt, contains('纯白无缝背景'));
      expect(prompt, contains('soft diffused studio lighting'));
      expect(prompt, contains('matte surface'));
      // 验证必须融入时代服饰全身锚点
      expect(prompt, contains('中式传统古装仙侠服饰'));
      expect(prompt, contains('宽袍大袖'));
      // 验证剧集全局风格锁经三视图纯白底清洗后：画风分辨率词被保留
      expect(prompt, contains('8K超高清'));
      // 验证角色本体描述
      expect(prompt, contains('韩立，青年修士'));
    });

    test('组装三视图负向提示词时强力合并时代负向禁绝词', () {
      final xianxia = VisualEraGenre.fromId('xianxia');
      final neg = CharacterTurnaroundPrompt.buildNegative(
        baseNegative: 'bad hands, low quality',
        eraGenre: xianxia,
      );

      // 验证基础排畸约束
      expect(neg, contains('切头'));
      expect(neg, contains('断脚'));
      expect(neg, contains('多个人物'));
      // 验证用户基础负向
      expect(neg, contains('bad hands, low quality'));
      // 验证时代严禁项
      expect(neg, contains('短袖短裤'));
      expect(neg, contains('现代服饰'));
      expect(neg, contains('牛仔裤'));
    });

    test('无时代设定时负向提示词正常回落标准三视图排畸', () {
      final neg = CharacterTurnaroundPrompt.buildNegative(
        baseNegative: 'blurry',
        eraGenre: null,
      );
      expect(neg, contains('切头'));
      expect(neg, contains('断脚'));
      expect(neg, contains('多个人物'));
      expect(neg, contains('blurry'));
      expect(neg.contains('短袖短裤'), isFalse);
    });
  });

  group('AiConstraintEngine 小说拆解 Schema 验证', () {
    test('小说主资产抽取 Schema 正确捕获并验证 era_genre', () {
      final validRaw = '''
{
  "era_genre": "xianxia",
  "worldview": "修真大世界，修仙者乘风御剑，凡人如蚁",
  "style_tokens": "traditional Chinese ink wash style, cinematic lighting",
  "characters": [
    {
      "name": "韩立",
      "description_zh": "青年修士，相貌普通，皮肤微黑，身着青灰长袍，腰系布带，下身直缀长袍垂至足尖，足登布履",
      "personality": "沉稳谨慎，心性坚韧",
      "role": "主角",
      "tts_voice_id": "male_cultivator"
    }
  ],
  "scenes": [
    {
      "name": "落云宗药园",
      "description_zh": "灵气缥缈的山谷药园，古朴茅屋，灵草繁茂",
      "prompt_en": "ethereal ancient mountain valley herb garden, misty, ancient wooden hut"
    }
  ],
  "props": [
    {
      "name": "掌天瓶",
      "description_zh": "巴掌大小的翠绿小瓶，周身布满墨绿色灵纹，青铜古玉质感",
      "prompt_en": "palm-sized emerald green ancient flask, mystical glowing patterns",
      "is_key_prop": true
    }
  ]
}
''';
      final rawMap = AiConstraintEngine.parseJsonLoose(validRaw);
      expect(rawMap, isNotNull);
      final validated = AiConstraintEngine.validateSchema(
        StudioAiTask.novelMasterExtraction,
        rawMap!,
      );
      expect(validated, isNotNull);

      expect(validated!['era_genre'], equals('xianxia'));
      expect(validated['worldview'], contains('修真大世界'));
      expect(validated['characters'], hasLength(1));
      expect(validated['characters'][0]['name'], equals('韩立'));
      expect(validated['scenes'], hasLength(1));
    });

    test('小说主资产缺少 era_genre 时自动补齐空字符串', () {
      final withoutEra = '''
{
  "worldview": "奇幻世界",
  "style_tokens": "cinematic",
  "characters": [
    {
      "name": "亚瑟",
      "description_zh": "金发骑士",
      "personality": "勇敢"
    }
  ],
  "scenes": []
}
''';
      final rawMap = AiConstraintEngine.parseJsonLoose(withoutEra);
      expect(rawMap, isNotNull);
      final validated = AiConstraintEngine.validateSchema(
        StudioAiTask.novelMasterExtraction,
        rawMap!,
      );
      expect(validated, isNotNull);
      expect(validated!['era_genre'], equals(''));
    });
  });

  group('CharacterTurnaroundProportion 体态比例与提示词组装', () {
    test('标准比例与 Q 版萌系基础属性与 fromId 正确映射', () {
      expect(CharacterTurnaroundProportion.standard.id, equals('standard'));
      expect(CharacterTurnaroundProportion.standard.filename, equals('turnaround.png'));
      expect(CharacterTurnaroundProportion.standard.labelZh, contains('标准比例'));

      expect(CharacterTurnaroundProportion.chibi.id, equals('chibi'));
      expect(CharacterTurnaroundProportion.chibi.filename, equals('turnaround_chibi.png'));
      expect(CharacterTurnaroundProportion.chibi.labelZh, contains('Q版萌系'));

      expect(CharacterTurnaroundProportion.fromId('standard'), equals(CharacterTurnaroundProportion.standard));
      expect(CharacterTurnaroundProportion.fromId('chibi'), equals(CharacterTurnaroundProportion.chibi));
      expect(CharacterTurnaroundProportion.fromId('unknown'), equals(CharacterTurnaroundProportion.standard));
      expect(CharacterTurnaroundProportion.fromId(null), equals(CharacterTurnaroundProportion.standard));
    });

    test('标准比例三视图提示词注入 7~8 头身锚点并反向禁绝 Q 版 SD 风格', () {
      final prompt = CharacterTurnaroundPrompt.build(
        '李长寿，俊美青年修士',
        proportion: CharacterTurnaroundProportion.standard,
      );
      expect(prompt, contains('标准7~8头身成人体态比例'));
      expect(prompt, contains('身材修长挺拔匀称'));
      expect(prompt, contains('写实人体结构'));

      final neg = CharacterTurnaroundPrompt.buildNegative(
        baseNegative: 'lowres',
        proportion: CharacterTurnaroundProportion.standard,
      );
      expect(neg, contains('Q版'));
      expect(neg, contains('大头娃娃'));
      expect(neg, contains('2头身'));
    });

    test('Q 版萌系三视图提示词注入 2.5 头身萌系锚点并反向禁绝修长写实身形', () {
      final prompt = CharacterTurnaroundPrompt.build(
        '李长寿，纸人化身',
        proportion: CharacterTurnaroundProportion.chibi,
      );
      expect(prompt, contains('Q版萌系体态'));
      expect(prompt, contains('二头半萌态身型'));
      expect(prompt, contains('大圆脸圆脑袋'));
      expect(prompt, contains('娇小萌系体型'));

      final neg = CharacterTurnaroundPrompt.buildNegative(
        baseNegative: 'blurry',
        proportion: CharacterTurnaroundProportion.chibi,
      );
      expect(neg, contains('写实成人比例'));
      expect(neg, contains('修长身材'));
      expect(neg, contains('8头身'));
      expect(neg.contains('大头娃娃'), isFalse);
    });
  });
}

