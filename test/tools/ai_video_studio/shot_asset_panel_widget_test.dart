import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/storyboard_board.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShotAssetPanel Widget & Multi-Asset Binding Tests', () {
    late Directory root;
    late Directory charDirJiang;
    late Directory propDirSword;
    late Directory propDirShield;

    setUp(() {
      root = Directory.systemTemp.createTempSync('shot_asset_panel_wtest_');
      AppPaths.overrideRootForTesting(root);

      final charBase = StudioProjectManager.instance.charactersDir('s_test');
      charDirJiang = Directory('${charBase.path}/c_jiang')..createSync(recursive: true);

      final propBase = StudioProjectManager.instance.propsDir('s_test');
      propDirSword = Directory('${propBase.path}/p_sword')..createSync(recursive: true);
      propDirShield = Directory('${propBase.path}/p_shield')..createSync(recursive: true);
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
    final wang = CharacterCard(
      id: 'c_wang',
      name: '老王',
      descriptionZh: '牢头',
      updatedAt: DateTime(2026),
    );

    final sword = PropCard(
      id: 'p_sword',
      name: '青锋古剑',
      descriptionZh: '玄铁古剑',
      referenceImages: ['sword_front.png', 'sword_detail.png'],
      updatedAt: DateTime(2026),
    );
    final shield = PropCard(
      id: 'p_shield',
      name: '玄武盾',
      descriptionZh: '重型防御盾牌',
      referenceImages: ['shield.png'],
      updatedAt: DateTime(2026),
    );

    testWidgets('面板展开展示出场角色与出场道具列表', (tester) async {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${propDirSword.path}/sword_front.png').writeAsStringSync('x');

      final shot = StudioShot(
        number: 1,
        characterIds: ['c_jiang'],
        propIds: ['p_sword'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShotAssetPanel(
              shot: shot,
              characters: [jiang, wang],
              props: [sword, shield],
              scene: null,
              seriesId: 's_test',
              onEdited: (_) {},
            ),
          ),
        ),
      );

      // ExpansionTile title is visible
      expect(find.text('出场资产'), findsOneWidget);
      expect(find.textContaining('1 角色 · 1 道具'), findsOneWidget);

      // Tap to expand
      await tester.tap(find.text('出场资产'));
      await tester.pumpAndSettle();

      // Check character and prop rows are rendered
      expect(find.text('姜七夜'), findsOneWidget);
      expect(find.text('青锋古剑'), findsOneWidget);

      // Action buttons to add unassigned entities are present
      expect(find.text('添加角色'), findsOneWidget);
      expect(find.text('添加道具'), findsOneWidget);
    });

    testWidgets('点击添加道具弹出菜单并选择未在场道具', (tester) async {
      final shot = const StudioShot(
        number: 1,
        characterIds: ['c_jiang'],
        propIds: ['p_sword'],
      );

      StudioShot? updatedShot;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShotAssetPanel(
              shot: shot,
              characters: [jiang, wang],
              props: [sword, shield],
              scene: null,
              seriesId: 's_test',
              onEdited: (s) => updatedShot = s,
            ),
          ),
        ),
      );

      // Expand panel
      await tester.tap(find.text('出场资产'));
      await tester.pumpAndSettle();

      // Tap "添加道具"
      await tester.tap(find.text('添加道具'));
      await tester.pumpAndSettle();

      // Popup menu should show only unassigned prop: 玄武盾 (sword is already assigned)
      expect(find.text('玄武盾'), findsOneWidget);

      // Select 玄武盾
      await tester.tap(find.text('玄武盾'));
      await tester.pumpAndSettle();

      expect(updatedShot, isNotNull);
      expect(updatedShot!.propIds, ['p_sword', 'p_shield']);
    });

    testWidgets('点击添加角色弹出菜单并选择未在场角色', (tester) async {
      final shot = const StudioShot(
        number: 1,
        characterIds: ['c_jiang'],
      );

      StudioShot? updatedShot;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShotAssetPanel(
              shot: shot,
              characters: [jiang, wang],
              props: [sword, shield],
              scene: null,
              seriesId: 's_test',
              onEdited: (s) => updatedShot = s,
            ),
          ),
        ),
      );

      // Expand panel
      await tester.tap(find.text('出场资产'));
      await tester.pumpAndSettle();

      // Tap "添加角色"
      await tester.tap(find.text('添加角色'));
      await tester.pumpAndSettle();

      // Popup menu should show only unassigned character: 老王 (jiang is already assigned)
      expect(find.text('老王'), findsOneWidget);

      // Select 老王
      await tester.tap(find.text('老王'));
      await tester.pumpAndSettle();

      expect(updatedShot, isNotNull);
      expect(updatedShot!.characterIds, ['c_jiang', 'c_wang']);
    });

    testWidgets('MaterialMultiSelectDialog 支持多选并返回已选素材列表', (tester) async {
      File('${propDirSword.path}/sword_front.png').writeAsStringSync('x');
      File('${propDirSword.path}/sword_detail.png').writeAsStringSync('x');

      final candidates = [
        const AssetMaterialCandidate(fileName: 'sword_front.png', label: '基准参考图', isDefault: true),
        const AssetMaterialCandidate(fileName: 'sword_detail.png', label: '细节特写', isDefault: false),
      ];

      List<String>? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  selectedResult = await showDialog<List<String>>(
                    context: ctx,
                    builder: (_) => MaterialMultiSelectDialog(
                      assetName: '青锋古剑',
                      isProp: true,
                      isScene: false,
                      candidates: candidates,
                      initialSelected: const [],
                      assetDirPath: propDirSword.path,
                    ),
                  );
                },
                child: const Text('打开素材弹窗'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('打开素材弹窗'));
      await tester.pumpAndSettle();

      expect(find.text('选择参考图 · 青锋古剑（道具）'), findsOneWidget);
      expect(find.text('基准参考图'), findsOneWidget);
      expect(find.text('细节特写'), findsOneWidget);

      // Check both candidates
      await tester.tap(find.text('基准参考图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('细节特写'));
      await tester.pumpAndSettle();

      // Click "确定（已选 2 张）"
      expect(find.text('确定（已选 2 张）'), findsOneWidget);
      await tester.tap(find.text('确定（已选 2 张）'));
      await tester.pumpAndSettle();

      expect(selectedResult, ['sword_front.png', 'sword_detail.png']);
    });

    test('端到端装配测试：多角色、多道具及多图绑定完整且有序进入生成参考图载荷', () {
      File('${charDirJiang.path}/turnaround.png').writeAsStringSync('x');
      File('${charDirJiang.path}/face.png').writeAsStringSync('x');

      final wangDir = Directory('${StudioProjectManager.instance.charactersDir('s_test').path}/c_wang')
        ..createSync(recursive: true);
      File('${wangDir.path}/turnaround.png').writeAsStringSync('x');

      File('${propDirSword.path}/sword_front.png').writeAsStringSync('x');
      File('${propDirSword.path}/sword_detail.png').writeAsStringSync('x');
      File('${propDirShield.path}/shield.png').writeAsStringSync('x');

      final sceneDir = StudioProjectManager.instance.sceneDir('s_test', 's_palace')
        ..createSync(recursive: true);
      File('${sceneDir.path}/palace.png').writeAsStringSync('x');

      final palace = SceneCard(
        id: 's_palace',
        name: '玄清殿',
        referenceImages: ['palace.png'],
        updatedAt: DateTime(2026),
      );

      final shot = StudioShot(
        number: 1,
        durationSec: 5,
        actionZh: '姜七夜手提青锋古剑，与老王手持玄武盾遥相对峙',
        characterIds: ['c_jiang', 'c_wang'],
        propIds: ['p_sword', 'p_shield'],
        sceneId: 's_palace',
        assetBindings: {
          'c_jiang': const ShotAssetBinding(
            materialPaths: ['turnaround.png', 'face.png'],
            role: ShotAssetRole.subject,
          ),
          'p_sword': const ShotAssetBinding(
            materialPaths: ['sword_front.png', 'sword_detail.png'],
          ),
        },
      );

      final materials = AssetBindingResolver.resolve(
        shot: shot,
        characters: [jiang, wang],
        props: [sword, shield],
        scene: palace,
        seriesId: 's_test',
      );

      // Total reference images:
      // Jiang: 2 images (<Picture 1>, <Picture 2>)
      // Wang: 1 image (<Picture 3>)
      // Sword: 2 images (<Picture 4>, <Picture 5>)
      // Shield: 1 image (<Picture 6>)
      // Palace: 1 image (<Picture 7>)
      expect(materials.length, 7);

      expect(materials[0].pictureTag, '<Picture 1>');
      expect(materials[0].assetName, '姜七夜');
      expect(materials[0].filePath.endsWith('turnaround.png'), isTrue);

      expect(materials[1].pictureTag, '<Picture 2>');
      expect(materials[1].assetName, '姜七夜');
      expect(materials[1].filePath.endsWith('face.png'), isTrue);

      expect(materials[2].pictureTag, '<Picture 3>');
      expect(materials[2].assetName, '老王');
      expect(materials[2].filePath.endsWith('turnaround.png'), isTrue);

      expect(materials[3].pictureTag, '<Picture 4>');
      expect(materials[3].assetName, '青锋古剑');
      expect(materials[3].isProp, isTrue);
      expect(materials[3].filePath.endsWith('sword_front.png'), isTrue);

      expect(materials[4].pictureTag, '<Picture 5>');
      expect(materials[4].assetName, '青锋古剑');
      expect(materials[4].isProp, isTrue);
      expect(materials[4].filePath.endsWith('sword_detail.png'), isTrue);

      expect(materials[5].pictureTag, '<Picture 6>');
      expect(materials[5].assetName, '玄武盾');
      expect(materials[5].isProp, isTrue);
      expect(materials[5].filePath.endsWith('shield.png'), isTrue);

      expect(materials[6].pictureTag, '<Picture 7>');
      expect(materials[6].assetName, '玄清殿');
      expect(materials[6].isScene, isTrue);
      expect(materials[6].filePath.endsWith('palace.png'), isTrue);

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
        characters: [jiang, wang],
        props: [sword, shield],
        scene: palace,
        materials: materials,
      );

      expect(prompt.contains('【出场道具】'), isTrue);
      expect(prompt.contains('青锋古剑'), isTrue);
      expect(prompt.contains('玄武盾'), isTrue);
      expect(prompt.contains('<Picture 4>'), isTrue);
      expect(prompt.contains('<Picture 6>'), isTrue);
    });
  });
}
