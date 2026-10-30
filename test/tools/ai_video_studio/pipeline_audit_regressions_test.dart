import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/breakdown_input.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_generation_tasks.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_task_queue.dart';

class _TestRunner implements StudioTaskRunner {
  @override
  final String taskId;
  final Future<String> Function(void Function(double) onProgress) body;

  _TestRunner(this.taskId, this.body);

  @override
  bool isCancelled() => false;

  @override
  Future<String> run(void Function(double progress) onProgress) =>
      body(onProgress);
}

void main() {
  late Directory root;
  final manager = StudioProjectManager.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('studio_pipeline_audit_test');
    AppPaths.overrideRootForTesting(root);
    manager.resetCachesForTesting();
  });

  tearDown(() {
    AppPaths.resetForTesting();
    manager.resetCachesForTesting();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  // ===========================================================================
  // Task 1.5: BreakdownInput.synopsisOf & hasUnsyncedRawScreenplay 双轨优先级
  // ===========================================================================
  group('1.5 BreakdownInput 粗大纲不遮蔽文学剧本 & 双轨未同步检测', () {
    StudioEpisode makeEpisode({
      required String synopsis,
      required String screenplayText,
      List<DramaScene>? scenes,
    }) {
      final now = DateTime(2026, 10, 25);
      return StudioEpisode(
        id: 'ep_01',
        seriesId: 's_01',
        index: 1,
        title: '第一集',
        synopsis: synopsis,
        screenplayText: screenplayText,
        scenes: scenes ??
            const [
              DramaScene(
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
                    action: '东方诏递刀',
                  ),
                ],
              ),
            ],
        createdAt: now,
        updatedAt: now,
      );
    }

    test('rawTextOverride 等于未改动粗大纲时，不遮蔽 screenplayText', () {
      final ep = makeEpisode(
        synopsis: '4行粗大纲：沈长青入职镇魔司。',
        screenplayText: '### 第1场 镇魔司大殿\n完整精修文学剧本正文。',
      );

      // 模拟分镜看板传入未改动的 _synopsisController.text
      expect(
        BreakdownInput.synopsisOf(
          ep,
          rawTextOverride: '4行粗大纲：沈长青入职镇魔司。',
        ),
        '### 第1场 镇魔司大殿\n完整精修文学剧本正文。',
      );
    });

    test('rawTextOverride 被用户实际修改且不等于 synopsis 时，优先采用 override', () {
      final ep = makeEpisode(
        synopsis: '4行粗大纲：沈长青入职镇魔司。',
        screenplayText: '### 第1场 镇魔司大殿\n完整精修文学剧本正文。',
      );

      expect(
        BreakdownInput.synopsisOf(
          ep,
          rawTextOverride: '用户在看板手动改写的新剧情大纲',
        ),
        '用户在看板手动改写的新剧情大纲',
      );
    });

    test('hasUnsyncedRawScreenplay 能准确识别全文剧本独立于 scenes 的修改', () {
      final baseScenes = const [
        DramaScene(
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
              action: '东方诏递刀',
            ),
          ],
        ),
      ];
      final syncedEp = makeEpisode(
        synopsis: '粗大纲',
        screenplayText: '',
        scenes: baseScenes,
      );
      expect(BreakdownInput.hasUnsyncedRawScreenplay(syncedEp), isFalse);

      final modifiedRawEp = makeEpisode(
        synopsis: '粗大纲',
        screenplayText: '用户在全文模式下改写：沈长青拔刀斩碎石柱，拒绝受封！',
        scenes: baseScenes,
      );
      expect(BreakdownInput.hasUnsyncedRawScreenplay(modifiedRawEp), isTrue);
    });
  });

  // ===========================================================================
  // Task 2.3: ShotVariationResolver.resolveCharacterForShot 互斥激活与选图
  // ===========================================================================
  group('2.3 ShotVariationResolver 单镜形态互斥激活与 AssetBindingResolver 选图', () {
    test('resolveCharacterForShot 将命中形态置为 active:true 并取消默认形态的 active', () async {
      final series = await manager.createSeries(name: '形态互斥测试剧');
      final card = CharacterCard(
        id: 'c_jiang',
        name: '姜七夜',
        variations: const [
          CharacterVariation(
            id: 'v_default',
            name: '默认',
            attirePrompt: 'grey linen robe',
            active: true,
          ),
          CharacterVariation(
            id: 'v_battle',
            name: '战损黑袍',
            attirePrompt: 'blood-stained torn black armor',
            active: false,
          ),
        ],
        updatedAt: DateTime(2026),
      );
      await manager.saveCharacter(series.id, card);

      final dir = manager.characterDir(series.id, card.id);
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'turnaround_v_default.png'))
          .writeAsString('default_img');
      await File(p.join(dir.path, 'turnaround_v_battle.png'))
          .writeAsString('battle_img');

      // 分镜在动作描述中提及「战损黑袍」（即使未显式填 characterVariations map 也能自动匹配）
      const shot = StudioShot(
        number: 1,
        actionZh: '姜七夜身披战损黑袍立于断崖之上',
        characterIds: ['c_jiang'],
      );

      final resolvedCard = ShotVariationResolver.resolveCharacterForShot(
        episode: null,
        shot: shot,
        character: card,
      );

      expect(resolvedCard.variations[0].active, isFalse,
          reason: '默认形态必须取消 active，否则 firstWhere((v) => v.active) 会误取 index 0');
      expect(resolvedCard.variations[1].active, isTrue);
      expect(
        resolvedCard.activeVariation?.attirePrompt,
        'blood-stained torn black armor',
      );

      // 验证 AssetBindingResolver 选图拿到的是 turnaround_v_battle.png 而非 turnaround_v_default.png
      final materials = AssetBindingResolver.resolve(
        shot: shot,
        characters: [resolvedCard],
        scene: null,
        seriesId: series.id,
        manager: manager,
      );
      expect(materials, hasLength(1));
      expect(materials.single.filePath, endsWith('turnaround_v_battle.png'));
    });
  });

  // ===========================================================================
  // Task 3.4: PromptAssembler 过期缓存失效回退与 <Picture N> 全链路保留
  // ===========================================================================
  group('3.4 buildVideoGenPrompt 过期回退与 buildSanitizedVideoPrompt <Picture N> 保留', () {
    StudioEpisode dummyEp(List<StudioShot> shots) => StudioEpisode(
          id: 'ep_test',
          seriesId: 's_test',
          index: 1,
          title: '测试集',
          shots: shots,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('shot.isVideoPromptStale 为 true 时忽略旧快照，重新按最新字段与素材组装', () {
      const base = StudioShot(
        number: 1,
        actionZh: '姜七夜拱手',
        characterIds: ['c1'],
      );
      final savedWithSnapshot = base.copyWith(
        videoPrompt: 'OLD_CACHED_PROMPT_WITHOUT_PICTURE',
        videoPromptSourceKey: base.videoPromptSourceKeyOf,
      );
      // 尚未修改字段时返回缓存快照
      expect(
        PromptAssembler.buildVideoGenPrompt(
          shot: savedWithSnapshot,
          episode: dummyEp([savedWithSnapshot]),
        ),
        'OLD_CACHED_PROMPT_WITHOUT_PICTURE',
      );

      // 用户修改了动作并绑定了参考图后，缓存已过期
      final modified = savedWithSnapshot.copyWith(
        actionZh: '姜七夜拔刀横斩',
        assetBindings: const {
          'c1': ShotAssetBinding(materialPath: 'turnaround.png'),
        },
      );
      expect(modified.isVideoPromptStale, isTrue);

      final materials = [
        const ResolvedAssetMaterial(
          index: 0,
          assetId: 'c1',
          assetName: '姜七夜',
          filePath: '/tmp/turnaround.png',
          role: ShotAssetRole.subject,
          isScene: false,
        ),
      ];
      final rebuilt = PromptAssembler.buildVideoGenPrompt(
        shot: modified,
        episode: dummyEp([modified]),
        materials: materials,
      );
      expect(rebuilt, isNot(equals('OLD_CACHED_PROMPT_WITHOUT_PICTURE')));
      expect(rebuilt, contains('<Picture 1>'));
      expect(rebuilt, contains('姜七夜拔刀横斩'));
    });

    test('buildSanitizedVideoPrompt 传入 materials 时保留 <Picture N> 指令', () {
      const shot = StudioShot(
        number: 1,
        actionZh: '姜七夜拔剑指向沈长青',
        characterIds: ['c1', 'c2'],
      );
      const materials = [
        ResolvedAssetMaterial(
          index: 0,
          assetId: 'c1',
          assetName: '姜七夜',
          filePath: '/tmp/c1.png',
          role: ShotAssetRole.subject,
          isScene: false,
        ),
        ResolvedAssetMaterial(
          index: 1,
          assetId: 'c2',
          assetName: '沈长青',
          filePath: '/tmp/c2.png',
          role: ShotAssetRole.confrontation,
          isScene: false,
        ),
      ];

      final sanitized = PromptAssembler.buildSanitizedVideoPrompt(
        shot: shot,
        episode: dummyEp([shot]),
        materials: materials,
      );
      expect(sanitized, contains('<Picture 1>'));
      expect(sanitized, contains('<Picture 2>'));
    });
  });

  // ===========================================================================
  // Task 4.4: StudioTaskQueue 多前置任务依赖级联 & canRelayFrameFromPrev 强化拦截
  // ===========================================================================
  group('4.4 StudioTaskQueue 多前置依赖 & canRelayFrameFromPrev 反打/视角突变拦截', () {
    test('StudioTaskQueue 等待全部 requiredTaskIds 完成后才启动下游任务', () async {
      final queue = StudioTaskQueue.instance;
      queue.clearFinished();

      final executionOrder = <String>[];
      final idA = queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 101,
        label: '前置A',
        runner: _TestRunner('prereq_a', (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          executionOrder.add('prereq_a');
          return 'a.png';
        }),
      );
      final idB = queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 100,
        label: '前置B',
        runner: _TestRunner('prereq_b', (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          executionOrder.add('prereq_b');
          return 'b.mp4';
        }),
      );
      final depId = queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 101,
        label: '后继接力视频',
        requiredTaskIds: [idA, idB],
        runner: _TestRunner('dep_video', (_) async {
          executionOrder.add('dep_video');
          return 'dep.mp4';
        }),
      );

      final dependent = queue.lookup(depId)!;
      for (int i = 0; i < 40 && !dependent.isTerminal; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(dependent.status, StudioTaskStatus.completed);
      expect(executionOrder, ['prereq_a', 'prereq_b', 'dep_video']);
    });

    test('StudioTaskQueue 任一前置任务失败时级联标记下游任务为失败', () async {
      final queue = StudioTaskQueue.instance;
      queue.clearFinished();

      final idOk = queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 202,
        label: '成功前置',
        runner: _TestRunner('ok_task', (_) async => 'ok.png'),
      );
      final idFail = queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 201,
        label: '失败前置',
        runner: _TestRunner('fail_task', (_) async {
          throw StateError('模拟前镜视频生成失败');
        }),
      );
      final depId = queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 202,
        label: '依赖双前置的子任务',
        requiredTaskIds: [idOk, idFail],
        runner: _TestRunner('relay_child', (_) async => 'child.mp4'),
      );

      final dependent = queue.lookup(depId)!;
      for (int i = 0; i < 40 && !dependent.isTerminal; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(dependent.status, StudioTaskStatus.failed);
      expect(dependent.error, contains('前置任务未满足'));
    });

    test('canRelayFrameFromPrev 拦截俯仰角变化、高度层突变与视线左右翻转', () {
      const basePrev = StudioShot(
        number: 1,
        sceneId: 's_hall',
        characterIds: ['c_jiang'],
        actionZh: '姜七夜缓步前行',
        continuity: ShotContinuity(
          cameraAngle: '平视',
          elevationLevel: 'ground',
          gazeDirection: '朝右',
          screenPosition: '画面左侧',
        ),
      );

      // 相同场景、相同机位、相同朝向 -> 允许接力
      const validNext = StudioShot(
        number: 2,
        sceneId: 's_hall',
        characterIds: ['c_jiang'],
        actionZh: '姜七夜停步驻足',
        continuity: ShotContinuity(
          cameraAngle: '平视',
          elevationLevel: 'ground',
          gazeDirection: '朝右',
          screenPosition: '画面左侧',
        ),
      );
      expect(canRelayFrameFromPrev(basePrev, validNext), isTrue);

      // 俯仰角突变（平视 -> 高空俯拍） -> 拦截
      expect(
        canRelayFrameFromPrev(
          basePrev,
          validNext.copyWith(
            continuity: validNext.continuity.copyWith(cameraAngle: '高空俯拍'),
          ),
        ),
        isFalse,
      );

      // 高度层突变（ground -> rooftop） -> 拦截
      expect(
        canRelayFrameFromPrev(
          basePrev,
          validNext.copyWith(
            continuity: validNext.continuity.copyWith(elevationLevel: 'rooftop'),
          ),
        ),
        isFalse,
      );

      // 视线方向左右翻转（朝右 -> 朝左，典型正反打） -> 拦截
      expect(
        canRelayFrameFromPrev(
          basePrev,
          validNext.copyWith(
            continuity: validNext.continuity.copyWith(gazeDirection: '朝左'),
          ),
        ),
        isFalse,
      );
    });
  });

  // ===========================================================================
  // Task 5.5: sampleNovelTextForContext 长文中部采样 & mergeMasterAssets 增量演进
  // ===========================================================================
  group('5.5 长篇小说多窗口均匀采样 & mergeMasterAssets 角色描述升级与新服装形态追加', () {
    test('sampleNovelTextForContext 对 >35,000 字长文保留首部、5个中部均匀窗口与尾部', () {
      final sb = StringBuffer();
      for (int i = 0; i < 2000; i++) {
        sb.writeln('第$i段：这是长篇小说在进度 ${(i / 20).toStringAsFixed(1)}% 处的剧情段落内容，包含特定中后期角色与招式描写。');
      }
      final fullNovel = sb.toString();
      expect(fullNovel.length, greaterThan(70000));

      final sampled = AiConstraintEngine.sampleNovelTextForContext(
        fullNovel,
        maxChars: 35000,
      );

      // 首部保留
      expect(sampled, contains('第0段：'));
      // 尾部保留
      expect(sampled, contains('第1999段：'));
      // 5 个中部采样窗口标记全部存在，不再出现旧版硬截断
      expect(sampled, isNot(contains('[...中间精彩章节省略...]')));
      for (int w = 1; w <= 5; w++) {
        expect(sampled, contains('[...全书中部采样片段 $w/5'));
      }
    });

    test('mergeMasterAssets 自动升级更详尽的角色/场景描述并追加新服装形态，同时保留既有锚点图与激活态', () async {
      final series = await manager.createSeries(name: '增量演进测试剧');

      // 初始导入：角色只有简短描述与初始青衫造型，且已生成一张参考图并激活默认形态
      final initialChar = CharacterCard(
        id: 'c_shen',
        name: '沈长青',
        descriptionZh: '镇魔司学徒',
        facialFeaturesZh: '黑发青年',
        facialPrompt: 'young man with black hair',
        defaultAttireZh: '青色布衣',
        defaultAttirePrompt: 'cyan cotton robe',
        basePromptPositive: 'young man, cyan cotton robe',
        referenceImages: const ['anchor_face.png'],
        variations: const [
          CharacterVariation(
            id: 'v_init',
            name: '默认',
            attirePrompt: 'cyan cotton robe',
            active: true,
          ),
        ],
        updatedAt: DateTime(2026, 1, 1),
      );
      await manager.saveCharacter(series.id, initialChar);

      // 后续章节增量合并：同名角色拥有更详尽的外貌描写，并换上了「镇魔司玄甲飞鱼服」
      await manager.mergeMasterAssets(
        seriesId: series.id,
        masterExtraction: {
          'characters': [
            {
              'name': '沈长青',
              'description_zh': '大秦镇魔司破山城除魔使，眼神冷峻如刀，气血如烘炉',
              'facial_features_zh': '剑眉星目，轮廓分明的冷峻黑发青年，右眉有一道浅痕',
              'facial_prompt':
                  'sharp sword eyebrows, cold resolute eyes, young man with black hair and faint scar on right brow',
              'default_attire_zh': '镇魔司玄甲飞鱼服',
              'attire_prompt':
                  'black gold embroidered flying fish uniform with dark iron shoulder guards',
              'base_prompt_positive':
                  'masterpiece, sharp sword eyebrows, cold resolute eyes, black gold flying fish uniform',
            },
          ],
        },
      );

      final chars = await manager.listCharacters(series.id);
      expect(chars, hasLength(1));
      final updated = chars.single;

      // 1. 既有锚点图未丢失
      expect(updated.referenceImages, ['anchor_face.png']);
      // 2. 描述与五官升级为更详尽版本
      expect(updated.descriptionZh, contains('除魔使'));
      expect(updated.facialFeaturesZh, contains('剑眉星目'));
      expect(updated.facialPrompt, contains('sharp sword eyebrows'));
      // 3. 原默认服饰保持不变，新服饰作为非激活的新 CharacterVariation 追加
      expect(updated.defaultAttireZh, '青色布衣');
      expect(updated.variations, hasLength(2));
      expect(updated.variations[0].id, 'v_init');
      expect(updated.variations[0].active, isTrue);
      expect(updated.variations[1].name, '镇魔司玄甲飞鱼服');
      expect(
        updated.variations[1].attirePrompt,
        'black gold embroidered flying fish uniform with dark iron shoulder guards',
      );
      expect(updated.variations[1].active, isFalse);
    });
  });
}
