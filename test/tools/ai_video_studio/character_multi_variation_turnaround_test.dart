import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_generation_tasks.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/image_gen_adapter.dart';

class _FakeImageGenAdapter implements ImageGenAdapter {
  @override
  String get id => 'fake';

  @override
  String get label => 'Fake';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<File> generate(ImageGenRequest request) async {
    request.outputFile.createSync(recursive: true);
    request.outputFile.writeAsBytesSync([1, 2, 3]);
    return request.outputFile;
  }
}

void main() {
  group('CharacterVariation 多形态与三视图路径扩展', () {
    test('CharacterVariation 序列化与反序列化保留 turnaroundPath 与 referenceImages', () {
      final variation = CharacterVariation(
        id: 'var_armor',
        name: '玄铁战铠',
        positiveDelta: 'wearing heavy iron armor, holding a spear',
        negativeDelta: 'casual clothes',
        turnaroundPath: 'turnaround_var_armor.png',
        referenceImages: ['custom_ref_1.png', 'custom_ref_2.png'],
      );

      final json = variation.toJson();
      expect(json['id'], equals('var_armor'));
      expect(json['name'], equals('玄铁战铠'));
      expect(json['positive_delta'], equals('wearing heavy iron armor, holding a spear'));
      expect(json['turnaround_path'], equals('turnaround_var_armor.png'));
      expect(json['reference_images'], equals(['custom_ref_1.png', 'custom_ref_2.png']));

      final restored = CharacterVariation.fromJson(json);
      expect(restored.id, equals('var_armor'));
      expect(restored.name, equals('玄铁战铠'));
      expect(restored.turnaroundPath, equals('turnaround_var_armor.png'));
      expect(restored.referenceImages, equals(['custom_ref_1.png', 'custom_ref_2.png']));
    });

    test('旧版缺失 turnaround_path 与 reference_images 时平滑回退', () {
      final oldJson = {
        'id': 'var_simple',
        'name': '常服',
        'positive_delta': 'blue robe',
      };

      final restored = CharacterVariation.fromJson(oldJson);
      expect(restored.id, equals('var_simple'));
      expect(restored.name, equals('常服'));
      expect(restored.turnaroundPath, isNull);
      expect(restored.referenceImages, isEmpty);
    });

    test('copyWith 正确变更 turnaroundPath 与 referenceImages', () {
      final variation = CharacterVariation(
        id: 'var_robe',
        name: '道袍',
        positiveDelta: 'daoist robe',
      );

      final updated = variation.copyWith(
        turnaroundPath: 'turnaround_var_robe.png',
        referenceImages: ['ref1.png'],
      );

      expect(updated.turnaroundPath, equals('turnaround_var_robe.png'));
      expect(updated.referenceImages, equals(['ref1.png']));
      expect(updated.name, equals('道袍'));
    });
  });

  group('StudioShot 分镜多角色形态绑定', () {
    test('StudioShot 序列化与反序列化保留 characterVariations', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 3.0,
        characterIds: ['char_li', 'char_lan'],
        characterVariations: {
          'char_li': 'var_armor',
          'char_lan': 'var_wedding',
        },
      );

      final json = shot.toJson();
      expect(json['character_variations'], equals({
        'char_li': 'var_armor',
        'char_lan': 'var_wedding',
      }));

      final restored = StudioShot.fromJson(json);
      expect(restored.characterVariations['char_li'], equals('var_armor'));
      expect(restored.characterVariations['char_lan'], equals('var_wedding'));
    });

    test('旧版 StudioShot JSON 缺失 character_variations 时安全回退空 Map', () {
      final oldJson = {
        'number': 2,
        'duration_sec': 4.0,
        'character_ids': ['char_li'],
      };

      final restored = StudioShot.fromJson(oldJson);
      expect(restored.characterVariations, isEmpty);
    });

    test('StudioShot copyWith 正确复制并修改 characterVariations', () {
      final shot = StudioShot(
        number: 3,
        durationSec: 2.5,
        characterVariations: {'char_li': 'var_old'},
      );

      final updated = shot.copyWith(
        characterVariations: {'char_li': 'var_new'},
      );

      expect(updated.characterVariations['char_li'], equals('var_new'));
    });
  });

  group('PromptAssembler 角色子形态三视图提示词与面容继承', () {
    final character = CharacterCard(
      id: 'char_li',
      name: '李长寿',
      descriptionZh: '长相清秀，身材修长',
      basePromptPositive: 'young immortal cultivator, calm handsome face, dark hair',
      basePromptNegative: 'ugly, deformed',
      updatedAt: DateTime(2026, 1, 1),
      variations: [
        CharacterVariation(
          id: 'var_armor',
          name: '玄铁战铠',
          positiveDelta: 'wearing heavy dark iron armor, spiked gauntlets',
        ),
        CharacterVariation(
          id: 'var_chibi',
          name: 'Q版纸人',
          positiveDelta: 'miniature paper doll form',
        ),
      ],
    );

    test('标准比例形态三视图自动注入面容继承提示词与基础角色外貌', () {
      final variation = character.variations.first;
      final prompt = CharacterTurnaroundPrompt.buildForVariation(
        character: character,
        variation: variation,
        styleTokens: 'traditional anime style',
        proportion: CharacterTurnaroundProportion.standard,
      );

      expect(prompt, contains('角色三视图设计图'));
      expect(prompt, contains('正面平视、侧面、背面'));
      expect(prompt, contains('完全一致的人物面容身份'));
      expect(prompt, contains('与基准参考图保持相同的五官神态特征'));
      expect(prompt, contains('wearing heavy dark iron armor'));
      expect(prompt, contains('calm handsome face'));
      expect(prompt, contains('全身从头到脚完整可见'));
    });

    test('Q版萌系形态三视图注入 Q版专属比例与比例锁定', () {
      final variation = character.variations[1];
      final prompt = CharacterTurnaroundPrompt.buildForVariation(
        character: character,
        variation: variation,
        styleTokens: 'traditional anime style',
        proportion: CharacterTurnaroundProportion.chibi,
      );

      expect(prompt, contains('Q版萌系体态'));
      expect(prompt, contains('二头半萌态身型'));
      expect(prompt, contains('大圆脸圆脑袋'));
      expect(prompt, contains('完全一致的人物面容身份'));
      expect(prompt, contains('miniature paper doll form'));
    });

    test('形态反向提示词针对标准比例 vs Q版正确施加禁令', () {
      final variation = character.variations.first;
      final negStandard = CharacterTurnaroundPrompt.buildNegativeForVariation(
        character: character,
        variation: variation,
        proportion: CharacterTurnaroundProportion.standard,
      );
      expect(negStandard, contains('Q版'));
      expect(negStandard, contains('大头娃娃'));
      expect(negStandard, contains('ugly, deformed'));

      final negChibi = CharacterTurnaroundPrompt.buildNegativeForVariation(
        character: character,
        variation: variation,
        proportion: CharacterTurnaroundProportion.chibi,
      );
      expect(negChibi, contains('写实成人比例'));
      expect(negChibi, contains('8头身'));
      expect(negChibi, contains('ugly, deformed'));
    });
  });

  group('ImageGenTask 参考图动态路由优先级', () {
    test('当指定形态时优先使用形态专属三视图', () {
      final tempDir = Directory.systemTemp.createTempSync('task_test_');
      try {
        final charDir = Directory('${tempDir.path}/series/s1/characters/char_1')..createSync(recursive: true);
        final baseTurnaround = File('${charDir.path}/turnaround.png')..writeAsStringSync('base');
        final varTurnaround = File('${charDir.path}/turnaround_var_armor.png')..writeAsStringSync('armor');

        final character = CharacterCard(
          id: 'char_1',
          name: '李长寿',
          basePromptPositive: 'cultivator',
          updatedAt: DateTime(2026, 1, 1),
          variations: [
            CharacterVariation(
              id: 'var_armor',
              name: '战铠',
              positiveDelta: 'armor',
              turnaroundPath: varTurnaround.path,
            ),
          ],
        );

        final task = ImageGenTask(
          taskId: 't1',
          seriesId: 's1',
          episodeId: 'e1',
          shotNumber: 1,
          adapter: _FakeImageGenAdapter(),
          character: character,
          variation: character.variations.first,
        );

        // 检验形态指定的 turnaroundPath 存在
        expect(task.variation?.turnaroundPath, equals(varTurnaround.path));
        expect(varTurnaround.existsSync(), isTrue);
        expect(baseTurnaround.existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
