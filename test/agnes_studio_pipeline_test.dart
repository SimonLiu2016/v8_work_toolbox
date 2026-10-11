import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/image_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';

void main() {
  setUpAll(() {
    AppPaths.overrideRootForTesting(
      Directory.systemTemp.createTempSync('agnes_studio_test'),
    );
  });

  group('Agnes 视觉模型与分镜规范测试', () {
    test('StudioShotSize.full 解析与中文全景兼容', () {
      expect(StudioShotSize.fromId('full'), StudioShotSize.full);
      expect(StudioShotSize.fromId('全景'), StudioShotSize.full);
      expect(StudioShotSize.fromId('wide'), StudioShotSize.full);
      expect(StudioShotSize.full.label, '全景');
    });

    test('StudioShot 台词预估秒数提取与解析', () {
      const shotWithSec = StudioShot(
        number: 1,
        durationSec: 4.0,
        dialogue: '（压低声音）快走，后面有人！（预估2.5秒）',
      );
      expect(shotWithSec.dialogueEstimatedSec, 2.5);

      const shotWithoutSec = StudioShot(
        number: 2,
        durationSec: 4.0,
        dialogue: '这里没有标注秒数',
      );
      // 8 字 / 4.0 = 2.0 秒
      expect(shotWithoutSec.dialogueEstimatedSec, 2.0);

    });

    test('SystemAiImageAdapter 生成 Agnes 图像精简 Payload 测试', () async {
      http.Request? capturedPostReq;
      final adapter = SystemAiImageAdapter(
        baseUrl: 'http://119.29.249.154:3356',
        model: 'agnes-image-2.5-flash',
        apiKey: 'sk-mock-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            capturedPostReq = req;
            return http.Response(
              '{"data":[{"url":"https://mock.cdn/agnes_img.png"}]}',
              200,
            );
          }
          if (req.method == 'GET') {
            return http.Response.bytes(List.filled(200, 1), 200);
          }
          return http.Response('{}', 404);
        },
      );

      final tempOut = File('${Directory.systemTemp.path}/test_agnes_img_${DateTime.now().millisecondsSinceEpoch}.png');
      await adapter.generate(ImageGenRequest(
        prompt: '向日葵',
        shotNumber: 1,
        outputFile: tempOut,
      ));

      expect(capturedPostReq, isNotNull);
      expect(capturedPostReq!.url.path, '/v1/images/generations');
      final body = jsonDecode(capturedPostReq!.body) as Map<String, dynamic>;
      expect(body['model'], 'agnes-image-2.5-flash');
      expect(body['prompt'], '向日葵');
      // 验证未传递多余的容易引起中转站报错的顶层字段
      expect(body.containsKey('extra_body'), isFalse);
      expect(body.containsKey('size'), isFalse);
      expect(tempOut.existsSync(), isTrue);
      tempOut.deleteSync();
    });

    test('downloadImageFileWithRetry 支持在网络连接重置时自动重试', () async {
      var attemptCount = 0;
      final tempOut = File('${Directory.systemTemp.path}/test_retry_img_${DateTime.now().millisecondsSinceEpoch}.png');
      
      final res = await downloadImageFileWithRetry(
        url: 'https://mock.cdn/transient_fail.png',
        outputFile: tempOut,
        httpFn: (req) async {
          attemptCount++;
          if (attemptCount < 2) {
            throw const SocketException('Connection reset by peer');
          }
          return http.Response.bytes(List.filled(256, 1), 200);
        },
      );

      expect(attemptCount, 2);
      expect(res.existsSync(), isTrue);
      expect(res.lengthSync(), 256);
      tempOut.deleteSync();
    });

    test('AgnesVideoAdapter 生成请求体与轮询状态测试', () async {
      var callCount = 0;
      final adapter = AgnesVideoAdapter(
        apiKey: 'test-key',
        baseUrl: 'http://119.29.249.154:3356',
        model: 'agnes-video-2.5-flash',
        httpFn: (req) async {
          callCount++;
          if (req.method == 'POST') {
            final body = jsonDecode((req as http.Request).body) as Map<String, dynamic>;
            expect(body.containsKey('size'), isFalse, reason: 'Agnes 视频请求不得包含非法 size 参数');
            expect(body['mode'], 'keyframe');
            expect(body['aspect_ratio'], '9:16');
            expect(body['seconds'], '5');
            expect(body['first_frame'], startsWith('data:image/png;base64,'));
            return http.Response('{"id": "task_agnes_999"}', 200);
          }
          if (req.method == 'GET' && req.url.path.contains('/v1/videos/task_agnes_999')) {
            return http.Response('{"status": "completed", "url": "https://mock.cdn/agnes.mp4"}', 200);
          }
          if (req.url.path.endsWith('.mp4')) {
            return http.Response.bytes([0, 0, 0, 24, 102, 116, 121, 112], 200);
          }
          return http.Response('{}', 404);
        },
      );

      final tempImg = File('${Directory.systemTemp.path}/test_frame_${DateTime.now().millisecondsSinceEpoch}.png');
      tempImg.writeAsBytesSync([137, 80, 78, 71]);
      final tempMp4 = File('${Directory.systemTemp.path}/test_agnes_out_${DateTime.now().millisecondsSinceEpoch}.mp4');

      await adapter.generateVideo(VideoGenRequest(
        inputImage: tempImg,
        cameraMove: 'slow push-in',
        durationSec: 5.0,
        shotNumber: 1,
        outputFile: tempMp4,
      ));

      expect(callCount, greaterThanOrEqualTo(2));
      expect(tempMp4.existsSync(), isTrue);
      tempImg.deleteSync();
      tempMp4.deleteSync();
    });


    test('StudioProjectManager.importNovelProject 原子化入库两阶段数据', () async {
      final manager = StudioProjectManager.instance;
      final series = await manager.createSeries(name: '测试原著短剧');

      final masterData = {
        'worldview': '架空民国异能都市，风起云涌。',
        'style_tokens': 'cinematic 90s hong kong movie tone, 8k',
        'characters': [
          {
            'name': '陆寒川',
            'description_zh': '身穿深黑风衣，眼神冷冽。',
            'base_prompt_positive': '1man, black trench coat, sharp eyes',
            'base_prompt_negative': 'low quality, cartoon',
          },
        ],
        'scenes': [
          {
            'name': '雨夜废弃工厂',
            'description_zh': '锈迹斑斑的钢铁管道，地面有大量雨水倒影。',
            'prompt_en': 'abandoned factory, rusty steel pipes, wet floor reflections',
          },
        ],
      };

      final segmentData = {
        'total_recommended_episodes': 2,
        'episodes': [
          {
            'index': 1,
            'title': '第1集：潜行与截击',
            'synopsis': '暴雨之夜，陆寒川潜入废弃工厂调查神秘图纸。',
            'summary': '陆寒川成功发现图纸，但遭遇神秘黑衣人包围。',
            'hook': '一声枪响划破黑夜，子弹直逼眉心！',
          },
          {
            'index': 2,
            'title': '第2集：反杀脱困',
            'synopsis': '陆寒川侧身闪避，借助烟雾弹展开反击。',
            'summary': '击退杀手并获取关键信件。',
            'hook': '信封上的印章竟属于他最信任的人。',
          },
        ],
      };

      final updated = await manager.importNovelProject(
        seriesId: series.id,
        masterExtraction: masterData,
        episodeSegmentation: segmentData,
      );

      expect(updated.worldview, '架空民国异能都市，风起云涌。');
      expect(updated.styleTokens, 'cinematic 90s hong kong movie tone, 8k');
      expect(updated.memories.length, 2);
      expect(updated.memories.first.hook, '一声枪响划破黑夜，子弹直逼眉心！');

      final chars = await manager.listCharacters(series.id);
      expect(chars.length, 1);
      expect(chars.first.name, '陆寒川');

      final scenes = await manager.listScenes(series.id);
      expect(scenes.length, 1);
      expect(scenes.first.name, '雨夜废弃工厂');

      final episodes = await manager.listEpisodes(series.id);
      expect(episodes.length, 2);
      expect(episodes.first.title, '第1集：潜行与截击');
    });

    test('PromptAssembler 动作描述融入与空镜头人物抑制测试', () {
      // 1. 空镜头测试：无角色时正向有动作/场景，负向注入人脸抑制
      final now = DateTime.now();
      final emptyShotPrompt = PromptAssembler.buildShotPrompt(PromptParts(
        shotSize: 'extreme long shot',
        mood: 'depressing',
        scene: SceneCard(
          id: 's1',
          name: '暴雨街道',
          promptEn: 'midnight city street, neon reflections on wet asphalt',
          updatedAt: now,
        ),
        actionZh: '暴雨倾盆的午夜街道，霓虹在雨幕中晕开',
      ));

      expect(emptyShotPrompt.positive.contains('midnight city street'), isTrue);
      expect(emptyShotPrompt.positive.contains('暴雨倾盆的午夜街道'), isTrue);
      expect(emptyShotPrompt.negative.contains('person, human, face'), isTrue);

      // 2. 角色镜头测试：有角色时不注入人物抑制，保留角色基础设定
      final charShotPrompt = PromptAssembler.buildShotPrompt(PromptParts(
        shotSize: 'medium close-up',
        character: CharacterCard(
          id: 'c1',
          name: '王瑞',
          basePromptPositive: 'detective in dark trench coat, short black hair',
          updatedAt: DateTime.now(),
        ),
        actionZh: '王瑞撑着黑伞驻足街边，缓缓抬头',
      ));

      expect(charShotPrompt.positive.contains('detective in dark trench coat'), isTrue);
      expect(charShotPrompt.positive.contains('王瑞撑着黑伞驻足街边'), isTrue);
      expect(charShotPrompt.negative.contains('person, human, face'), isFalse);
    });
  });
}

