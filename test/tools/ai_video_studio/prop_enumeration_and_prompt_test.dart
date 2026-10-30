import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  group('Prop Material Enumeration & Binding Resolution', () {
    late Directory root;
    late Directory charDirJiang;
    late Directory propDirSword;
    late Directory propDirMirror;
    late Directory sceneDir;

    setUp(() {
      root = Directory.systemTemp.createTempSync('prop_test_');
      AppPaths.overrideRootForTesting(root);
      final charBase = StudioProjectManager.instance.charactersDir('s_test');
      charDirJiang = Directory('${charBase.path}/c_jiang')..createSync(recursive: true);

      final propBase = StudioProjectManager.instance.propsDir('s_test');
      propDirSword = Directory('${propBase.path}/p_sword')..createSync(recursive: true);
      propDirMirror = Directory('${propBase.path}/p_mirror')..createSync(recursive: true);

      sceneDir = StudioProjectManager.instance.sceneDir('s_test', 's_palace')
        ..createSync(recursive: true);
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final jiang = CharacterCard(
      id: 'c_jiang',
      name: '姜七夜',
      descriptionZh: '持剑青年',
      updatedAt: DateTime(2026),
    );

    final sword = PropCard(
      id: 'p_sword',
      name: '青锋古剑',
      descriptionZh: '玄铁铸造，剑身有微弱青光',
      referenceImages: ['sword_front.png', 'sword_detail.png'],
      updatedAt: DateTime(2026),
    );

    final mirror = PropCard(
      id: 'p_mirror',
      name: '照妖古镜',
      descriptionZh: '青铜八卦镜',
      referenceImages: ['mirror.png'],
      updatedAt: DateTime(2026),
    );

    final palace = SceneCard(
      id: 's_palace',
      name: '幽玄大殿',
      promptEn: 'ancient palace',
      referenceImages: ['palace_main.png'],
      updatedAt: DateTime(2026),
    );

    test('AssetMaterialEnumerator.forProp 枚举道具候选图且首张为默认', () {
      File('${propDirSword.path}/sword_front.png').writeAsStringSync('x');
      File('${propDirSword.path}/sword_detail.png').writeAsStringSync('x');

      final candidates = AssetMaterialEnumerator.forProp(
        sword,
        propDirPath: propDirSword.path,
      );

      expect(candidates.length, 2);
      expect(candidates[0].fileName, 'sword_front.png');
      expect(candidates[0].isDefault, isTrue);
      expect(candidates[0].label, '基准参考图');
      expect(candidates[1].fileName, 'sword_detail.png');
      expect(candidates[1].isDefault, isFalse);
      expect(candidates[1].label, '参考图 2');

      final def = AssetMaterialEnumerator.defaultMaterialFor(
        isScene: false,
        isProp: true,
        prop: sword,
        assetDirPath: propDirSword.path,
      );
      expect(def, 'sword_front.png');
    });

    test('AssetBindingResolver.resolve 严格按 角色 ➔ 道具 ➔ 场景 编排 <Picture N>', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${propDirSword.path}/sword_front.png').writeAsStringSync('x');
      File('${propDirMirror.path}/mirror.png').writeAsStringSync('x');
      File('${sceneDir.path}/palace_main.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        characterIds: ['c_jiang'],
        propIds: ['p_sword', 'p_mirror'],
        sceneId: 's_palace',
      );

      final materials = AssetBindingResolver.resolve(
        shot: shot,
        characters: [jiang],
        props: [sword, mirror],
        scene: palace,
        seriesId: 's_test',
      );

      expect(materials.length, 4);
      expect(materials[0].pictureTag, '<Picture 1>');
      expect(materials[0].assetName, '姜七夜');
      expect(materials[0].isProp, isFalse);
      expect(materials[0].isScene, isFalse);

      expect(materials[1].pictureTag, '<Picture 2>');
      expect(materials[1].assetName, '青锋古剑');
      expect(materials[1].isProp, isTrue);
      expect(materials[1].roleLabel, '道具');

      expect(materials[2].pictureTag, '<Picture 3>');
      expect(materials[2].assetName, '照妖古镜');
      expect(materials[2].isProp, isTrue);

      expect(materials[3].pictureTag, '<Picture 4>');
      expect(materials[3].assetName, '幽玄大殿');
      expect(materials[3].isScene, isTrue);
    });

    test('角色与道具多图绑定展开为连续 <Picture N> 编号', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${charDirJiang.path}/face.png').writeAsStringSync('x');
      File('${propDirSword.path}/sword_front.png').writeAsStringSync('x');
      File('${propDirSword.path}/sword_detail.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        characterIds: ['c_jiang'],
        propIds: ['p_sword'],
        assetBindings: {
          'c_jiang': const ShotAssetBinding(
            materialPaths: ['turnaround.png', 'face.png'],
          ),
          'p_sword': const ShotAssetBinding(
            materialPaths: ['sword_front.png', 'sword_detail.png'],
          ),
        },
      );

      final materials = AssetBindingResolver.resolve(
        shot: shot,
        characters: [jiang],
        props: [sword],
        seriesId: 's_test',
      );

      expect(materials.length, 4);
      expect(materials[0].pictureTag, '<Picture 1>');
      expect(materials[0].assetName, '姜七夜');
      expect(materials[0].filePath.endsWith('turnaround.png'), isTrue);

      expect(materials[1].pictureTag, '<Picture 2>');
      expect(materials[1].assetName, '姜七夜');
      expect(materials[1].filePath.endsWith('face.png'), isTrue);

      expect(materials[2].pictureTag, '<Picture 3>');
      expect(materials[2].assetName, '青锋古剑');
      expect(materials[2].isProp, isTrue);
      expect(materials[2].filePath.endsWith('sword_front.png'), isTrue);

      expect(materials[3].pictureTag, '<Picture 4>');
      expect(materials[3].assetName, '青锋古剑');
      expect(materials[3].isProp, isTrue);
      expect(materials[3].filePath.endsWith('sword_detail.png'), isTrue);
    });

    test('resolveWithGaps 检测缺失道具并报告 missing 且不阻塞正常资产', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      // p_sword 目录为空，无素材文件

      final shot = StudioShot(
        number: 1,
        characterIds: ['c_jiang'],
        propIds: ['p_sword'],
      );

      final result = AssetBindingResolver.resolveWithGaps(
        shot: shot,
        characters: [jiang],
        props: [sword],
        seriesId: 's_test',
      );

      expect(result.materials.length, 1);
      expect(result.materials.first.assetName, '姜七夜');
      expect(result.missing, ['青锋古剑']);
    });

    test('PromptAssembler.buildVideoGenPrompt 输出【素材指代】含道具说明与【出场道具】', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${propDirSword.path}/sword_front.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        durationSec: 5,
        actionZh: '姜七夜手握青锋古剑，指向前方',
        characterIds: ['c_jiang'],
        propIds: ['p_sword'],
      );

      final materials = AssetBindingResolver.resolve(
        shot: shot,
        characters: [jiang],
        props: [sword],
        seriesId: 's_test',
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: StudioEpisode(
          id: 'ep1',
          seriesId: 's_test',
          index: 1,
          title: 'Ep 1',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          shots: [shot],
        ),
        characters: [jiang],
        props: [sword],
        materials: materials,
      );

      expect(prompt.contains('【素材指代】'), isTrue);
      expect(prompt.contains('<Picture 1> = 姜七夜（主体）'), isTrue);
      expect(prompt.contains('<Picture 2> = 青锋古剑（道具，实物道具参考）'), isTrue);
      expect(
        prompt.contains('【出场道具】: 青锋古剑（玄铁铸造，剑身有微弱青光）（实物外观以<Picture 2>为准）'),
        isTrue,
      );
    });
  });
}
