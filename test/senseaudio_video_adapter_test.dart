import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('senseaudio_test');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AiProviderConfig 与 AiConfigStore video 槽位测试', () {
    test('AiProviderConfig 扩展 videoModels 支持序列化与反序列化', () {
      const config = AiProviderConfig(
        id: 'senseaudio_test',
        name: 'SenseAudio 官方视频',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.senseaudio.cn/v1',
        keychainKeyId: 'key_senseaudio',
        videoModels: ['doubao-seedance-2-0-260128', 'doubao-seedance-1-5-pro'],
      );

      final json = config.toJson();
      expect(json['models']['video'], contains('doubao-seedance-2-0-260128'));

      final restored = AiProviderConfig.fromJson(json);
      expect(restored.videoModels, equals(['doubao-seedance-2-0-260128', 'doubao-seedance-1-5-pro']));
    });

    test('AiConfigStore 初始化时自动注册 video 槽位', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      expect(store.slotBindings.containsKey('video'), isTrue);

      await store.addSlotCandidate('video', 'prov_senseaudio', 'doubao-seedance-2-0-260128');
      expect(store.slotBindings['video'], isNotEmpty);
      expect(store.slotBindings['video']!.first.providerId, equals('prov_senseaudio'));
      expect(store.slotBindings['video']!.first.model, equals('doubao-seedance-2-0-260128'));
    });
  });

  group('SenseAudioVideoAdapter 协议契约与生成轮询测试', () {
    late File dummyInputImage;
    late File dummyOutputFile;

    setUp(() {
      dummyInputImage = File(p.join(tempDir.path, 'frame_001.png'))..createSync(recursive: true);
      dummyInputImage.writeAsBytesSync(utf8.encode('fake-png-bytes'));
      dummyOutputFile = File(p.join(tempDir.path, 'shot_001.mp4'));
    });

    test('未配置 API Key 时抛出包含可操作指引的 StateError', () async {
      final adapter = SenseAudioVideoAdapter(
        baseUrl: 'https://api.senseaudio.cn/v1',
        apiKey: '',
      );

      await expectLater(
        adapter.generateVideo(VideoGenRequest(
          inputImage: dummyInputImage,
          cameraMove: 'slow push-in',
          durationSec: 5,
          shotNumber: 1,
          outputFile: dummyOutputFile,
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('API Key 未配置'),
        )),
      );
    });

    test('正常流程：发送规范 POST /v1/video/create 并轮询 GET /v1/video/status 直至下载', () async {
      int requestCount = 0;
      final adapter = SenseAudioVideoAdapter(
        baseUrl: 'https://api.senseaudio.cn/v1',
        model: 'doubao-seedance-2-0-260128',
        apiKey: 'sk-test-token',
        client: http.Client(),
        httpFn: (req) async {
          requestCount++;
          if (req.method == 'POST') {
            expect(req.url.path, endsWith('/video/create'));
            expect(req.headers['Authorization'], equals('Bearer sk-test-token'));
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['model'], equals('doubao-seedance-2-0-260128'));
            expect(body['ratio'], equals('9:16'));
            expect(body['duration'], equals(5));

            final content = body['content'] as List;
            expect(content.length, equals(2));
            expect(content[0]['type'], equals('text'));
            expect(content[0]['text'], equals('slow push-in'));
            expect(content[1]['type'], equals('image'));
            expect(content[1]['role'], equals('first_frame'));
            expect(content[1]['url'], startsWith('data:image/png;base64,'));

            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'id': 'task_123456'},
              }),
              200,
            );
          } else if (req.method == 'GET' && req.url.path.contains('/video/status')) {
            expect(req.url.queryParameters['id'], equals('task_123456'));
            if (requestCount == 2) {
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'status': 'processing',
                    'progress': 45,
                  },
                }),
                200,
              );
            } else {
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'status': 'completed',
                    'progress': 100,
                    'video_url': 'https://download.senseaudio.cn/test.mp4',
                  },
                }),
                200,
              );
            }
          } else if (req.method == 'GET' && req.url.host.contains('download.senseaudio.cn')) {
            return http.Response.bytes(utf8.encode('fake-video-mp4-data'), 200);
          }
          return http.Response('not found', 404);
        },
      );

      final doubleProgressList = <double>[];
      final res = await adapter.generateVideo(
        VideoGenRequest(
          inputImage: dummyInputImage,
          cameraMove: 'slow push-in',
          durationSec: 5,
          shotNumber: 1,
          outputFile: dummyOutputFile,
        ),
        onProgress: (p) => doubleProgressList.add(p),
      );

      expect(res.existsSync(), isTrue);
      expect(res.readAsStringSync(), equals('fake-video-mp4-data'));
      expect(doubleProgressList, contains(0.45));
      expect(doubleProgressList.last, equals(1.0));
    });

    test('服务端生成失败时优雅抛出包含 message 的异常', () async {
      final adapter = SenseAudioVideoAdapter(
        baseUrl: 'https://api.senseaudio.cn/v1',
        apiKey: 'sk-test-token',
        httpFn: (req) async {
          if (req.method == 'POST') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'id': 'task_fail_999'},
              }),
              200,
            );
          } else {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'status': 'failed',
                  'error': '敏感镜头检测阻断',
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
        },
      );

      await expectLater(
        adapter.generateVideo(VideoGenRequest(
          inputImage: dummyInputImage,
          cameraMove: 'pan right',
          durationSec: 4,
          shotNumber: 2,
          outputFile: dummyOutputFile,
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('敏感镜头检测阻断'),
        )),
      );
    });
  });

  group('AgnesVideoAdapter 协议契约、图像压缩与 429 退避重试测试', () {
    late File dummyInputImage;
    late File dummyOutputFile;

    setUp(() {
      dummyInputImage = File(p.join(tempDir.path, 'agnes_frame_001.png'))..createSync(recursive: true);
      // 创建一张包含合法 PNG 头的微型图片
      dummyInputImage.writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ));
      dummyOutputFile = File(p.join(tempDir.path, 'agnes_shot_001.mp4'));
    });

    test('遇到 429 上游负载饱和时自动重试并最终成功', () async {
      var postAttempts = 0;
      Map<String, dynamic>? capturedPayload;

      final adapter = AgnesVideoAdapter(
        baseUrl: 'http://119.29.249.154:3356/v1',
        model: 'agnes-video-2.5-flash',
        apiKey: 'sk-test-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            postAttempts++;
            capturedPayload = jsonDecode(req.body) as Map<String, dynamic>;
            if (postAttempts == 1) {
              return http.Response(
                jsonEncode({
                  'code': 'fail_to_fetch_task',
                  'message': '当前分组上游负载已饱和，请稍后再试',
                  'data': null,
                }),
                429,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            return http.Response(
              jsonEncode({
                'data': {'id': 'task_agnes_ok_1'},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          } else {
            // GET /v1/videos/task_agnes_ok_1 or download
            if (req.url.path.endsWith('.mp4')) {
              return http.Response('video-bytes-success', 200);
            }
            return http.Response(
              jsonEncode({
                'status': 'completed',
                'video_url': 'http://119.29.249.154:3356/output.mp4',
              }),
              200,
            );
          }
        },
      );

      final result = await adapter.generateVideo(VideoGenRequest(
        inputImage: dummyInputImage,
        cameraMove: 'slow pull-back',
        durationSec: 5,
        shotNumber: 1,
        outputFile: dummyOutputFile,
      ));

      expect(postAttempts, equals(2));
      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['mode'], equals('keyframe'));
      expect(capturedPayload!['first_frame'], startsWith('data:image/'));
      expect(capturedPayload!.containsKey('image'), isFalse);
      expect(capturedPayload!.containsKey('image_url'), isFalse);
      expect(capturedPayload!.containsKey('size'), isFalse);
      expect(result.existsSync(), isTrue);
      expect(result.readAsStringSync(), equals('video-bytes-success'));
    });

    test('遇到网关坏节点丢弃参数报 400 时自动轮询换路重试并成功', () async {
      var postAttempts = 0;

      final adapter = AgnesVideoAdapter(
        baseUrl: 'http://119.29.249.154:3356/v1',
        model: 'agnes-video-2.5-flash',
        apiKey: 'sk-test-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            postAttempts++;
            if (postAttempts == 1) {
              return http.Response(
                jsonEncode({
                  'code': 'invalid_request',
                  'message': 'keyframe 模式需要 first_frame 或 last_frame (request id: 20261009115315436052795LM9DdUdj)',
                  'data': {'param': 'first_frame'},
                }),
                400,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            return http.Response(
              jsonEncode({
                'data': {'id': 'task_recovered_ok_2'},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          } else {
            if (req.url.path.endsWith('.mp4')) {
              return http.Response('video-retry-recovered-mp4', 200);
            }
            return http.Response(
              jsonEncode({
                'status': 'completed',
                'video_url': 'http://119.29.249.154:3356/output_rec.mp4',
              }),
              200,
            );
          }
        },
      );

      final result = await adapter.generateVideo(VideoGenRequest(
        inputImage: dummyInputImage,
        cameraMove: 'slow zoom',
        durationSec: 5,
        shotNumber: 1,
        outputFile: dummyOutputFile,
      ));

      expect(postAttempts, equals(2));
      expect(result.existsSync(), isTrue);
      expect(result.readAsStringSync(), equals('video-retry-recovered-mp4'));
    });

    test('分镜图片不存在时自适应回退到 mode: text', () async {
      final nonExistentImage = File(p.join(tempDir.path, 'no_such_file.png'));
      Map<String, dynamic>? capturedPayload;

      final adapter = AgnesVideoAdapter(
        baseUrl: 'http://119.29.249.154:3356/v1',
        model: 'agnes-video-2.5-flash',
        apiKey: 'sk-test-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            capturedPayload = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'data': {'id': 'task_text_mode'},
              }),
              200,
            );
          } else {
            if (req.url.path.endsWith('.mp4')) {
              return http.Response('video-text-success', 200);
            }
            return http.Response(
              jsonEncode({
                'status': 'completed',
                'video_url': 'http://119.29.249.154:3356/output_text.mp4',
              }),
              200,
            );
          }
        },
      );

      final result = await adapter.generateVideo(VideoGenRequest(
        inputImage: nonExistentImage,
        cameraMove: 'cinematic pan',
        durationSec: 5,
        shotNumber: 2,
        outputFile: dummyOutputFile,
      ));

      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['mode'], equals('text'));
      expect(capturedPayload!.containsKey('first_frame'), isFalse);
      expect(result.readAsStringSync(), equals('video-text-success'));
    });
  });
}
