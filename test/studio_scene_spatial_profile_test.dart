import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  group('SceneDirection & SceneDirectionalView & SceneCard', () {
    test('SceneDirection values and keys coverage', () {
      expect(SceneDirection.values.length, 7);
      final keys = SceneDirection.values.map((e) => e.key).toSet();
      expect(keys, containsAll(['front', 'back', 'left', 'right', 'top', 'bottom', 'topDown']));

      expect(SceneDirection.fromKey('front'), SceneDirection.front);
      expect(SceneDirection.fromKey('back'), SceneDirection.back);
      expect(SceneDirection.fromKey('left'), SceneDirection.left);
      expect(SceneDirection.fromKey('right'), SceneDirection.right);
      expect(SceneDirection.fromKey('top'), SceneDirection.top);
      expect(SceneDirection.fromKey('bottom'), SceneDirection.bottom);
      expect(SceneDirection.fromKey('topDown'), SceneDirection.topDown);
      expect(SceneDirection.fromKey('top_down'), SceneDirection.topDown);
      expect(SceneDirection.fromKey('unknown_key'), SceneDirection.front);
    });

    test('SceneDirectionalView serialization and getters', () {
      const view = SceneDirectionalView(
        direction: SceneDirection.top,
        descriptionZh: '雕花梁木藻井',
        promptEn: 'traditional Chinese caisson ceiling',
        imagePath: '/path/to/top.png',
      );

      expect(view.hasImage, isTrue);
      expect(view.hasContent, isTrue);

      final json = view.toJson();
      expect(json['direction'], 'top');
      expect(json['description_zh'], '雕花梁木藻井');
      expect(json['prompt_en'], 'traditional Chinese caisson ceiling');
      expect(json['image_path'], '/path/to/top.png');

      final reconstructed = SceneDirectionalView.fromJson(json);
      expect(reconstructed.direction, SceneDirection.top);
      expect(reconstructed.descriptionZh, '雕花梁木藻井');
      expect(reconstructed.promptEn, 'traditional Chinese caisson ceiling');
      expect(reconstructed.imagePath, '/path/to/top.png');
    });

    test('SceneCard backward compatibility with legacy JSON without spatial_views', () {
      final legacyJson = {
        'id': 'scene_001',
        'name': '破庙正堂',
        'description_zh': '破败的古庙正殿，蛛网密布，供奉着残缺的金身佛像',
        'prompt_en': 'dilapidated temple main hall, dusty atmosphere, broken Buddha statue',
        'reference_images': ['scenes/scene_001/ref1.png'],
        'shared_across_series': false,
        'updated_at': '2026-10-16T12:00:00.000Z',
      };

      final card = SceneCard.fromJson(legacyJson);
      expect(card.id, 'scene_001');
      expect(card.name, '破庙正堂');
      expect(card.descriptionZh, legacyJson['description_zh']);
      expect(card.promptEn, legacyJson['prompt_en']);
      expect(card.referenceImages, ['scenes/scene_001/ref1.png']);

      // 自动补齐 7 方位，且 front 继承主数据
      final fullViews = card.fullSpatialViews;
      expect(fullViews.length, 7);
      final frontView = card.viewFor(SceneDirection.front);
      expect(frontView.descriptionZh, legacyJson['description_zh']);
      expect(frontView.promptEn, legacyJson['prompt_en']);
      expect(frontView.imagePath, 'scenes/scene_001/ref1.png');

      // 其余方位默认空白
      final topView = card.viewFor(SceneDirection.top);
      expect(topView.descriptionZh, isEmpty);
      expect(topView.hasImage, isFalse);
      expect(card.hasSpatialDeconstruction, isFalse);
    });

    test('SceneCard with spatial_views serialization and update helpers', () {
      final now = DateTime.now();
      var card = SceneCard(
        id: 'scene_002',
        name: '丽香苑雅阁',
        descriptionZh: '雅致房间，纱幔低垂',
        promptEn: 'elegant ancient chamber',
        updatedAt: now,
      );

      expect(card.hasSpatialDeconstruction, isFalse);

      // 更新天顶视角
      card = card.withUpdatedSpatialView(const SceneDirectionalView(
        direction: SceneDirection.top,
        descriptionZh: '八角藻井悬挂流苏琉璃宫灯',
        promptEn: 'octagonal caisson ceiling with tassel lanterns',
        imagePath: '/scenes/top.png',
      ));

      expect(card.hasSpatialDeconstruction, isTrue);
      expect(card.viewFor(SceneDirection.top).descriptionZh, '八角藻井悬挂流苏琉璃宫灯');

      // 更新正面视角，检查是否同步更新主属性
      card = card.withUpdatedSpatialView(const SceneDirectionalView(
        direction: SceneDirection.front,
        descriptionZh: '正中红木主案与四扇山水绢丝屏风',
        promptEn: 'center mahogany desk with four-panel landscape silk screen',
        imagePath: '/scenes/front.png',
      ));

      expect(card.descriptionZh, '正中红木主案与四扇山水绢丝屏风');
      expect(card.promptEn, 'center mahogany desk with four-panel landscape silk screen');
      expect(card.referenceImages, contains('/scenes/front.png'));

      // 校验序列化与反序列化
      final json = card.toJson();
      expect(json['spatial_views'], isNotNull);
      final restored = SceneCard.fromJson(json);
      expect(restored.viewFor(SceneDirection.top).descriptionZh, '八角藻井悬挂流苏琉璃宫灯');
      expect(restored.viewFor(SceneDirection.front).descriptionZh, '正中红木主案与四扇山水绢丝屏风');
      expect(restored.hasSpatialDeconstruction, isTrue);
    });
  });

  group('AiConstraintEngine sceneSpatialDeconstruction', () {
    test('StudioAiTask properties and system prompt', () {
      expect(StudioAiTask.sceneSpatialDeconstruction.id, 'scene_spatial_deconstruction');
      expect(StudioAiTask.sceneSpatialDeconstruction.label, '场景空间全息解构');

      final prompt = AiConstraintEngine.systemPromptFor(StudioAiTask.sceneSpatialDeconstruction);
      expect(prompt, contains('七方位空间全息档案'));
      expect(prompt, contains('绝对空间空镜与零人物约束'));
      expect(prompt, contains('front'));
      expect(prompt, contains('topDown'));

      expect(AiConstraintEngine.defaultTimeoutFor(StudioAiTask.sceneSpatialDeconstruction),
          const Duration(seconds: 180));
    });

    test('Schema validation cleanses character narrative and parses 7 views', () {
      final aiRawOutput = {
        'views': {
          'front': {
            'zh': '风月场所丽香苑内的雅致房间，纱幔低垂，琴音袅袅，暗藏耳目与情报。富家公子与江湖草莽在此交错，欲望与阴谋在酒意中发酵。',
            'en': 'front main view, elegant chamber with sheer curtains and guqin, dim light',
          },
          'back': {
            'zh': '双开雕花朱漆大门，门口站着两个带刀侍卫。门外是幽深木质走廊。',
            'en': 'reverse angle view towards entrance door, long dark wooden hallway',
          },
          'top': {
            'zh': '重檐藻井，垂悬琉璃宫灯',
            'en': 'caisson ceiling, low angle upward view',
          },
        }
      };

      final validated = AiConstraintEngine.validateSchema(
        StudioAiTask.sceneSpatialDeconstruction,
        aiRawOutput,
      );

      expect(validated, isNotNull);
      final views = validated!['views'] as Map<String, dynamic>;
      expect(views.containsKey('front'), isTrue);
      final front = views['front'] as Map<String, dynamic>;
      // 验证人物与情节已被清洗
      expect(front['description_zh'], isNot(contains('富家公子')));
      expect(front['description_zh'], isNot(contains('江湖草莽')));
      expect(front['description_zh'], contains('风月场所丽香苑内的雅致房间'));
      expect(front['description_zh'], contains('纱幔低垂'));
      // 英文 Prompt 自动补充纯空镜标签
      expect(front['prompt_en'], contains('empty room'));
      expect(front['prompt_en'], contains('no humans'));

      // back 视角的侍卫句子也被清洗
      final back = views['back'] as Map<String, dynamic>;
      expect(back['description_zh'], isNot(contains('带刀侍卫')));
      expect(back['description_zh'], contains('双开雕花朱漆大门'));

      // 转换为 SceneDirectionalView 映射
      final spatialViews = AiConstraintEngine.parseSpatialViewsFromResult(validated);
      expect(spatialViews.length, 7);
      expect(spatialViews['front']!.descriptionZh, front['description_zh']);
      expect(spatialViews['top']!.descriptionZh, '重檐藻井，垂悬琉璃宫灯。');
      // 未返回的方位有默认占位
      expect(spatialViews['bottom']!.direction, SceneDirection.bottom);
      expect(spatialViews['bottom']!.descriptionZh, isEmpty);
    });
  });

  group('StudioProjectManager scene spatial integration', () {
    late Directory tempDir;
    late StudioProjectManager manager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('studio_spatial_test');
      AppPaths.overrideRootForTesting(tempDir);
      manager = StudioProjectManager.instance;
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('mergeMasterAssets preserves and merges spatial_views', () async {
      final series = await manager.createSeries(name: '剑来测试');
      final seriesId = series.id;

      final extraction = {
        'worldview': '古典仙侠修真世界',
        'era_genre': 'xianxia',
        'scenes': [
          {
            'name': '泥瓶巷祖宅',
            'description_zh': '泥泞小巷尽头的陈旧土坯小院',
            'prompt_en': 'ancient weathered courtyard in small alley',
            'spatial_views': {
              'front': {
                'description_zh': '正房三间，土墙灰瓦',
                'prompt_en': 'front view of clay house, grey tiles',
              },
              'topDown': {
                'description_zh': '俯视长方形逼仄院落，天井中央有口老井',
                'prompt_en': 'top-down view of narrow courtyard with old water well in center',
              },
            },
          }
        ],
      };

      await manager.mergeMasterAssets(
        seriesId: seriesId,
        masterExtraction: extraction,
      );

      final scenes = await manager.listScenes(seriesId);
      expect(scenes.length, 1);
      final scene = scenes.first;
      expect(scene.name, '泥瓶巷祖宅');
      expect(scene.hasSpatialDeconstruction, isTrue);

      final topDown = scene.viewFor(SceneDirection.topDown);
      expect(topDown.descriptionZh, contains('老井'));
      expect(topDown.promptEn, contains('water well'));

      final front = scene.viewFor(SceneDirection.front);
      expect(front.descriptionZh, contains('正房三间'));
    });
  });

  group('PromptAssembler camera angle spatial matching', () {
    test('matchCameraDirection heuristics coverage', () {
      expect(PromptAssembler.matchCameraDirection(cameraMove: 'low angle push-in'), SceneDirection.top);
      expect(PromptAssembler.matchCameraDirection(actionZh: '仰拍屋顶梁木'), SceneDirection.top);
      expect(PromptAssembler.matchCameraDirection(cameraMove: 'high angle aerial'), SceneDirection.topDown);
      expect(PromptAssembler.matchCameraDirection(actionZh: '俯瞰全景鸟瞰'), SceneDirection.topDown);
      expect(PromptAssembler.matchCameraDirection(cameraMove: 'reverse angle shot'), SceneDirection.back);
      expect(PromptAssembler.matchCameraDirection(actionZh: '过肩反打'), SceneDirection.back);
      expect(PromptAssembler.matchCameraDirection(cameraMove: 'pan left'), SceneDirection.left);
      expect(PromptAssembler.matchCameraDirection(actionZh: '向左侧看'), SceneDirection.left);
      expect(PromptAssembler.matchCameraDirection(cameraMove: 'pan right'), SceneDirection.right);
      expect(PromptAssembler.matchCameraDirection(actionZh: '向右侧移'), SceneDirection.right);
      expect(PromptAssembler.matchCameraDirection(cameraMove: 'ground level track'), SceneDirection.bottom);
      expect(PromptAssembler.matchCameraDirection(actionZh: '低机位特写地砖'), SceneDirection.bottom);
      expect(PromptAssembler.matchCameraDirection(cameraMove: 'static eye-level'), SceneDirection.front);
      expect(PromptAssembler.matchCameraDirection(explicitDirection: SceneDirection.top), SceneDirection.top);
    });

    test('buildShotPrompt integrates matched spatial view prompt', () {
      final scene = SceneCard(
        id: 'scene_hall',
        name: '议事大厅',
        descriptionZh: '宏伟大厅',
        promptEn: 'grand imperial hall',
        spatialViews: {
          'top': const SceneDirectionalView(
            direction: SceneDirection.top,
            descriptionZh: '雕龙画凤的金色穹顶',
            promptEn: 'golden dome ceiling with carved dragons, upward angle',
          ),
          'back': const SceneDirectionalView(
            direction: SceneDirection.back,
            descriptionZh: '朱红双开殿门',
            promptEn: 'massive vermilion palace gates, reverse view',
          ),
        },
        updatedAt: DateTime.now(),
      );

      // Low angle shot matches top view
      final topShotPrompt = PromptAssembler.buildShotPrompt(PromptParts(
        scene: scene,
        cameraMove: 'low angle upward tilt',
        actionZh: '抬头仰视',
      ));
      expect(topShotPrompt.positive, contains('golden dome ceiling with carved dragons'));

      // Reverse shot matches back view
      final backShotPrompt = PromptAssembler.buildShotPrompt(PromptParts(
        scene: scene,
        cameraMove: 'reverse shot',
      ));
      expect(backShotPrompt.positive, contains('massive vermilion palace gates'));

      // Normal shot falls back to scene.promptEn
      final normalShotPrompt = PromptAssembler.buildShotPrompt(PromptParts(
        scene: scene,
        cameraMove: 'slow push-in',
      ));
      expect(normalShotPrompt.positive, contains('grand imperial hall'));
    });
  });

  group('ScenePromptBuilder strict empty scene human suppression', () {
    test('sanitizeBasePrompt strips human entities and actions while preserving physical objects', () {
      const dirty = 'bustling street with pedestrians, a vendor talking to someone, people walking near the shop';
      final clean = ScenePromptBuilder.sanitizeBasePrompt(dirty);

      expect(clean.toLowerCase(), isNot(contains('pedestrians')));
      expect(clean.toLowerCase(), isNot(contains('vendor')));
      expect(clean.toLowerCase(), isNot(contains('people')));
      expect(clean.toLowerCase(), isNot(contains('someone')));
      expect(clean.toLowerCase(), isNot(contains('walking')));
      expect(clean.toLowerCase(), isNot(contains('talking')));
      expect(clean.toLowerCase(), contains('street'));
      expect(clean.toLowerCase(), contains('shop'));
      // bustling downgraded to spacious
      expect(clean.toLowerCase(), contains('spacious'));
    });

    test('buildPositivePrompt constructs dual sandwich with affirmative locks and no human tokens', () {
      final prompt = ScenePromptBuilder.buildPositivePrompt(
        basePrompt: 'front main view, wooden tea table and chairs, tea set',
        eraGenreId: 'xianxia',
      );

      // Must start with head lock
      expect(prompt.startsWith(ScenePromptBuilder.emptyHeadLock), isTrue);
      // Must end with tail lock
      expect(prompt.endsWith(ScenePromptBuilder.emptyTailLock), isTrue);
      // Must not contain "no humans" or "no people"
      expect(prompt.toLowerCase(), isNot(contains('no humans')));
      expect(prompt.toLowerCase(), isNot(contains('no people')));
      // Contains affirmative uninhabited keywords in Chinese
      expect(prompt, contains('完全空无一人'));
      expect(prompt, contains('空旷建筑场景'));
      expect(prompt, contains('虚位以待的无人空间'));
    });

    test('buildNegativePrompt includes comprehensive human suppression tokens', () {
      final neg = ScenePromptBuilder.buildNegativePrompt(eraGenreId: 'xianxia');
      expect(neg, contains('人物'));
      expect(neg, contains('人类'));
      expect(neg, contains('人群'));
      expect(neg, contains('路人'));
      expect(neg, contains('面部五官'));
    });

    test('buildPositivePrompt for enclosed dungeon scene strips outdoor clouds, mountains, pavilions', () {
      final prompt = ScenePromptBuilder.buildPositivePrompt(
        basePrompt: '巡城司大牢，幽暗牢狱通道，青石地面潮湿泛着水光，粗木铁栏囚室，牢头值房旧木桌与刑架，铁链悬挂',
        styleTokens: 'UE5渲染，东方仙侠美学，体积光，云海雾气，8K超高细节',
        eraGenreId: 'xianxia',
      );

      expect(prompt, isNot(contains('云海')));
      expect(prompt, isNot(contains('云雾缭绕')));
      expect(prompt, isNot(contains('奇峰仙山')));
      expect(prompt, isNot(contains('亭台楼阁')));
      expect(prompt, isNot(contains('长街古道')));

      expect(prompt, contains('巡城司大牢'));
      expect(prompt, contains('粗木铁栏囚室'));
      expect(prompt, contains('室内局部微光'));
    });
  });
}
