import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// spec: shot-asset-binding · 第 3 组（素材指代编号与取材统一）
void main() {
  group('AssetBindingResolver', () {
    late Directory root;
    late Directory charDirJiang;
    late Directory charDirWang;
    late Directory sceneDir;

    setUp(() {
      root = Directory.systemTemp.createTempSync('resolver_test');
      AppPaths.overrideRootForTesting(root);
      // characterDir(sceneDir) 的真实形状是 <root>/video_studio/series_library/
      // <seriesId>/characters/<id>；这里只关心它能被指到临时目录，所以用真实
      // manager 反查目录再往里造文件。
      final seriesDir = StudioProjectManager.instance.charactersDir('s');
      charDirJiang = Directory('${seriesDir.path}/c_jiang')
        ..createSync(recursive: true);
      charDirWang = Directory('${seriesDir.path}/c_wang')
        ..createSync(recursive: true);
      sceneDir = StudioProjectManager.instance.sceneDir('s', 's_yamen')
        ..createSync(recursive: true);
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final jiang = CharacterCard(
      id: 'c_jiang', name: '姜七夜', descriptionZh: '青年', updatedAt: DateTime(2026));
    final wang = CharacterCard(
      id: 'c_wang', name: '老王', descriptionZh: '牢头', updatedAt: DateTime(2026));

    SceneCard yamen() => SceneCard(
      id: 's_yamen',
      name: '衙门',
      promptEn: 'yamen',
      referenceImages: ['view_front.png'],
      updatedAt: DateTime(2026));

        test('编号 = 有序列表下标 + 1，角色按 characterIds 顺序、场景排最后', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${charDirWang.path}/turnaround.png').writeAsStringSync('x');
      File('${sceneDir.path}/view_front.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        characterIds: ['c_jiang', 'c_wang'],
        sceneId: 's_yamen',
      );

      final materials = AssetBindingResolver.resolve(
        shot: shot,
        characters: [jiang, wang],
        scene: yamen(),
        seriesId: 's',
      );

      expect(materials.length, 3);
      expect(materials[0].pictureTag, '<Picture 1>');
      expect(materials[1].pictureTag, '<Picture 2>');
      expect(materials[2].pictureTag, '<Picture 3>');
      expect(materials[0].assetName, '姜七夜');
      expect(materials[1].assetName, '老王');
      expect(materials[2].isScene, isTrue);
      expect(materials[2].assetName, '衙门');
    });

    test('空 materialPath 时取系统默认（三视图优先）', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${charDirJiang.path}/ref_upload.png').writeAsStringSync('x');

      final shot = const StudioShot(number: 1, characterIds: ['c_jiang']);
      final materials = AssetBindingResolver.resolve(
        shot: shot, characters: [jiang], seriesId: 's');

      expect(materials.single.filePath.endsWith('turnaround.png'), isTrue);
    });

    test('显式 materialPath 优先于系统默认', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${charDirJiang.path}/ref_upload.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        characterIds: ['c_jiang'],
        assetBindings: {'c_jiang': const ShotAssetBinding(materialPath: 'ref_upload.png')},
      );
      final materials = AssetBindingResolver.resolve(
        shot: shot, characters: [jiang], seriesId: 's');

      expect(materials.single.filePath.endsWith('ref_upload.png'), isTrue);
    });

    test('名称互相包含时编号不错位（老王 vs 老王头）', () {
      final wangTou = CharacterCard(
        id: 'c_wt', name: '老王头', descriptionZh: '捕头', updatedAt: DateTime(2026));
      final wtDir = Directory('${StudioProjectManager.instance.charactersDir('s').path}/c_wt')
        ..createSync(recursive: true);
      File('${charDirWang.path}/turnaround.png').writeAsStringSync('x');
      File('${wtDir.path}/turnaround.png').writeAsStringSync('x');

      final shot = const StudioShot(number: 1, characterIds: ['c_wang', 'c_wt']);
      final materials = AssetBindingResolver.resolve(
        shot: shot,
        characters: [wang, wangTou],
        seriesId: 's',
      );

      expect(materials.length, 2);
      expect(materials[0].assetName, '老王');
      expect(materials[1].assetName, '老王头');
      // 两张不同的图，两个不同的编号。
      expect(materials[0].filePath, isNot(materials[1].filePath));
      expect(materials[0].pictureTag, isNot(materials[1].pictureTag));
    });

    test('无可用素材的资产被跳过且不占编号', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      // c_wang 目录为空。

      final shot = const StudioShot(number: 1, characterIds: ['c_jiang', 'c_wang']);
      final result = AssetBindingResolver.resolveWithGaps(
        shot: shot,
        characters: [jiang, wang],
        seriesId: 's',
      );

      expect(result.materials.length, 1);
      expect(result.materials.single.pictureTag, '<Picture 1>');
      expect(result.missing, ['老王']);
    });

    test('场景无可用素材时进 missing 但不阻断角色', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');

      final shot = const StudioShot(number: 1, characterIds: ['c_jiang'], sceneId: 's_yamen');
      final result = AssetBindingResolver.resolveWithGaps(
        shot: shot,
        characters: [jiang],
        scene: yamen(),
        seriesId: 's',
      );

      expect(result.materials.length, 1);
      expect(result.missing, ['衙门']);
    });

    test('findSubject 取文本中最早出现的角色', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${charDirWang.path}/turnaround.png').writeAsStringSync('x');

      final materials = AssetBindingResolver.resolve(
        shot: const StudioShot(number: 1, characterIds: ['c_jiang', 'c_wang']),
        characters: [jiang, wang],
        seriesId: 's',
      );

      // 文本里老王先出现。
      final subject = AssetBindingResolver.findSubject(
        '老王在背后跳脚，姜七夜转身离去',
        materials,
      );
      expect(subject!.assetName, '老王');
      expect(subject.pictureTag, '<Picture 2>');
    });

    test('findSubject 只认角色，不返回场景', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${sceneDir.path}/view_front.png').writeAsStringSync('x');

      final materials = AssetBindingResolver.resolve(
        shot: const StudioShot(number: 1, characterIds: ['c_jiang'], sceneId: 's_yamen'),
        characters: [jiang],
        scene: yamen(),
        seriesId: 's',
      );

      final subject = AssetBindingResolver.findSubject('衙门内姜七夜拱手', materials);
      expect(subject!.assetName, '姜七夜');
    });
  });
  group('素材指代进入提示词行（4.1~4.4）', () {
    late Directory root2;
    late Directory cdJiang;
    late Directory cdWang;
    late CharacterCard j2;
    late CharacterCard w2;

    setUp(() {
      root2 = Directory.systemTemp.createTempSync('resolver_prompt_test');
      AppPaths.overrideRootForTesting(root2);
      final base = StudioProjectManager.instance.charactersDir('s');
      cdJiang = Directory('${base.path}/c_jiang')..createSync(recursive: true);
      cdWang = Directory('${base.path}/c_wang')..createSync(recursive: true);
      j2 = CharacterCard(id: 'c_jiang', name: '姜七夜', descriptionZh: '二十岁青年', updatedAt: DateTime(2026));
      w2 = CharacterCard(id: 'c_wang', name: '老王', descriptionZh: '五十多岁牢头', updatedAt: DateTime(2026));
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (root2.existsSync()) root2.deleteSync(recursive: true);
    });

    StudioEpisode ep(List<StudioShot> shots) => StudioEpisode(
      id: 'e', seriesId: 's', index: 1, title: 't',
      createdAt: DateTime(2026), updatedAt: DateTime(2026), shots: shots);
    test('buildVideoGenPrompt 含【素材指代】段且每张图有名字', () {
      File('${cdJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${cdWang.path}/turnaround.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        durationSec: 5,
        actionZh: '姜七夜拱手一拜转身牵驴离去，老王在背后跳脚',
        dialogue: '老王：你！你站住！（预估2.0秒）',
        characterIds: ['c_jiang', 'c_wang'],
      );
      final materials = AssetBindingResolver.resolve(
        shot: shot, characters: [j2, w2], seriesId: 's');

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: ep([shot]),
        characters: [j2, w2],
        materials: materials,
      );

      expect(prompt.contains('【素材指代】'), isTrue);
      expect(prompt.contains('<Picture 1> = 姜七夜（主体）'), isTrue);
      expect(prompt.contains('<Picture 2> = 老王（主体）'), isTrue);
    });

    test('时间轴动作行与台词行各带主体编号', () {
      File('${cdJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${cdWang.path}/turnaround.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        durationSec: 5,
        actionZh: '姜七夜拱手一拜转身牵驴离去',
        dialogue: '老王：你！你站住！（预估2.0秒）',
        characterIds: ['c_jiang', 'c_wang'],
      );
      final materials = AssetBindingResolver.resolve(
        shot: shot, characters: [j2, w2], seriesId: 's');

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: ep([shot]),
        characters: [j2, w2],
        materials: materials,
      );

      // 编号行内前置：紧贴主体名之后，不挂时间段末尾（spec: 编号紧贴主体）。
      expect(prompt.contains('姜七夜（<Picture 1>）拱手一拜转身牵驴离去'), isTrue);
      // 台词行经 cleanDialogueForSpeech 剥离了「老王：」前缀，文本里已无角色名，
      // 于是走兜底主体（按说话人解析出的老王）标在行内。
      expect(prompt.contains('台词（2.0s）：'), isTrue);
      expect(prompt.contains('<Picture 2>'), isTrue);
    });

    test('已绑定素材的角色不再重复静态外貌长文', () {
      File('${cdJiang.path}/turnaround.png').writeAsStringSync('x');
      final shot = const StudioShot(number: 1, durationSec: 4, characterIds: ['c_jiang']);
      final materials = AssetBindingResolver.resolve(
        shot: shot, characters: [j2], seriesId: 's');

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: ep([shot]),
        characters: [j2],
        materials: materials,
      );

      expect(prompt.contains('形象以'), isTrue);
      expect(prompt.contains('<Picture 1>'), isTrue);
      // descriptionZh 长文不出现。
      expect(prompt.contains('二十岁青年'), isFalse);
    });

    test('片段提示词的动作行与台词行带编号', () {
      File('${cdJiang.path}/turnaround.png').writeAsStringSync('x');
      final materials = AssetBindingResolver.resolve(
        shot: const StudioShot(number: 1, characterIds: ['c_jiang']),
        characters: [j2], seriesId: 's');

      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          targetDurationSec: 5,
          characters: [j2],
          shots: const [
            SegmentShotParts(
              number: 1,
              actionZh: '姜七夜拱手一拜',
              dialogue: '姜七夜：告辞。（预估1.5秒）',
              characterIds: ['c_jiang'],
              durationSec: 5,
            ),
          ],
        ),
        materials: materials,
      );

      expect(result.positive.contains('动作：姜七夜（<Picture 1>）拱手一拜'), isTrue);
      expect(result.positive.contains('对白：告辞。'), isTrue);
      expect(result.positive.contains('姜七夜（<Picture 1>）'), isTrue);
    });
  });

  group('空间关系编译（5.1~5.4）', () {
    late Directory root3;
    late Directory cdJiang;
    late Directory cdWang;
    late CharacterCard j2;
    late CharacterCard w2;

    setUp(() {
      root3 = Directory.systemTemp.createTempSync('resolver_spatial_test');
      AppPaths.overrideRootForTesting(root3);
      final base = StudioProjectManager.instance.charactersDir('s');
      cdJiang = Directory('${base.path}/c_jiang')..createSync(recursive: true);
      cdWang = Directory('${base.path}/c_wang')..createSync(recursive: true);
      j2 = CharacterCard(id: 'c_jiang', name: '姜七夜', descriptionZh: '二十岁青年', updatedAt: DateTime(2026));
      w2 = CharacterCard(id: 'c_wang', name: '老王', descriptionZh: '五十多岁牢头', updatedAt: DateTime(2026));
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (root3.existsSync()) root3.deleteSync(recursive: true);
    });

    test('对峙分工编译为相互注视', () {
      File('${cdJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${cdWang.path}/turnaround.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        durationSec: 5,
        actionZh: '姜七夜与老王对峙',
        characterIds: ['c_jiang', 'c_wang'],
        assetBindings: const {
          'c_jiang': ShotAssetBinding(),
          'c_wang': ShotAssetBinding(role: ShotAssetRole.confrontation),
        },
        continuity: const ShotContinuity(
          screenPosition: '姜七夜立于画面左侧，老王立于画面右侧',
          gazeDirection: '相对而立',
          gazeTarget: '对方',
        ),
      );
      final materials = AssetBindingResolver.resolve(
        shot: shot, characters: [j2, w2], seriesId: 's');

      final spatial = PromptAssembler.buildSpatialRelationSection(
        shot: shot, materials: materials);

      expect(spatial.contains('姜七夜与老王相对对峙'), isTrue);
      expect(spatial.contains('姜七夜面朝老王'), isTrue);
      expect(spatial.contains('老王面朝姜七夜'), isTrue);
      expect(spatial.contains('目光聚焦于对方'), isTrue);
    });

    test('单角色镜不编造他人注视', () {
      File('${cdJiang.path}/turnaround.png').writeAsStringSync('x');
      final shot = const StudioShot(number: 1, characterIds: ['c_jiang']);
      final materials = AssetBindingResolver.resolve(
        shot: shot, characters: [j2], seriesId: 's');

      final spatial = PromptAssembler.buildSpatialRelationSection(
        shot: shot, materials: materials);

      expect(spatial, isEmpty);
    });

    test('gazeTarget 为空时不编造注视对象', () {
      File('${cdJiang.path}/turnaround.png').writeAsStringSync('x');
      final shot = const StudioShot(
        number: 1,
        characterIds: ['c_jiang'],
        continuity: ShotContinuity(gazeDirection: '面向北门警惕注视'),
      );
      final materials = AssetBindingResolver.resolve(
        shot: shot, characters: [j2], seriesId: 's');

      final spatial = PromptAssembler.buildSpatialRelationSection(
        shot: shot, materials: materials);

      expect(spatial.contains('目光聚焦于'), isFalse);
      expect(spatial.contains('视线面向北门警惕注视'), isTrue);
    });
  });
}
