import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/services/media_capability.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/image_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';

/// Engine Adapter 层的契约测试：HTTP 错误处理、工厂选择、可灵轮询逻辑。
///
/// 全部走注入的假 http 后端，不起真实网络。可灵的创建→轮询→下载三段落用
/// 一个按请求次数切换响应的假后端模拟。
void main() {
  // KeychainService 的读写落在 AppPaths 下，未初始化时它抛的 StateError
  // 会盖过被测代码自己的错误，让断言读到错误来源。
  setUpAll(() {
    AppPaths.overrideRootForTesting(
      Directory.systemTemp.createTempSync('studio_adapter_test'),
    );
  });

  group('硅基流动适配器 HTTP 细节', () {
    test('未配置 Key 时不发请求，直接抛可操作的 StateError', () async {
      var called = 0;
      final adapter = SiliconFlowImageAdapter(
        httpFn: (req) async {
          called++;
          return http.Response('{}', 200);
        },
      );
      await expectLater(
        adapter.generate(ImageGenRequest(
          prompt: 'test',
          shotNumber: 1,
          outputFile: File('/tmp/should_not_exist.png'),
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('API Key 未配置'),
        )),
      );
      expect(called, 0, reason: '没有 Key 时不该白发一次请求');
    });

    test('非 200 响应抛 StateError 且带上服务端 message', () async {
      var called = 0;
      // 这台机器可能真的配过 Key——显式写一个，让请求真发到假后端。
      await KeychainService.instance.writeSecret(
        SiliconFlowImageAdapter.keychainKeyId,
        'sk-test-key',
      );
      addTearDown(() => KeychainService.instance.deleteSecret(
        SiliconFlowImageAdapter.keychainKeyId,
      ));
      final adapter = SiliconFlowImageAdapter(
        httpFn: (req) async {
          called++;
          expect(req.url.toString(), SiliconFlowImageAdapter.endpoint);
          expect(req.headers['Authorization'], startsWith('Bearer '));
          final payload = jsonDecode(req.body) as Map;
          expect(payload['model'], SiliconFlowImageAdapter.modelId);
          expect(payload['image_size'], '1080x1920');
          return http.Response(
            '{"message": "insufficient quota"}',
            429,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      await expectLater(
        adapter.generate(ImageGenRequest(
          prompt: 'test',
          shotNumber: 1,
          outputFile: File('/tmp/should_not_exist.png'),
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('429'), contains('insufficient quota')),
        )),
      );
      expect(called, 1);
    });

    test('返回体缺少 images 字段时抛 FormatException', () async {
      await KeychainService.instance.writeSecret(
        SiliconFlowImageAdapter.keychainKeyId,
        'sk-test-key',
      );
      addTearDown(() => KeychainService.instance.deleteSecret(
        SiliconFlowImageAdapter.keychainKeyId,
      ));
      final adapter = SiliconFlowImageAdapter(
        httpFn: (req) async => http.Response(
          '{"data": []}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        adapter.generate(ImageGenRequest(
          prompt: 'x',
          shotNumber: 1,
          outputFile: File('/tmp/nope.png'),
        )),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('可灵适配器 任务生命周期', () {
    setUp(() async {
      await KeychainService.instance.writeSecret(
        KlingVideoAdapter.keychainKeyId,
        'ak-test-key',
      );
    });
    tearDown(() async {
      await KeychainService.instance.deleteSecret(
        KlingVideoAdapter.keychainKeyId,
      );
    });

    test('创建 → 轮询 processing → 成功下载', () async {
      var phase = 0;
      final adapter = KlingVideoAdapter(
        httpFn: (req) async {
          phase++;
          if (req.method == 'POST') {
            return http.Response(
              jsonEncode({'data': {'task_id': 'task-123'}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          // GET：第一次 processing，第二次 succeeded
          if (phase == 2) {
            return http.Response(
              jsonEncode({'data': {'task_status': 'processing'}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'data': {
                'task_status': 'succeeded',
                'task_result': {
                  'videos': [
                    {'url': 'https://cdn.example.com/video.mp4'},
                  ],
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      // 轮询间隔是 5 秒（spec 级的实测值），两次轮询至少 10 秒。
      final dir = Directory.systemTemp.createTempSync('kling_test');
      final srcVideo = File(p.join(dir.path, 'fake.mp4'));
      srcVideo.writeAsBytesSync(List<int>.filled(4096, 7));

      final out = File(p.join(dir.path, 'out.mp4'));
      // 下载走真实 client，URL 不可达——所以断言的是「轮询走到了 succeeded
      // 并发起下载」（错误里带着那个 URL），而不是假装下载成功。
      await expectLater(
        adapter.generateVideo(VideoGenRequest(
          inputImage: srcVideo,
          cameraMove: 'orbit',
          durationSec: 5,
          shotNumber: 1,
          outputFile: out,
        )),
        throwsA(anything), // 具体类型不重要，下面按消息断言
      ).catchError((e) async {
        expect(e.toString(), anyOf(contains('cdn.example.com'), contains('StateError')));
        return null;
      });
      expect(phase, greaterThanOrEqualTo(3),
             reason: '应当完成创建 + 至少一次轮询 + 下载尝试');
      dir.deleteSync(recursive: true);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('任务失败时抛带服务端原因的 StateError', () async {
      final adapter = KlingVideoAdapter(
        httpFn: (req) async {
          if (req.method == 'POST') {
            return http.Response(
              jsonEncode({'data': {'task_id': 't1'}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'data': {'task_status': 'failed', 'message': 'content policy'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );
      await expectLater(
        adapter.generateVideo(VideoGenRequest(
          inputImage: File('/dev/null'),
          cameraMove: '',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File('/tmp/kling_fail.mp4'),
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('content policy'),
        )),
      );
    });

    test('取消后停止轮询（不再等待云端）', () async {
      var polls = 0;
      // 先声明再构造：httpFn 闭包里要引用它来触发取消。
      late final KlingVideoAdapter adapter;
      adapter = KlingVideoAdapter(
        httpFn: (req) async {
          if (req.method == 'POST') {
            return http.Response(
              jsonEncode({'data': {'task_id': 't2'}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          polls++;
          // 第一次轮询后就取消：下一轮循环开头应检查 _cancelled 并抛出。
          adapter.cancelCurrent();
          return http.Response(
            jsonEncode({'data': {'task_status': 'processing'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      await expectLater(
        adapter.generateVideo(VideoGenRequest(
          inputImage: File('/dev/null'),
          cameraMove: '',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File('/tmp/kling_cancel.mp4'),
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('取消'),
        )),
      );
      // 关键断言：取消后不再继续轮询（否则会白等到 5 分钟超时）。
      expect(polls, 1, reason: '取消后应立刻停止轮询');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('适配器工厂', () {
    test('未配置 Key 时图像工厂回落到本地占位实现', () async {
      final adapter = await ImageGenAdapterFactory.create();
      expect(adapter, isA<LocalStubImageAdapter>(),
             reason: '零 Key 也必须能出图，spec 要求不出现功能不可用提示');
    });

    test('显式偏好 local-stub 时返回本地实现', () async {
      final adapter = await ImageGenAdapterFactory.create(
        preferredEngineId: 'local-stub',
      );
      expect(adapter, isA<LocalStubImageAdapter>());
    });

    test('narration / anime 类型默认走本地 Ken Burns，不选云端 I2V', () async {
      for (final type in ['narration', 'anime']) {
        final adapter = await VideoGenAdapterFactory.create(
          productionType: type,
        );
        expect(adapter, isA<KenBurnsVideoAdapter>(),
               reason: '$type 应零成本本地出片');
      }
    });

    test('drama 无 Key 时也回落到本地 Ken Burns', () async {
      final adapter = await VideoGenAdapterFactory.create(
        productionType: 'drama',
      );
      // 未配置可灵 Key 时不能把用户卡在云端路径上。
      expect(adapter, isA<KenBurnsVideoAdapter>());
    });

    test('未知引擎 id 回落到默认选择而不是崩溃', () async {
      final adapter = await ImageGenAdapterFactory.create(
        preferredEngineId: 'no-such-engine',
      );
      expect(adapter, isNotNull);
    });

    test('显式偏好 system-image 返回 SystemAiImageAdapter', () async {
      final adapter = await ImageGenAdapterFactory.create(
        preferredEngineId: 'system-image',
      );
      expect(adapter, isA<SystemAiImageAdapter>());
    });

    test('getSystemImageConfigSummary 正确反映配置状态', () {
      final summary = ImageGenAdapterFactory.getSystemImageConfigSummary();
      expect(summary, isNotNull);
    });
  });

  group('SystemAiImageAdapter HTTP 与解码细节', () {
    test('OpenAI 格式返回 data[0].b64_json 正确解析并写入文件', () async {
      final out = File('${AppPaths.root.path}/test_out.png');
      final dummyPngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]; // PNG 签名
      final b64 = base64Encode(dummyPngBytes);

      final adapter = SystemAiImageAdapter(
        baseUrl: 'https://api.openai.com/v1',
        model: 'dall-e-3',
        apiKey: 'sk-mock-key',
        httpFn: (req) async {
          expect(req.headers['Authorization'], 'Bearer sk-mock-key');
          expect(req.url.toString(), 'https://api.openai.com/v1/images/generations');
          return http.Response(
            jsonEncode({
              'data': [
                {'b64_json': b64}
              ]
            }),
            200,
          );
        },
      );

      final result = await adapter.generate(ImageGenRequest(
        prompt: 'a scenic mountain',
        shotNumber: 1,
        outputFile: out,
      ));

      expect(await result.exists(), isTrue);
      expect(await result.readAsBytes(), dummyPngBytes);
      if (await out.exists()) await out.delete();
    });

    test('遇到 HTTP 429 速率限制时自动退避重试，后续成功则正常返回', () async {
      final out = File('${AppPaths.root.path}/test_429_retry.png');
      final dummyPngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final b64 = base64Encode(dummyPngBytes);
      var callCount = 0;

      final adapter = SystemAiImageAdapter(
        baseUrl: 'https://api.openai.com/v1',
        model: 'dall-e-3',
        apiKey: 'sk-mock-key',
        retryBaseDelay: const Duration(milliseconds: 10),
        httpFn: (req) async {
          callCount++;
          if (callCount == 1) {
            return http.Response('{"error": {"message": "Rate limit reached"}}', 429);
          }
          return http.Response(
            jsonEncode({
              'data': [
                {'b64_json': b64}
              ]
            }),
            200,
          );
        },
      );

      final result = await adapter.generate(ImageGenRequest(
        prompt: 'a tranquil lake',
        shotNumber: 1,
        outputFile: out,
      ));

      expect(callCount, 2);
      expect(await result.exists(), isTrue);
      expect(await result.readAsBytes(), dummyPngBytes);
      if (await out.exists()) await out.delete();
    });

    test('HTTP 429 持续返回并在重试耗尽后抛出明确异常', () async {
      final out = File('${AppPaths.root.path}/test_429_exhausted.png');
      var callCount = 0;

      final adapter = SystemAiImageAdapter(
        baseUrl: 'https://api.openai.com/v1',
        model: 'dall-e-3',
        apiKey: 'sk-mock-key',
        retryBaseDelay: const Duration(milliseconds: 10),
        httpFn: (req) async {
          callCount++;
          return http.Response('{"error": {"message": "Rate limit exceeded"}}', 429);
        },
      );

      await expectLater(
        adapter.generate(ImageGenRequest(
          prompt: 'test exhausted',
          shotNumber: 1,
          outputFile: out,
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('429'),
        )),
      );

      expect(callCount, 4); // 初始 1 次 + 重试 3 次 = 4 次
      if (await out.exists()) await out.delete();
    });
  });

  group('SenseAudioImageAdapter 与尺寸吸附测试', () {
    test('snapToSupportedSenseAudioSize 针对工坊竖屏 1080x1920 完美吸附到 1152x2048', () {
      final size = SenseAudioImageAdapter.snapToSupportedSenseAudioSize(
        1080,
        1920,
        'senseaudio-image-2.0-260319',
      );
      expect(size, '1152x2048');
    });

    test('snapToSupportedSenseAudioSize 针对横屏 1920x1080 完美吸附到 2048x1152', () {
      final size = SenseAudioImageAdapter.snapToSupportedSenseAudioSize(
        1920,
        1080,
        'senseaudio-image-2.0-260319',
      );
      expect(size, '2048x1152');
    });

    test('snapToSupportedSenseAudioSize 针对正方形 1080x1080 完美吸附到 1024x1024', () {
      final size = SenseAudioImageAdapter.snapToSupportedSenseAudioSize(
        1080,
        1080,
        'senseaudio-image-2.0-260319',
      );
      expect(size, '1024x1024');
    });

    test('SenseAudio 同步生图正常解析 url 并下载', () async {
      final out = File('${AppPaths.root.path}/sense_out.png');
      final dummyPngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(150, 0)];

      final adapter = SenseAudioImageAdapter(
        baseUrl: 'https://api.senseaudio.cn/v1',
        model: 'senseaudio-image-2.0-260319',
        apiKey: 'mock-sense-key',
        httpFn: (req) async {
          if (req.url.path.endsWith('/image/sync')) {
            expect(req.headers['Authorization'], 'Bearer mock-sense-key');
            final body = jsonDecode(req.body) as Map;
            expect(body['model'], 'senseaudio-image-2.0-260319');
            expect(body['size'], '1152x2048'); // 经过吸附
            return http.Response(
              jsonEncode({'url': 'https://mock.cdn/img.png'}),
              200,
            );
          } else if (req.url.toString() == 'https://mock.cdn/img.png') {
            return http.Response.bytes(dummyPngBytes, 200);
          }
          throw StateError('Unexpected URL: ${req.url}');
        },
      );

      final result = await adapter.generate(ImageGenRequest(
        prompt: 'cyberpunk warrior portrait',
        shotNumber: 1,
        width: 1080,
        height: 1920,
        outputFile: out,
      ));

      expect(await result.exists(), isTrue);
      expect(await result.length(), dummyPngBytes.length);
      if (await out.exists()) await out.delete();
    });

    test('SenseAudio 参考图自动编码为 Data URI 并透传', () async {
      final refFile = File('${AppPaths.root.path}/mock_ref.png');
      await refFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03]);
      final out = File('${AppPaths.root.path}/sense_ref_out.png');
      final dummyPngBytes = List.filled(140, 1);

      bool refReceived = false;
      final adapter = SenseAudioImageAdapter(
        baseUrl: 'https://api.senseaudio.cn/v1',
        model: 'senseaudio-image-2.0-260319',
        apiKey: 'mock-sense-key',
        httpFn: (req) async {
          if (req.url.path.endsWith('/image/sync')) {
            final body = jsonDecode(req.body) as Map;
            final ref = body['reference'] as String?;
            if (ref != null && ref.startsWith('data:image/png;base64,')) {
              refReceived = true;
            }
            return http.Response(
              jsonEncode({'url': 'https://mock.cdn/ref_img.png'}),
              200,
            );
          } else if (req.url.toString() == 'https://mock.cdn/ref_img.png') {
            return http.Response.bytes(dummyPngBytes, 200);
          }
          throw StateError('Unexpected URL: ${req.url}');
        },
      );

      await adapter.generate(ImageGenRequest(
        prompt: 'consistent character with ref',
        shotNumber: 2,
        outputFile: out,
        referenceImages: [refFile.path],
      ));

      expect(refReceived, isTrue);
      if (await refFile.exists()) await refFile.delete();
      if (await out.exists()) await out.delete();
    });

    test('SenseAudio 同步遇 500000 繁忙时自动降级到异步轮询', () async {
      final out = File('${AppPaths.root.path}/sense_async_fallback.png');
      final dummyPngBytes = List.filled(200, 2);

      int pollCount = 0;
      final adapter = SenseAudioImageAdapter(
        baseUrl: 'https://api.senseaudio.cn/v1',
        model: 'senseaudio-image-2.0-260319',
        apiKey: 'mock-sense-key',
        httpFn: (req) async {
          if (req.url.path.endsWith('/image/sync')) {
            // 同步接口返回 500000 服务繁忙
            return http.Response(
              jsonEncode({'ref_code': '500000', 'message': '服务繁忙，请稍后再试'}),
              500,
            );
          } else if (req.url.path.endsWith('/image/async')) {
            return http.Response(
              jsonEncode({'task_id': 'async_task_999'}),
              200,
            );
          } else if (req.url.path.endsWith('/image/pending')) {
            pollCount++;
            expect(req.url.queryParameters['task_id'], 'async_task_999');
            if (pollCount == 1) {
              return http.Response(
                jsonEncode({'status': 'pending'}),
                200,
              );
            } else {
              return http.Response(
                jsonEncode({
                  'status': 'completed',
                  'url': 'https://mock.cdn/async_done.png',
                }),
                200,
              );
            }
          } else if (req.url.toString() == 'https://mock.cdn/async_done.png') {
            return http.Response.bytes(dummyPngBytes, 200);
          }
          throw StateError('Unexpected URL: ${req.url}');
        },
      );

      final result = await adapter.generate(ImageGenRequest(
        prompt: 'async fallback test',
        shotNumber: 3,
        outputFile: out,
      ));

      expect(await result.exists(), isTrue);
      expect(pollCount, greaterThanOrEqualTo(2));
      if (await out.exists()) await out.delete();
    });

    test('SystemAiImageAdapter 自动探测并分发 SenseAudio 专属协议', () async {
      final out = File('${AppPaths.root.path}/system_sense_dispatch.png');
      final dummyPngBytes = List.filled(160, 3);

      bool calledSenseEndpoint = false;
      final adapter = SystemAiImageAdapter(
        baseUrl: 'https://api.senseaudio.cn/v1',
        model: 'senseaudio-image-2.0-260319',
        apiKey: 'mock-sense-key',
        httpFn: (req) async {
          if (req.url.path.contains('/image/sync')) {
            calledSenseEndpoint = true;
            return http.Response(
              jsonEncode({'url': 'https://mock.cdn/dispatch.png'}),
              200,
            );
          } else if (req.url.toString() == 'https://mock.cdn/dispatch.png') {
            return http.Response.bytes(dummyPngBytes, 200);
          }
          throw StateError('Unexpected URL: ${req.url}');
        },
      );

      await adapter.generate(ImageGenRequest(
        prompt: 'auto dispatch test',
        shotNumber: 4,
        outputFile: out,
      ));

      expect(calledSenseEndpoint, isTrue);
      if (await out.exists()) await out.delete();
    });
  });

  group('片段级请求的多参考图契约', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('segment_ref_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File writeFakePng(String name) {
      // 1×1 透明 PNG。适配器只读字节转 base64，不解码内容。
      final file = File(p.join(tempDir.path, name));
      file.writeAsBytesSync(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]);
      return file;
    }

    test('SenseAudio content 数组首张 first_frame、其余 reference', () async {
      final ref1 = writeFakePng('char.png');
      final ref2 = writeFakePng('scene.png');
      Map<String, dynamic>? captured;

      final adapter = SenseAudioVideoAdapter(
        baseUrl: 'https://mock.senseaudio.local',
        model: 'doubao-seedance-2-0-260128',
        apiKey: 'mock-key',
        httpFn: (req) async {
          if (req.method == 'POST' && req.url.path == '/video/create') {
            captured = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'id': 'task-1'}), 200);
          }
          if (req.url.path == '/video/status') {
            return http.Response(
              jsonEncode({
                'data': {
                  'status': 'succeeded',
                  'video_url': 'https://mock.cdn/out.mp4',
                },
              }),
              200,
            );
          }
          // 下载分支：返回 4 个字节，够证明整条链路走通了。
          return http.Response.bytes(const [1, 2, 3, 4], 200);
        },
      );

      // 片段级形状：不带首帧，两张参考图 + 完整片段提示词。整条链路走 mock，
      // 不碰真实网络，所以 generateVideo 会正常返回而不是抛错。
      final output = File(p.join(tempDir.path, 'seg-1.mp4'));
      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: null,
          referenceImages: [ref1, ref2],
          promptZh: 'shot 1 | 回眸\nshot 2 | 走近',
          durationSec: 8,
          shotNumber: 1,
          outputFile: output,
        ),
      );

      expect(await output.exists(), isTrue);
      expect(captured, isNotNull,
          reason: '请求必须已经发出，否则后面的 payload 断言没有意义');
      final content = captured!['content'] as List;
      expect(content, hasLength(3), reason: 'text + 2 张图');
      expect((content[0] as Map)['type'], 'text');
      expect((content[0] as Map)['text'], contains('shot 1'));
      expect((content[1] as Map)['role'], 'first_frame');
      expect((content[2] as Map)['role'], 'reference');
      for (final item in content.skip(1)) {
        final url = (item as Map)['url'] as String;
        expect(url, startsWith('data:image/png;base64,'));
      }
    });

    test('effectivePrompt 优先用片段提示词而非运镜短语', () {
      final request = VideoGenRequest(
        inputImage: null,
        promptZh: 'shot 1 | 回眸，右手持有折叠刀',
        cameraMove: 'slow push-in',
        durationSec: 8,
        shotNumber: 1,
        outputFile: File(p.join(tempDir.path, 'x.mp4')),
      );
      expect(request.effectivePrompt, contains('折叠刀'));
      expect(request.effectivePrompt, isNot(contains('slow push-in')));
    });

    test('promptZh 为空时回退运镜短语', () {
      final request = VideoGenRequest(
        inputImage: writeFakePng('a.png'),
        cameraMove: 'slow push-in',
        durationSec: 5,
        shotNumber: 1,
        outputFile: File(p.join(tempDir.path, 'y.mp4')),
      );
      expect(request.effectivePrompt, 'slow push-in');
    });

    test('allImages 去重：首帧与参考图同一路径只出现一次', () {
      final same = writeFakePng('same.png');
      final request = VideoGenRequest(
        inputImage: same,
        referenceImages: [same, writeFakePng('other.png')],
        durationSec: 5,
        shotNumber: 1,
        outputFile: File(p.join(tempDir.path, 'z.mp4')),
      );
      expect(request.allImages, hasLength(2));
    });

    test('unwrap 取回内层适配器', () async {
      final inner = SenseAudioVideoAdapter(
        baseUrl: 'https://mock.local',
        model: 'doubao-seedance-2-0-260128',
        apiKey: 'k',
      );
      final wrapped = NormalizingVideoAdapter(
        inner,
        MediaCapabilityPresets.forModel('doubao-seedance-2-0-260128')!,
        modelId: 'doubao-seedance-2-0-260128',
      );
      expect(identical(wrapped.unwrap(), inner), isTrue);
      // id/label 透传，UI 上看到的还是同一个引擎。
      expect(wrapped.id, inner.id);
      expect(wrapped.label, inner.label);
    });

    test('规整超限被拒绝时不提交请求', () async {
      var called = false;
      final inner = SenseAudioVideoAdapter(
        baseUrl: 'https://mock.local',
        model: 'doubao-seedance-2-0-260128',
        apiKey: 'k',
        httpFn: (req) async {
          called = true;
          return http.Response('{}', 200);
        },
      );
      // 声明最多 1 张参考图，请求带 3 张 → 必须拒绝。
      final wrapped = NormalizingVideoAdapter(
        inner,
        const MediaModelCapability(
          maxReferenceImages: 1,
          supportsFirstFrame: true,
          isDeclared: true,
        ),
        modelId: 'doubao-seedance-2-0-260128',
      );

      final refs = List.generate(
        3,
        (i) => File(p.join(tempDir.path, 'r$i.png')),
      );
      for (final f in refs) {
        f.writeAsBytesSync(const [1, 2, 3]);
      }

      await expectLater(
        wrapped.generateVideo(
          VideoGenRequest(
            inputImage: null,
            referenceImages: refs,
            promptZh: 'shot 1',
            durationSec: 8,
            shotNumber: 1,
            outputFile: File(p.join(tempDir.path, 'out.mp4')),
          ),
        ),
        throwsA(isA<MediaCapabilityException>()),
      );
      expect(called, isFalse,
          reason: '被拒绝的请求绝不能到达网络层');
    });

    test('Ken Burns 无首帧时抛可读错误', () async {
      final adapter = KenBurnsVideoAdapter();
      // 不探测 FFmpeg 可用性：错误必须在探测之前抛出，否则测试会依赖本机
      // 是否装了 FFmpeg。
      await expectLater(
        adapter.generateVideo(
          VideoGenRequest(
            inputImage: null,
            referenceImages: [writeFakePng('r.png')],
            durationSec: 8,
            shotNumber: 1,
            outputFile: File(p.join(tempDir.path, 'kb.mp4')),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Ken Burns'),
              contains('首帧'),
            ),
          ),
        ),
      );
    });
  });

  /// Agnes 视频模式三态与参数化（spec: storyboard-visual-composition /
  /// media-model-capability-matrix）。
  ///
  /// 关键约束是**行为兼容**：不传 mode/sizeTier/ratio 时提交体必须与改动前
  /// 逐字一致。所以这里既有新形态的断言，也有一条锁旧形态的回归。
  group('Agnes 视频模式三态与参数化', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('agnes_mode_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// 造一张真实 PNG。尺寸守卫会解码并可能缩放，所以不能用字节桩——
    /// 只有能解码出宽高的图才能走到 resize/encodeJpg 分支。
    File writePng(String name, {int width = 800, int height = 1400}) {
      final image = img.Image(width: width, height: height);
      final file = File(p.join(tempDir.path, name));
      file.writeAsBytesSync(img.encodePng(image));
      return file;
    }

    /// 造一个走完整链路的 Agnes 适配器：创建→轮询→下载，全部 mock。
    /// 每次 [buildAdapter] 的创建请求 payload 落在哪。用一个持有者而不是
    /// 每个测试各自的局部变量：httpFn 是闭包，它引用的变量必须在它之前声明。
    final payloadHolder = <String, Map<String, dynamic>>{};

    /// 造一个走完整链路的 Agnes 适配器：创建→轮询→下载，全部 mock。
    AgnesVideoAdapter buildAdapter(
      Map<String, dynamic>? Function() readCaptured, {
      String model = 'agnes-video-2.5-flash',
      int createStatus = 200,
      String createBody = '{"video_id": "video_test_1"}',
    }) {
      final slot = <String, dynamic>{};
      payloadHolder['captured'] = slot;
      return AgnesVideoAdapter(
        apiKey: 'test-key',
        baseUrl: 'https://api.agnes-ai.cn/v1',
        model: model,
        httpFn: (req) async {
          if (req.method == 'POST' && req.url.path == '/v1/videos') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            slot
              ..clear()
              ..addAll(body);
            return http.Response(createBody, createStatus);
          }
          if (req.method == 'GET' && req.url.path == '/agnesapi') {
            return http.Response(
              '{"status": "completed", "progress": 100, '
              '"url": "https://mock.cdn/out.mp4"}',
              200,
            );
          }
          if (req.url.host == 'mock.cdn') {
            return http.Response.bytes(List<int>.filled(2048, 0), 200);
          }
          return http.Response('{}', 404);
        },
      );
    }

    test('仅尾帧 → keyframe 模式且带 last_frame，不要求首帧', () async {
      final adapter = buildAdapter(() => null);
      final last = writePng('last.png');

      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: null,
          lastFrameImage: last,
          promptZh: '人物走向窗边',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o1.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      expect(captured['mode'], 'keyframe');
      expect(captured['last_frame'], startsWith('data:image/'));
      expect(captured.containsKey('first_frame'), isFalse,
          reason: '只给了尾帧，payload 里不该出现 first_frame');
      expect(captured.containsKey('images'), isFalse);
    });

    test('首尾帧齐备 → 两个字段都在', () async {
      final adapter = buildAdapter(() => null);

      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: writePng('first.png'),
          lastFrameImage: writePng('last.png'),
          promptZh: '转身',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o2.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      expect(captured['mode'], 'keyframe');
      expect(captured['first_frame'], startsWith('data:image/'));
      expect(captured['last_frame'], startsWith('data:image/'));
    });

    test('仅参考图 → reference 模式提交 images，禁首尾帧', () async {
      final adapter = buildAdapter(() => null);
      final refs = [writePng('a.png'), writePng('b.png')];

      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: null,
          referenceImages: refs,
          promptZh: '以 <Picture 1> 为参考',
          durationSec: 5,
          shotNumber: 1,
          // 显式 reference：auto 推导下"只有参考图"仍走 keyframe（第一张
          // 参考图提升为首帧）——那是工坊片段级的既有行为，见 _deriveMode 注释。
          mode: AgnesVideoMode.reference,
          outputFile: File(p.join(tempDir.path, 'o3.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      expect(captured['mode'], 'reference');
      expect(captured['images'], isA<List>());
      expect((captured['images'] as List).length, 2);
      expect(captured.containsKey('first_frame'), isFalse);
      expect(captured.containsKey('last_frame'), isFalse);
    });

    test('auto 推导：片段级形状（多参考图无首帧）走 reference', () async {
      // 这是工坊 SegmentVideoGenTask 的形状，而它显式传的就是
      // AgnesVideoMode.reference。auto 与显式 reference 必须一致，否则同一种
      // 输入会因 mode 字段写没写而走两条不同协议——参考图本该以 <Picture N>
      // 指代，提成首帧会让第 2 张起彻底失去身份约束。
      final adapter = buildAdapter(() => null);

      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: null,
          referenceImages: [writePng('char.png'), writePng('scene.png')],
          promptZh: 'shot 1 | 回眸',
          durationSec: 8,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o3b.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      expect(captured['mode'], 'reference');
      expect(captured['images'], isA<List>());
      expect((captured['images'] as List).length, 2);
      expect(captured.containsKey('first_frame'), isFalse);
    });

    test('纯提示词 → text 模式且无任何媒体字段', () async {
      final adapter = buildAdapter(() => null);

      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: null,
          promptZh: '雨后的城市街道',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o4.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      expect(captured['mode'], 'text');
      for (final key in ['first_frame', 'last_frame', 'images']) {
        expect(captured.containsKey(key), isFalse,
            reason: 'text 模式不得携带 $key');
      }
    });

    test('首帧 + 参考图同时存在时拒绝提交，不发出请求', () async {
      var httpCalled = false;
      final adapter = AgnesVideoAdapter(
        apiKey: 'k',
        baseUrl: 'https://api.agnes-ai.cn/v1',
        model: 'agnes-video-2.5-flash',
        httpFn: (req) async {
          httpCalled = true;
          return http.Response('{}', 200);
        },
      );

      await expectLater(
        adapter.generateVideo(
          VideoGenRequest(
            inputImage: writePng('first.png'),
            referenceImages: [writePng('ref.png')],
            promptZh: 'x',
            durationSec: 5,
            shotNumber: 1,
            // 显式 keyframe + 参考图 = 官方明令禁止的组合。auto 下这个形状
            // 会走 keyframe 并把第一张参考图当首帧（工坊片段级的行为），
            // 所以冲突检测必须用显式模式才验得到。
            mode: AgnesVideoMode.keyframe,
            outputFile: File(p.join(tempDir.path, 'o5.mp4')),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('参考素材'), contains('不能同时使用')),
          ),
        ),
      );
      expect(httpCalled, isFalse,
          reason: '模式冲突必须在提交前拒绝——上游 400 只会给一句英文错误码');
    });

    test('非 Flash 型号的 sizeTier 原样归一为大写', () async {
      // 直接构造适配器（不走工厂）时没有规整层，这里验的是适配器自己的归一：
      // 非 Flash 型号才允许非 720P 档位（Flash 固定 720P 由下面的场景覆盖）。
      final adapter = buildAdapter(() => null, model: 'agnes-video-2.5');
      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: writePng('f.png'),
          promptZh: 'x',
          durationSec: 5,
          shotNumber: 1,
          sizeTier: '2k',
          outputFile: File(p.join(tempDir.path, 'o6.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      // size 大小写归一：请求写小写 '2k'，提交的是 Agnes 要求的大写 '2K'。
      expect(captured['size'], '2K');
    });

    test('Flash 型号不接受非 720P：规整层把它吸附掉', () async {
      final adapter = buildAdapter(() => null);
      // 经工厂的适配器被 NormalizingVideoAdapter 包着，规整层按
      // agnesVideo25Flash 的能力（resolutions: ['720p']）把 2K 吸成 720p，
      // 适配器再归一为大写。
      final wrapped = NormalizingVideoAdapter(
        adapter,
        MediaCapabilityPresets.forModel('agnes-video-2.5-flash')!,
        modelId: 'agnes-video-2.5-flash',
      );
      await wrapped.generateVideo(
        VideoGenRequest(
          inputImage: writePng('f.png'),
          promptZh: 'x',
          durationSec: 5,
          shotNumber: 1,
          sizeTier: '2k',
          outputFile: File(p.join(tempDir.path, 'o7.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      expect(captured['size'], '720P');
      expect(wrapped.lastChanges, isNotEmpty,
          reason: '吸附必须可见，否则用户以为参数生效了');
    });

    test('画幅比例随请求，不再写死 9:16', () async {
      final adapter = buildAdapter(() => null);
      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: writePng('f.png'),
          promptZh: 'x',
          durationSec: 5,
          shotNumber: 1,
          ratio: '16:9',
          outputFile: File(p.join(tempDir.path, 'o8.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      expect(captured['aspect_ratio'], '16:9');
    });

    test('seed 非空时进 payload', () async {
      final adapter = buildAdapter(() => null);
      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: writePng('f.png'),
          promptZh: 'x',
          durationSec: 5,
          shotNumber: 1,
          seed: 1101,
          outputFile: File(p.join(tempDir.path, 'o9.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      expect(captured['seed'], 1101);
    });

    test('行为兼容：不传新字段时 payload 与改动前逐字一致', () async {
      final adapter = buildAdapter(() => null);
      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: writePng('f.png'),
          cameraMove: 'slow push-in',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o10.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      // 这几个值就是改动前硬编码的那几个。任何一项变了，说明工坊主路径的
      // 提交体被本次改动影响了——那是必须被这条断言抓住的回归。
      expect(captured['size'], '720P');
      expect(captured['aspect_ratio'], '9:16');
      expect(captured['mode'], 'keyframe');
      expect(captured['seconds'], '5');
      expect(captured.containsKey('last_frame'), isFalse);
      expect(captured.containsKey('images'), isFalse);
      expect(captured.containsKey('seed'), isFalse);
    });

    test('尾帧尺寸过小被守卫拒绝', () async {
      final adapter = buildAdapter(() => null);
      await expectLater(
        adapter.generateVideo(
          VideoGenRequest(
            inputImage: null,
            lastFrameImage: writePng('tiny.png', width: 100, height: 100),
            promptZh: 'x',
            durationSec: 5,
            shotNumber: 1,
            outputFile: File(p.join(tempDir.path, 'o11.mp4')),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('不小于'),
          ),
        ),
      );
    });

    test('超大尾帧被缩放编码而不是原样提交', () async {
      final adapter = buildAdapter(() => null);
      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: null,
          lastFrameImage: writePng('huge.png', width: 4000, height: 6000),
          promptZh: 'x',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o12.mp4')),
        ),
      );

      final captured = payloadHolder['captured']!;
      final uri = captured['last_frame'] as String;
      // 守卫把超大图转成 JPEG：前缀从 image/png 变成 image/jpeg，且体积
      // 远小于原始 PNG。这条同时证明守卫对尾帧生效。
      expect(uri, startsWith('data:image/jpeg;base64,'));
    });
  });
}
