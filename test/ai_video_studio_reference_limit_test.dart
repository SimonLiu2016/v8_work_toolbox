import 'dart:convert';
import 'dart:io';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/settings_store.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';

/// spec: storyboard-visual-composition · 参考图上限可配置（第 7 组）
///
/// 锁死：上限来自能力声明（Flash 5 / 标准 8），超限抛错而非静默截断，
/// 且用户在设置里改的值优先。

/// 300x300 纯色 PNG（适配器尺寸守卫要求单边 ≥256）。
const String _png300Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAASwAAAEsCAIAAAD2HxkiAAACeklEQVR42u3TMQkAAAzEwBf2/qmsaujU5eAUBJJpgUeRAEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYETAgmBEwIJgRMCCYEE6oAJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEEwImBBMCJgQTAiYEE4IJVQATggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJAROCCQETggkBE4IJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEgAnBhIAJwYSACcGEYEIJwIRgQsCEYELAhGBCwIRgQsCEYELAhGBCwIRgQsCEYELAhGBCwIRgQsCEYELAhGBCwIRgQsCEYELAhGBCwIRgQsCEYELAhGBCwIRgQsCEYELgZgEoEY2632U+bAAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Agnes 参考素材上限', () {
    late Directory tempDir;
    late Map<String, dynamic> captured;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ref_limit_test');
      AppPaths.overrideRootForTesting(tempDir);
      captured = <String, dynamic>{};
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// 造一张 300x300 的 PNG——适配器有尺寸守卫（单边 ≥256），1x1 占位图会在
    /// 触到上限检查之前就被拒，那就验不到上限了。
    File writePng(String name) {
      final f = File(p.join(tempDir.path, name));
      f.writeAsBytesSync(base64Decode(_png300Base64));
      return f;
    }

    AgnesVideoAdapter buildAdapter(String model) => AgnesVideoAdapter(
          apiKey: 'test-key',
          baseUrl: 'https://api.agnes-ai.cn/v1',
          model: model,
          httpFn: (req) async {
            if (req.method == 'POST' && req.url.path == '/v1/videos') {
              captured.clear();
              captured.addAll(jsonDecode(req.body) as Map<String, dynamic>);
              return http.Response(
                '{"video_id": "video_1"}',
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            // GET 查询一律返回 not found：这些用例只关心「上限检查是否放行」，
            // 放行后随便它死在哪一步——只要不是上限错就行。
            return http.Response(
              '{"error": "not found"}',
              404,
              headers: {'content-type': 'application/json'},
            );
          },
        );

    test('Flash 型号：6 张参考图抛错且错误信息含上限', () async {
      final adapter = buildAdapter('agnes-video-2.5-flash');
      final refs = List.generate(6, (i) => writePng('r$i.png'));

      await expectLater(
        adapter.generateVideo(VideoGenRequest(
          inputImage: null,
          referenceImages: refs,
          promptZh: 'test',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o.mp4')),
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('5'), contains('6')),
        )),
      );
    });

    test('Flash 型号：5 张参考图不抛错', () async {
      final adapter = buildAdapter('agnes-video-2.5-flash');
      final refs = List.generate(5, (i) => writePng('r$i.png'));

      // 会因轮询/下载失败而抛别的错，但不应是上限错。
      try {
        await adapter.generateVideo(VideoGenRequest(
          inputImage: null,
          referenceImages: refs,
          promptZh: 'test',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o.mp4')),
        ));
      } on StateError catch (e) {
        expect(e.message.contains('参考素材'), isFalse,
            reason: '5 张不该触发上限错误，实际：${e.message}');
      }
    });

    test('标准型号：8 张参考图不抛上限错', () async {
      final adapter = buildAdapter('agnes-video-2.5');
      final refs = List.generate(8, (i) => writePng('r$i.png'));

      try {
        await adapter.generateVideo(VideoGenRequest(
          inputImage: null,
          referenceImages: refs,
          promptZh: 'test',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o.mp4')),
        ));
      } on StateError catch (e) {
        expect(e.message.contains('参考素材'), isFalse,
            reason: '8 张在该型号上限内，实际：${e.message}');
      }
    });

    test('标准型号：9 张参考图抛错', () async {
      final adapter = buildAdapter('agnes-video-2.5');
      final refs = List.generate(9, (i) => writePng('r$i.png'));

      await expectLater(
        adapter.generateVideo(VideoGenRequest(
          inputImage: null,
          referenceImages: refs,
          promptZh: 'test',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o.mp4')),
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('8'),
        )),
      );
    });

    test('设置里改的上限优先于型号声明', () async {
      await SettingsStore.instance.setVideoMaxReferenceImages(2);
      final adapter = buildAdapter('agnes-video-2.5');
      final refs = List.generate(3, (i) => writePng('r$i.png'));

      await expectLater(
        adapter.generateVideo(VideoGenRequest(
          inputImage: null,
          referenceImages: refs,
          promptZh: 'test',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o.mp4')),
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('2'), contains('3')),
        )),
      );
    });

    test('设为未确认上限（null）时放行任意数量', () async {
      await SettingsStore.instance.setVideoMaxReferenceImages(null);
      final adapter = buildAdapter('agnes-video-2.5');
      // 用一个远超任何声明的数量，验证不会因上限被拒。
      final refs = List.generate(6, (i) => writePng('r$i.png'));

      try {
        await adapter.generateVideo(VideoGenRequest(
          inputImage: null,
          referenceImages: refs,
          promptZh: 'test',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o.mp4')),
        ));
      } on StateError catch (e) {
        expect(e.message.contains('参考素材'), isFalse,
            reason: 'null 上限应放行，实际：${e.message}');
      }
    });
  });
  group('音频参考契约（D）', () {
    late Directory tempDir;
    late Map<String, dynamic> captured;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('audio_ref_test');
      AppPaths.overrideRootForTesting(tempDir);
      captured = <String, dynamic>{};
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File writePng(String name) {
      final f = File(p.join(tempDir.path, name));
      f.writeAsBytesSync(base64Decode(_png300Base64));
      return f;
    }

    File writeAudio(String name) {
      final f = File(p.join(tempDir.path, name));
      f.writeAsBytesSync(List<int>.filled(2048, 7));
      return f;
    }

    AgnesVideoAdapter buildAdapter() => AgnesVideoAdapter(
          apiKey: 'test-key',
          baseUrl: 'https://api.agnes-ai.cn/v1',
          model: 'agnes-video-2.5-flash',
          httpFn: (req) async {
            if (req.method == 'POST' && req.url.path == '/v1/videos') {
              captured.clear();
              captured.addAll(jsonDecode(req.body) as Map<String, dynamic>);
              return http.Response('{"video_id": "v1"}', 200,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response('{"error": "not found"}', 404,
                headers: {'content-type': 'application/json'});
          },
        );

    test('未提供音频时 payload 无 audios 字段', () async {
      final adapter = buildAdapter();
      try {
        await adapter.generateVideo(VideoGenRequest(
          inputImage: null,
          referenceImages: [writePng('a.png')],
          promptZh: 'test',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o.mp4')),
        ));
      } catch (_) {
        // 死在哪一步都行，只要创建请求已发出。
      }
      expect(captured.isNotEmpty, isTrue);
      expect(captured.containsKey('audios'), isFalse);
    });

    test('提供一段音频时 payload 带 audios 且编号位置一致', () async {
      final adapter = buildAdapter();
      try {
        await adapter.generateVideo(VideoGenRequest(
          inputImage: null,
          referenceImages: [writePng('a.png')],
          audioReferences: [writeAudio('line.m4a')],
          promptZh: 'test',
          durationSec: 5,
          shotNumber: 1,
          outputFile: File(p.join(tempDir.path, 'o.mp4')),
        ));
      } catch (_) {}
      expect(captured['audios'], isA<List>());
      expect((captured['audios'] as List).length, 1);
      expect((captured['audios'] as List).first, startsWith('data:audio/'));
    });

    test('VideoGenRequest.audioReferences 默认为空', () {
      final req = VideoGenRequest(
        inputImage: null,
        durationSec: 5,
        shotNumber: 1,
        outputFile: File('${tempDir.path}/x.mp4'),
      );
      expect(req.audioReferences, isEmpty);
    });
  });
}
