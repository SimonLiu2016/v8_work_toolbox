import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';


/// 生成一张 w×h 的纯色 PNG（测试用首帧）。
///
/// Agnes 对首帧边长有 256–5760 的硬校验，所以测试图不能再用 1x1 微型图。
List<int> _makePng(int w, int h) {
  List<int> be32(int v) =>
      [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];

  int crc32(List<int> data) {
    var c = 0xffffffff;
    for (final b in data) {
      c ^= b;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
      }
    }
    return c ^ 0xffffffff;
  }

  List<int> chunk(String type, List<int> data) {
    final crcInput = <int>[...type.codeUnits, ...data];
    return <int>[
      ...be32(data.length),
      ...type.codeUnits,
      ...data,
      ...be32(crc32(crcInput)),
    ];
  }

  final ihdr = <int>[...be32(w), ...be32(h), 8, 2, 0, 0, 0];
  final raw = <int>[];
  for (var y = 0; y < h; y++) {
    raw.add(0);
    for (var x = 0; x < w; x++) {
      raw.addAll(const [200, 120, 60]);
    }
  }
  // IDAT 用 ZLib 压缩。曾手写过 zlib stored block，字节数对但解码失败——
  // 压缩格式不是能靠"看起来对"蒙过去的东西，用现成的编码器。
  final idat = ZLibEncoder().encode(raw);

  return <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', idat),
    ...chunk('IEND', const <int>[]),
  ];
}

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
      // 300x300 的合法 PNG：Agnes 要求首帧边长 256–5760 像素，
      // 以前这里用 1x1 微型图，新增尺寸守卫后它会被本地拒绝——
      // 那正是守卫该做的事，但会让我们测不到后面的轮询逻辑。
      dummyInputImage.writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
            .replaceFirst('AAAACXBIWXMAAA', 'x'),
      ));
      // 上面那串是 1x1；真正写入的是下面这张 300x300 纯色图。
      dummyInputImage.writeAsBytesSync(_makePng(300, 300));
      dummyOutputFile = File(p.join(tempDir.path, 'agnes_shot_001.mp4'));
    });

    test('遇到 429 上游负载饱和时自动重试并最终成功', () async {
      var postAttempts = 0;
      Map<String, dynamic>? capturedPayload;

      final adapter = AgnesVideoAdapter(
        baseUrl: 'https://api.agnes-ai.cn/v1',
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
            // video_id 才是查询要用的字段；id / task_id 只是任务标识。
            // 这里刻意只给 video_id，验适配器没有拿错字段。
            return http.Response(
              jsonEncode({
                'id': 'task_agnes_ok_1',
                'task_id': 'task_agnes_ok_1',
                'video_id': 'video_agnes_ok_1',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          } else {
            // GET /agnesapi?... 是主查询路径（文档推荐），必须带 model_name。
            if (req.url.path == '/agnesapi') {
              expect(
                req.url.queryParameters['video_id'],
                'video_agnes_ok_1',
                reason: '查询必须用 video_id，不是 task_id',
              );
              expect(
                req.url.queryParameters['model_name'],
                'agnes-video-2.5-flash',
                reason: 'keyframe 模式查询必须带 model_name',
              );
              // 顶层 status / progress / url——Agnes 的字段不在 data 下。
              return http.Response(
                jsonEncode({
                  'status': 'completed',
                  'progress': 100,
                  'internal_status': 'pending',
                  'internal_progress': 0,
                  'url': 'https://cdn.agnes-ai.cn/output.mp4',
                }),
                200,
              );
            }
            // 下载：顶层 url 指向的临时地址。这里的假字节串只有 19 字节，
            // 低于适配器的 1024 完整性下限，所以补足长度——不然下载校验会
            // 以「文件异常」拒绝，测的就不是轮询逻辑了。
            if (req.url.host == 'cdn.agnes-ai.cn') {
              return http.Response('video-bytes-success${'x' * 1100}', 200);
            }
            return http.Response('not found', 404);
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
      // Flash 的 size 必须固定 "720P"——传其他值 Agnes 直接 400。
      // 旧实现根本不传 size，靠协议默认；文档明确这是硬校验，故显式传。
      expect(capturedPayload!['size'], equals('720P'));
      expect(result.existsSync(), isTrue);
      expect(result.readAsStringSync(), startsWith('video-bytes-success'));
    });

    test('遇到网关坏节点丢弃参数报 400 时自动轮询换路重试并成功', () async {
      var postAttempts = 0;

      final adapter = AgnesVideoAdapter(
        baseUrl: 'https://api.agnes-ai.cn/v1',
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
                'video_id': 'video_recovered_ok_2',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          } else {
            if (req.url.path == '/agnesapi') {
              return http.Response(
                jsonEncode({'status': 'completed', 'url': 'https://cdn.agnes-ai.cn/rec.mp4'}),
                200,
              );
            }
            if (req.url.host == 'cdn.agnes-ai.cn') {
              return http.Response('video-retry-recovered-mp4${'x' * 1100}', 200);
            }
            return http.Response('not found', 404);
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
      expect(result.readAsStringSync(), startsWith('video-retry-recovered-mp4'));
    });

    test('分镜图片不存在时自适应回退到 mode: text', () async {
      final nonExistentImage = File(p.join(tempDir.path, 'no_such_file.png'));
      Map<String, dynamic>? capturedPayload;

      final adapter = AgnesVideoAdapter(
        baseUrl: 'https://api.agnes-ai.cn/v1',
        model: 'agnes-video-2.5-flash',
        apiKey: 'sk-test-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            capturedPayload = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'video_id': 'video_text_mode',
              }),
              200,
            );
          } else {
            if (req.url.path == '/agnesapi') {
              return http.Response(
                jsonEncode({'status': 'completed', 'url': 'https://cdn.agnes-ai.cn/text.mp4'}),
                200,
              );
            }
            if (req.url.host == 'cdn.agnes-ai.cn') {
              return http.Response('video-text-success${'x' * 1100}', 200);
            }
            return http.Response('not found', 404);
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
      expect(result.readAsStringSync(), startsWith('video-text-success'));
    });

    // --- 2026-10-13 实测驱动的四条修正 --------------------------------
    //
    // 这四条全部来自真实 API Key 的调用记录，不是文档推断。文档与实现的
    // 分歧见 design.md 的 Context 表。它们守的都是"积分损失路径"——
    // 任何一个失效，用户都会遇到"钱花了、视频没拿到"。

    test('HTTP 200 的限流错误体被识别并退避，不被当作任务状态', () async {
      // Agnes 的限流返回 HTTP 200 + {"error":{"code":429,...}}，
      // 不是 HTTP 429 状态码。只判状态码会把错误体当正常响应读下去。
      var queryCount = 0;
      var rateLimitBodies = 0;

      final adapter = AgnesVideoAdapter(
        baseUrl: 'https://api.agnes-ai.cn/v1',
        model: 'agnes-video-2.5-flash',
        apiKey: 'sk-test-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            return http.Response('{"video_id": "video_rl"}', 200);
          }
          if (req.url.path == '/agnesapi') {
            queryCount++;
            // 前两次返回限流错误体，第三次开始正常。
            if (queryCount <= 2) {
              rateLimitBodies++;
              return http.Response(
                jsonEncode({
                  'error': {'code': 429, 'message': '查询过于频繁，请稍后重试'},
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'status': 'completed',
                'progress': 100,
                'started_at': 1791867536,
                'url': 'https://cdn.agnes-ai.cn/rl.mp4',
              }),
              200,
            );
          }
          if (req.url.host == 'cdn.agnes-ai.cn') {
            return http.Response('video-after-ratelimit${'x' * 1100}', 200);
          }
          return http.Response('not found', 404);
        },
      );

      final result = await adapter.generateVideo(VideoGenRequest(
        inputImage: dummyInputImage,
        cameraMove: 'pan',
        durationSec: 4,
        shotNumber: 1,
        outputFile: dummyOutputFile,
      ));

      expect(rateLimitBodies, 2, reason: '两次限流都应被识别，而不是静默跳过');
      expect(result.readAsStringSync(), startsWith('video-after-ratelimit'));
    });

    test('兜底查询路径从 metadata.url 取视频地址', () async {
      // 主路径 /agnesapi 的 url 在顶层；兜底路径 /v1/videos/<id> 的 url
      // 在 metadata.url。共用一套顶层读取会读到空，然后空转到预算耗尽。
      final adapter = AgnesVideoAdapter(
        baseUrl: 'https://api.agnes-ai.cn/v1',
        model: 'agnes-video-2.5-flash',
        apiKey: 'sk-test-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            return http.Response('{"video_id": "video_fb"}', 200);
          }
          // 主路径一律不可用，强制走兜底。
          if (req.url.path == '/agnesapi') {
            return http.Response('gateway error', 502);
          }
          if (req.url.path == '/v1/videos/video_fb') {
            return http.Response(
              jsonEncode({
                'status': 'completed',
                'progress': 100,
                'started_at': 1791867536,
                'metadata': {'url': 'https://cdn.agnes-ai.cn/fb.mp4'},
              }),
              200,
            );
          }
          if (req.url.host == 'cdn.agnes-ai.cn') {
            return http.Response('video-from-fallback${'x' * 1100}', 200);
          }
          return http.Response('not found', 404);
        },
      );

      final result = await adapter.generateVideo(VideoGenRequest(
        inputImage: dummyInputImage,
        cameraMove: 'pan',
        durationSec: 4,
        shotNumber: 1,
        outputFile: dummyOutputFile,
      ));

      expect(result.readAsStringSync(), startsWith('video-from-fallback'));
    });

    test('阶段切换以 started_at 为准，不依赖状态字符串', () async {
      // 实测状态有五态：queued / pending / in_progress / completed /
      // failed。文档漏了 pending。用 started_at 做信号则新状态值不影响我们。
      var queryCount = 0;
      final adapter = AgnesVideoAdapter(
        baseUrl: 'https://api.agnes-ai.cn/v1',
        model: 'agnes-video-2.5-flash',
        apiKey: 'sk-test-key',
        httpFn: (req) async {
          if (req.method == 'POST') {
            return http.Response('{"video_id": "video_ph"}', 200);
          }
          if (req.url.path == '/agnesapi') {
            queryCount++;
            if (queryCount <= 3) {
              // pending：started_at 为 null。文档没提这个状态。
              return http.Response(
                jsonEncode({'status': 'pending', 'progress': 0, 'started_at': null}),
                200,
              );
            }
            // 一个文档外的新状态，但 started_at 已非空——应视为生成中。
            return http.Response(
              jsonEncode({
                'status': 'initializing',
                'progress': 5,
                'started_at': 1791867536,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        },
      );

      // 只跑一小会就取消——我们要验的是"未知状态不导致失败"，
      // 不是等它跑完。轮询间隔 2 秒，300ms 只够发起创建、不够第一次查询，
      // 所以给到 2.6 秒：至少跨过一次查询。
      final fut = adapter.generateVideo(VideoGenRequest(
        inputImage: dummyInputImage,
        cameraMove: 'pan',
        durationSec: 4,
        shotNumber: 1,
        outputFile: dummyOutputFile,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      adapter.cancelCurrent();
      await expectLater(fut, throwsA(isA<StateError>()));
      expect(queryCount, greaterThanOrEqualTo(1),
          reason: 'pending 与文档外的 initializing 都应继续轮询，不得判失败');
    });

    test('首帧边长小于 256 时本地拒绝，不把供应商错误透出', () async {
      final tiny = File(p.join(tempDir.path, 'tiny_frame.png'))
        ..writeAsBytesSync(_makePng(100, 100));

      final adapter = AgnesVideoAdapter(
        baseUrl: 'https://api.agnes-ai.cn/v1',
        model: 'agnes-video-2.5-flash',
        apiKey: 'sk-test-key',
        httpFn: (req) async => http.Response('{}', 200),
      );

      Object? caught;
      try {
        await adapter.generateVideo(VideoGenRequest(
          inputImage: tiny,
          cameraMove: 'pan',
          durationSec: 4,
          shotNumber: 1,
          outputFile: dummyOutputFile,
        ));
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<StateError>());
      final msg = (caught as StateError).message.toString();
      expect(msg, contains('尺寸过小'));
      expect(msg, isNot(contains('first_frame')),
          reason: '供应商的错误指向 first_frame 参数，用户看不出是图太小');
    });
  });
}
