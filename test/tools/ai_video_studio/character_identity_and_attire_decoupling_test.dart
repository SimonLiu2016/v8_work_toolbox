import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/image_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  group('CharacterCard & CharacterVariation 容貌与服饰解耦模型', () {
    test('CharacterCard 序列化与反序列化保留容貌体态、默认服装与面部锚点', () {
      final card = CharacterCard(
        id: 'char_jiang',
        name: '姜七夜',
        facialFeaturesZh: '面如冠玉的俊美青年，剑眉入鬓，凤眼薄唇，墨发高束，体态修长',
        facialPrompt: 'handsome young man, jade face, sword eyebrows, phoenix eyes, high ponytail, clean-shaven',
        defaultAttireZh: '内着深青色劲装，外罩玄色巡城司狱卒袍服，腰束黑色板带，悬挂一柄长刀；下着同色长裤与黑色长靴',
        defaultAttirePrompt: 'inner dark cyan martial outfit, outer black prison guard robe, black belt, black boots, long dao blade',
        faceAnchorPath: 'face_anchor.png',
        referenceImages: ['turnaround.png'],
        ttsVoiceId: 'voice_young_hero',
        updatedAt: DateTime(2026, 10, 14),
        variations: [
          CharacterVariation(
            id: 'var_white',
            name: '白色着装',
            attirePrompt: 'wearing pristine white robes, flowing white silk, silver belt',
            positiveDelta: '白色着装',
            turnaroundPath: 'turnaround_var_white.png',
          ),
        ],
      );

      final json = card.toJson();
      expect(json['id'], equals('char_jiang'));
      expect(json['name'], equals('姜七夜'));
      expect(json['facial_features_zh'], contains('面如冠玉'));
      expect(json['facial_prompt'], contains('handsome young man'));
      expect(json['default_attire_zh'], contains('玄色巡城司狱卒袍服'));
      expect(json['default_attire_prompt'], contains('outer black prison guard robe'));
      expect(json['base_prompt_positive'], contains('面如冠玉'));
      expect(json['base_prompt_positive'], contains('玄色巡城司狱卒袍服'));

      final restored = CharacterCard.fromJson(json);
      expect(restored.id, equals('char_jiang'));
      expect(restored.facialFeaturesZh, contains('面如冠玉'));
      expect(restored.facialPrompt, contains('handsome young man'));
      expect(restored.defaultAttireZh, contains('玄色巡城司狱卒袍服'));
      expect(restored.defaultAttirePrompt, contains('outer black prison guard robe'));
      expect(restored.faceAnchorPath, equals('face_anchor.png'));
      expect(restored.variations.first.attirePrompt, contains('pristine white robes'));
      expect(restored.variations.first.effectiveAttirePrompt, contains('pristine white robes'));
    });

    test('旧版缺失解耦字段的 JSON 平滑回退至原有基础 Prompt', () {
      final legacyJson = {
        'id': 'char_old',
        'name': '李长寿',
        'description_zh': '清秀少年，身穿蓝袍',
        'base_prompt_positive': 'handsome young cultivator, blue daoist robe',
        'base_prompt_negative': 'ugly, blurry',
        'reference_images': ['turnaround.png'],
      };

      final restored = CharacterCard.fromJson(legacyJson);
      expect(restored.id, equals('char_old'));
      expect(restored.facialFeaturesZh, equals('清秀少年，身穿蓝袍'));
      expect(restored.facialPrompt, equals('handsome young cultivator, blue daoist robe'));
      expect(restored.defaultAttireZh, isEmpty);
      expect(restored.defaultAttirePrompt, isEmpty);
      expect(restored.faceAnchorPath, isNull);
      expect(restored.effectiveFacialPrompt, equals('清秀少年，身穿蓝袍'));
    });

    test('CharacterVariation 优先使用 attirePrompt，为空时回退 positiveDelta', () {
      final variationWithAttire = CharacterVariation(
        id: 'v1',
        name: '白袍形态',
        attirePrompt: 'pristine white robes',
        positiveDelta: '白色着装',
      );
      expect(variationWithAttire.effectiveAttirePrompt, equals('pristine white robes'));

      final variationLegacy = CharacterVariation(
        id: 'v2',
        name: '战损形态',
        positiveDelta: 'battle damaged armor',
      );
      expect(variationLegacy.effectiveAttirePrompt, equals('battle damaged armor'));
    });

    test('copyWith 正确变更与清除 faceAnchorPath', () {
      final card = CharacterCard(
        id: 'c1',
        name: '姜七夜',
        faceAnchorPath: 'old_face.png',
        updatedAt: DateTime(2026),
      );

      final updated = card.copyWith(faceAnchorPath: 'new_face.png');
      expect(updated.faceAnchorPath, equals('new_face.png'));

      final cleared = updated.copyWith(clearFaceAnchorPath: true);
      expect(cleared.faceAnchorPath, isNull);
    });
  });

  group('PromptAssembler & CharacterTurnaroundPrompt 两阶段组装与负向色彩对冲', () {
    test('normalizeDeltaWords 正确将中文服饰与颜色关键词转为英文提示词', () {
      final whiteResult = PromptAssembler.normalizeDeltaWords('白色着装');
      expect(whiteResult, contains('pristine white attire'));
      expect(whiteResult, contains('white robes'));

      final whiteRobeResult = PromptAssembler.normalizeDeltaWords('白长袍');
      expect(whiteRobeResult, contains('long flowing white robes'));

      final armorResult = PromptAssembler.normalizeDeltaWords('战铠');
      expect(armorResult, contains('battle armor'));

      final blackResult = PromptAssembler.normalizeDeltaWords('黑衣');
      expect(blackResult, contains('black clothes'));
    });

    test('CharacterTurnaroundPrompt.build 整合容貌与服装组装出场提示词', () {
      final prompt = CharacterTurnaroundPrompt.build(
        'handsome young man, jade skin',
        attirePrompt: 'outer black prison guard robe, black boots',
      );
      expect(prompt, contains('handsome young man'));
      expect(prompt, contains('outer black prison guard robe'));
      expect(prompt, contains('Character turnaround sheet'));
      expect(prompt, contains('分4个区块'));
      expect(prompt, contains('soft diffused studio lighting'));
    });

    test('CharacterTurnaroundPrompt.buildForVariation 实现服饰全量置换且剔除原默认服饰', () {
      final character = CharacterCard(
        id: 'c_test',
        name: '姜七夜',
        facialFeaturesZh: '面如冠玉的俊美青年，剑眉星目',
        facialPrompt: 'handsome young man, jade face, sword eyebrows',
        defaultAttireZh: '内着深青色劲装，外罩玄色巡城司狱卒袍服',
        defaultAttirePrompt: 'inner dark cyan martial outfit, outer black prison guard robe',
        basePromptPositive: 'handsome young man, jade face, inner dark cyan martial outfit, outer black prison guard robe',
        basePromptNegative: 'blurry, ugly',
        updatedAt: DateTime.now(),
      );

      final variation = CharacterVariation(
        id: 'var_white',
        name: '白色着装',
        attirePrompt: 'wearing pristine white robes, flowing silk',
        positiveDelta: '白色着装',
      );

      final prompt = CharacterTurnaroundPrompt.buildForVariation(
        character: character,
        variation: variation,
        inheritBaseFace: true,
      );

      // 验证：包含容貌特征与新形态白色服饰
      expect(prompt, contains('面如冠玉的俊美青年，剑眉星目'));
      expect(prompt, contains('wearing pristine white robes'));
      // 验证：原默认黑袍与深青劲装已被彻底剔除！
      expect(prompt, isNot(contains('outer black prison guard robe')));
      expect(prompt, isNot(contains('dark cyan martial outfit')));
    });

    test('CharacterTurnaroundPrompt.buildNegativeForVariation 自动触发深色服饰对冲', () {
      final character = CharacterCard(
        id: 'c_test',
        name: '姜七夜',
        facialFeaturesZh: '面如冠玉的俊美青年',
        facialPrompt: 'handsome young man',
        defaultAttireZh: '外罩玄色巡城司狱卒袍服',
        defaultAttirePrompt: 'outer black prison guard robe',
        basePromptPositive: 'handsome young man, outer black prison guard robe',
        basePromptNegative: 'ugly, low quality',
        updatedAt: DateTime.now(),
      );

      final variation = CharacterVariation(
        id: 'var_white',
        name: '白色着装',
        attirePrompt: 'pristine white robes',
        positiveDelta: '白色着装',
      );

      final negative = CharacterTurnaroundPrompt.buildNegativeForVariation(
        character: character,
        variation: variation,
      );

      // 验证负向提示词中被自动注入了黑衣与狱卒袍对冲禁令
      expect(negative, contains('黑色服装'));
      expect(negative, contains('深色长袍'));
      expect(negative, contains('玄色袍服'));
    });

    test('CharacterTurnaroundPrompt.buildPortrait 构建独立 1:1 免受服装干扰的面部特写提示词', () {
      final portraitPrompt = CharacterTurnaroundPrompt.buildPortrait(
        'handsome young man, jade face, sword eyebrows, phoenix eyes, clean-shaven',
      );
      expect(portraitPrompt, contains('面部高清特写肖像'));
      expect(portraitPrompt, contains('handsome young man'));
      expect(portraitPrompt, isNot(contains('角色三视图设计图')));
      expect(portraitPrompt, isNot(contains('三个全身视角')));

      final negativePortrait = CharacterTurnaroundPrompt.buildNegativePortrait(
        baseNegative: 'blurry',
      );
      expect(negativePortrait, contains('全身展示'));
      expect(negativePortrait, contains('三视图'));
    });
  });

  group('StudioProjectManager 面部特写锚点裁切与文件落盘契约', () {
    late Directory tempDir;
    final manager = StudioProjectManager.instance;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('face_anchor_test');
      AppPaths.overrideRootForTesting(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('cropAndSaveFaceAnchor: 从三视图中自动提取正面头部保存为 face_anchor.png', () async {
      // 1. 创建剧集与角色
      final series = await manager.createSeries(name: '测试剧集');
      final card = CharacterCard(
        id: 'char_test',
        name: '测试角色',
        facialPrompt: 'handsome boy',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, card);

      // 2. 生成一张 1080x1920 测试三视图底图
      final syntheticImage = img.Image(width: 1080, height: 1920);
      img.fill(syntheticImage, color: img.ColorRgb8(200, 200, 200));
      // 在头部预期区域 (X: 100~300, Y: 100~400) 绘制特定颜色
      img.fillRect(
        syntheticImage,
        x1: 100,
        y1: 100,
        x2: 300,
        y2: 400,
        color: img.ColorRgb8(255, 0, 0),
      );

      final charDir = manager.characterDir(series.id, card.id);
      await charDir.create(recursive: true);
      final turnaroundFile = File('${charDir.path}/turnaround.png');
      await turnaroundFile.writeAsBytes(img.encodePng(syntheticImage));

      // 3. 执行自动裁切
      final faceAnchorFile = await manager.cropAndSaveFaceAnchor(
        seriesId: series.id,
        characterId: card.id,
        turnaroundFile: turnaroundFile,
      );

      expect(faceAnchorFile, isNotNull);
      expect(await faceAnchorFile!.exists(), isTrue);
      expect(faceAnchorFile.path.endsWith('face_anchor.png'), isTrue);

      // 4. 验证裁切后图像维度
      final croppedBytes = await faceAnchorFile.readAsBytes();
      final croppedImg = img.decodeImage(croppedBytes);
      expect(croppedImg, isNotNull);
      expect(croppedImg!.width, greaterThan(300));
      expect(croppedImg.height, greaterThan(400));

      // 5. 验证 CharacterCard 中的 faceAnchorPath 字段已持久化更新
      final updatedCard = manager.readCharacter(series.id, card.id);
      expect(updatedCard, isNotNull);
      expect(updatedCard!.faceAnchorPath, equals('face_anchor.png'));
    });

    test('setFaceAnchor: 正确复制自定义头像为 face_anchor.png 并持久化配置', () async {
      final series = await manager.createSeries(name: '测试剧集2');
      final card = CharacterCard(
        id: 'char_custom',
        name: '定制角色',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, card);

      // 创建一个临时测试头像
      final customAvatar = File('${tempDir.path}/custom_avatar.png');
      final testImg = img.Image(width: 512, height: 512);
      await customAvatar.writeAsBytes(img.encodePng(testImg));

      final result = await manager.setFaceAnchor(
        seriesId: series.id,
        characterId: card.id,
        imageFile: customAvatar,
      );

      expect(result, isNotNull);
      expect(await result!.exists(), isTrue);

      final updated = manager.readCharacter(series.id, card.id);
      expect(updated!.faceAnchorPath, equals('face_anchor.png'));
    });
  });

  group('小说全案解构与提示词翻译双维度提取契约', () {
    late Directory tempDir;
    final manager = StudioProjectManager.instance;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('novel_decoupling_test');
      AppPaths.overrideRootForTesting(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('promptTranslation 验证器解析容貌与服饰独立提示词', () {
      final json = {
        'prompt_positive': '1 young man, handsome face, wearing white robes, 8k',
        'prompt_negative': 'blurry, bad anatomy',
        'facial_features_zh': '面如冠玉的俊美青年，剑眉星目',
        'facial_prompt': 'handsome young man, jade face, sword eyebrows, clean-shaven',
        'default_attire_zh': '素白丝绸长袍',
        'attire_prompt': 'wearing pristine white robes, flowing silk',
      };

      final parsed = AiConstraintEngine.validateSchema(
        StudioAiTask.promptTranslation,
        json,
      );

      expect(parsed, isNotNull);
      expect(parsed!['facial_features_zh'], contains('面如冠玉'));
      expect(parsed['facial_prompt'], contains('handsome young man'));
      expect(parsed['default_attire_zh'], contains('素白丝绸长袍'));
      expect(parsed['attire_prompt'], contains('pristine white robes'));
    });

    test('novelMasterExtraction 验证器与 mergeMasterAssets 双维度持久化角色卡', () async {
      final series = await manager.createSeries(name: '巡城司纪事');

      final masterExtraction = {
        'worldview': '暗流涌动的高武大周王朝',
        'era_genre': 'ancient_costume',
        'style_tokens': 'cinematic film still, dark realism',
        'characters': [
          {
            'name': '姜七夜',
            'description_zh': '面如冠玉的俊美青年，身着玄色狱卒袍',
            'facial_features_zh': '面如冠玉的俊美青年，剑眉入鬓，凤眼薄唇，墨发高束',
            'facial_prompt': 'handsome young man, jade face, sword eyebrows, high ponytail, clean-shaven',
            'default_attire_zh': '内着深青色劲装，外罩玄色巡城司狱卒袍服',
            'attire_prompt': 'inner dark cyan martial outfit, outer black prison guard robe',
            'personality': '玩世不恭，深藏不露',
            'prompt_positive': 'handsome young man, outer black prison guard robe, 8k',
            'prompt_negative': 'blurry',
          },
        ],
        'scenes': [
          {
            'name': '巡城司牢狱',
            'description_zh': '幽暗潮湿的刑房',
            'prompt_en': 'dim prison dungeon',
          },
        ],
      };

      // 验证 Schema 解析
      final parsed = AiConstraintEngine.validateSchema(
        StudioAiTask.novelMasterExtraction,
        masterExtraction,
      );
      expect(parsed, isNotNull);
      final chars = parsed!['characters'] as List;
      expect(chars.first['facial_features_zh'], contains('面如冠玉'));
      expect(chars.first['attire_prompt'], contains('outer black prison guard robe'));

      // 验证 mergeMasterAssets 增量持久化
      await manager.mergeMasterAssets(
        seriesId: series.id,
        masterExtraction: masterExtraction,
      );

      final characters = await manager.listCharacters(series.id);
      expect(characters.length, equals(1));
      final char = characters.first;
      expect(char.name, equals('姜七夜'));
      expect(char.facialFeaturesZh, contains('剑眉入鬓'));
      expect(char.facialPrompt, contains('high ponytail'));
      expect(char.defaultAttireZh, contains('玄色巡城司狱卒袍服'));
      expect(char.defaultAttirePrompt, contains('outer black prison guard robe'));
      expect(char.variations.first.effectiveAttirePrompt, contains('outer black prison guard robe'));
    });
  });

  group('面部特写交互式精确裁切与生命周期管理契约', () {
    late Directory tempDir;
    final manager = StudioProjectManager.instance;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('face_crop_mgmt_test');
      AppPaths.overrideRootForTesting(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('cropFaceAnchorFromRect: 根据视窗选定 Rect 精确截取并保存 face_anchor.png', () async {
      final series = await manager.createSeries(name: '截取测试');
      final card = CharacterCard(
        id: 'char_crop',
        name: '截取测试角色',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, card);

      // 创建测试底图 500x500
      final baseImg = img.Image(width: 500, height: 500);
      img.fill(baseImg, color: img.ColorRgb8(100, 100, 100));
      // 在 100, 100 到 300, 300 区域填充纯绿色
      img.fillRect(baseImg, x1: 100, y1: 100, x2: 300, y2: 300, color: img.ColorRgb8(0, 255, 0));

      final turnaroundFile = File('${tempDir.path}/turnaround.png');
      await turnaroundFile.writeAsBytes(img.encodePng(baseImg));

      // 裁切 100, 100, 200, 200 区域
      final savedFile = await manager.cropFaceAnchorFromRect(
        seriesId: series.id,
        characterId: card.id,
        sourceImageFile: turnaroundFile,
        cropX: 100,
        cropY: 100,
        cropW: 200,
        cropH: 200,
      );

      expect(savedFile, isNotNull);
      expect(await savedFile!.exists(), isTrue);
      expect(savedFile.path.endsWith('face_anchor.png'), isTrue);

      final croppedDecoded = img.decodeImage(await savedFile.readAsBytes());
      expect(croppedDecoded, isNotNull);
      expect(croppedDecoded!.width, equals(200));
      expect(croppedDecoded.height, equals(200));

      final updated = manager.readCharacter(series.id, card.id);
      expect(updated, isNotNull);
      expect(updated!.faceAnchorPath, equals('face_anchor.png'));
    });

    test('deleteFaceAnchor: 物理删除 face_anchor.png 并重置 CharacterCard faceAnchorPath', () async {
      final series = await manager.createSeries(name: '删除测试');
      final card = CharacterCard(
        id: 'char_del',
        name: '删除测试角色',
        faceAnchorPath: 'face_anchor.png',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, card);

      final charDir = manager.characterDir(series.id, card.id);
      await charDir.create(recursive: true);
      final faceFile = File('${charDir.path}/face_anchor.png');
      await faceFile.writeAsString('fake image bytes');
      expect(await faceFile.exists(), isTrue);

      final deleted = await manager.deleteFaceAnchor(
        seriesId: series.id,
        characterId: card.id,
      );

      expect(deleted, isTrue);
      expect(await faceFile.exists(), isFalse);

      final persisted = manager.readCharacter(series.id, card.id);
      expect(persisted!.faceAnchorPath, isNull);
    });
  });

  group('Agnes 图像生成协议与参考图 Base64 Data URI 装配契约', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('agnes_protocol_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('resolveAgnesSizeAndRatio: 比例规整映射到 Agnes 官方合法参数', () {
      expect(SystemAiImageAdapter.resolveAgnesSizeAndRatio(1024, 1024), equals(('1K', '1:1')));
      expect(SystemAiImageAdapter.resolveAgnesSizeAndRatio(1080, 1920), equals(('2K', '9:16')));
      expect(SystemAiImageAdapter.resolveAgnesSizeAndRatio(1920, 1080), equals(('2K', '16:9')));
      expect(SystemAiImageAdapter.resolveAgnesSizeAndRatio(768, 1024), equals(('2K', '3:4')));
      expect(SystemAiImageAdapter.resolveAgnesSizeAndRatio(1024, 768), equals(('2K', '4:3')));
      expect(SystemAiImageAdapter.resolveAgnesSizeAndRatio(2560, 1080), equals(('2K', '21:9')));
    });

    test('SystemAiImageAdapter: 在 Agnes 协议下将 referenceImages 编码为 Data URI Base64 并传递 extra_body.image', () async {
      // 1. 生成一张测试参考图
      final refFile = File('${tempDir.path}/face_anchor.png');
      final testImg = img.Image(width: 64, height: 64);
      img.fill(testImg, color: img.ColorRgb8(255, 128, 0));
      await refFile.writeAsBytes(img.encodePng(testImg));

      final outputFile = File('${tempDir.path}/output.png');

      Map<String, dynamic>? interceptedPayload;

      final adapter = SystemAiImageAdapter(
        baseUrl: 'https://api.agnes-ai.cn',
        model: 'agnes-image-25-flash',
        apiKey: 'test-agnes-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            interceptedPayload = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'data': [
                  {'url': 'https://mock.agnes-ai.cn/generated.png'}
                ]
              }),
              200,
            );
          } else if (req.method == 'GET') {
            final mockResult = img.Image(width: 256, height: 256);
            img.fill(mockResult, color: img.ColorRgb8(10, 20, 30));
            return http.Response.bytes(img.encodePng(mockResult), 200);
          }
          return http.Response('Not Found', 404);
        },
      );

      final resultFile = await adapter.generate(
        ImageGenRequest(
          prompt: 'handsome boy with pristine white robe',
          shotNumber: 1,
          width: 1080,
          height: 1920,
          outputFile: outputFile,
          referenceImages: [refFile.path],
        ),
      );

      expect(await resultFile.exists(), isTrue);
      expect(interceptedPayload, isNotNull);
      expect(interceptedPayload!['model'], equals('agnes-image-25-flash'));
      expect(interceptedPayload!['size'], equals('2K'));
      expect(interceptedPayload!['ratio'], equals('9:16'));

      final extraBody = interceptedPayload!['extra_body'] as Map<String, dynamic>?;
      expect(extraBody, isNotNull);
      expect(extraBody!['response_format'], equals('url'));

      final images = extraBody['image'] as List<dynamic>?;
      expect(images, isNotNull);
      expect(images!.length, equals(1));
      expect(images.first.toString().startsWith('data:image/png;base64,'), isTrue);

      // 解码验证 Base64 还原后与原始参考图大小一致
      final base64Str = images.first.toString().substring('data:image/png;base64,'.length);
      final decodedBytes = base64Decode(base64Str);
      final decodedRef = img.decodeImage(decodedBytes);
      expect(decodedRef, isNotNull);
      expect(decodedRef!.width, equals(64));
      expect(decodedRef.height, equals(64));
    });
  });

  group('三视图纯白背景加固与风格词清洗契约', () {
    test('cleanTurnaroundStyleTokens 过滤场景光影与环境词，保留纯艺术画风词', () {
      const rawStyle =
          'cinematic film still, dark realism, dramatic lighting, volumetric lighting, interior room, 3D render, cel-shaded anime, detailed background';

      final cleaned = CharacterTurnaroundPrompt.cleanTurnaroundStyleTokens(rawStyle);

      // 验证场景环境与光影词已被清洗剔除
      expect(cleaned, isNot(contains('cinematic film still')));
      expect(cleaned, isNot(contains('dark realism')));
      expect(cleaned, isNot(contains('dramatic lighting')));
      expect(cleaned, isNot(contains('volumetric lighting')));
      expect(cleaned, isNot(contains('interior room')));
      expect(cleaned, isNot(contains('detailed background')));

      // 验证纯画风词被完整保留
      expect(cleaned, contains('3D render'));
      expect(cleaned, contains('cel-shaded anime'));
    });

    test('CharacterTurnaroundPrompt.build 前置纯白底声明并剔除诱导词', () {
      final prompt = CharacterTurnaroundPrompt.build(
        'handsome young man, inner dark cyan martial outfit',
        styleTokens: 'cinematic lighting, dark realism, anime style',
      );

      // 1. 验证提示词开头首置英文资产图与纯白底
      expect(
        prompt.startsWith(
          'Character turnaround sheet，角色三视图设计图，角色设定资产参考图，16:9横版，纯白无缝背景，分4个区块',
        ),
        isTrue,
      );

      // 2. 验证正交平视与 PBR 漫射柔光注入
      expect(prompt, contains('正交视图orthographic'));
      expect(prompt, contains('soft diffused studio lighting'));
      expect(prompt, contains('matte surface'));
      expect(prompt, isNot(contains('consistent lighting and background')));

      // 3. 验证 styleTokens 中的场景光影词被清洗过滤，画风词被保留
      expect(prompt, isNot(contains('cinematic lighting')));
      expect(prompt, isNot(contains('dark realism')));
      expect(prompt, contains('anime style'));

      // 4. 验证负向提示词中包含强力背景与环境抑制词
      final negative = CharacterTurnaroundPrompt.buildNegative();
      expect(negative, contains('复杂背景'));
      expect(negative, contains('自然风景'));
      expect(negative, contains('室内外环境'));
      expect(negative, contains('暗色背景'));
      expect(negative, contains('阴影'));
    });
  });

  group('三视图 16:9 横屏画幅与原生超清面部裁切契约', () {
    late Directory tempDir;
    final manager = StudioProjectManager.instance;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('face_anchor_landscape_test');
      AppPaths.overrideRootForTesting(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('cropAndSaveFaceAnchor: 针对 16:9 横屏 2K 三视图自适应裁切左侧正视图面部并保留高清分辨率', () async {
      final series = await manager.createSeries(name: '测试横屏剧集');
      final card = CharacterCard(
        id: 'char_landscape',
        name: '横屏测试角色',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, card);

      // 1. 生成一张 2624x1472 (Agnes 2K 16:9) 测试底图
      final syntheticImage = img.Image(width: 2624, height: 1472);
      img.fill(syntheticImage, color: img.ColorRgb8(240, 240, 240));

      // 模拟正面视图头部位于左侧 1/3 (X: 130~700, Y: 70~500)
      img.fillRect(
        syntheticImage,
        x1: 130,
        y1: 70,
        x2: 700,
        y2: 500,
        color: img.ColorRgb8(220, 150, 100),
      );

      final charDir = manager.characterDir(series.id, card.id);
      await charDir.create(recursive: true);
      final turnaroundFile = File('${charDir.path}/turnaround.png');
      await turnaroundFile.writeAsBytes(img.encodePng(syntheticImage));

      // 2. 执行自动面部特写裁切
      final faceAnchorFile = await manager.cropAndSaveFaceAnchor(
        seriesId: series.id,
        characterId: card.id,
        turnaroundFile: turnaroundFile,
      );

      expect(faceAnchorFile, isNotNull);
      expect(await faceAnchorFile!.exists(), isTrue);

      // 3. 验证保留了完整原生高像素，绝无人为 512x512 降采样
      final croppedBytes = await faceAnchorFile.readAsBytes();
      final croppedImg = img.decodeImage(croppedBytes);
      expect(croppedImg, isNotNull);
      expect(croppedImg!.width, greaterThan(500));
      expect(croppedImg.height, greaterThan(450));
      // 验证宽度与高度保持原生 2624x1472 比例计算出的未缩放选区
      expect(croppedImg.width, equals((2624 * 0.23).round()));
      expect(croppedImg.height, equals((1472 * 0.35).round()));
    });

    test('resolveAgnesSizeAndRatio: 1920x1080 映射为 2K 16:9 舒展构图', () {
      final (size, ratio) = SystemAiImageAdapter.resolveAgnesSizeAndRatio(1920, 1080);
      expect(size, equals('2K'));
      expect(ratio, equals('16:9'));
    });

    test('原生高分辨率裁剪契约: 大于 512 的选区保留 100% 原生尺寸，拒绝下采样', () {
      final highResSource = img.Image(width: 2624, height: 1472);
      img.fill(highResSource, color: img.ColorRgb8(128, 128, 128));

      // 截取 800x800 正方形区域
      final cropped = img.copyCrop(
        highResSource,
        x: 100,
        y: 100,
        width: 800,
        height: 800,
      );

      // 验证原生无损保留原则：width 与 height 严格等于 800，不降采样为 512
      expect(cropped.width, equals(800));
      expect(cropped.height, equals(800));
      expect(cropped.width, isNot(equals(512)));
    });
  });
}

