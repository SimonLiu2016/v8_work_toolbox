import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/agnes_playground/models/playground_models.dart';
import 'package:V8WorkToolbox/tools/agnes_playground/services/playground_store.dart';

/// 试炼场快照层的回归。
///
/// 守两条核心性质：
/// 1. **自包含**——参考图是副本，原文件删掉后快照仍能回看"喂了什么"；
/// 2. **失败也留痕**——失败的那次同样记录了请求，排查时才不会只剩一个谜。
void main() {
  group('PlaygroundStore', () {
    late Directory tempDir;
    late Directory sourceDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('playground_store_test');
      AppPaths.overrideRootForTesting(tempDir);
      PlaygroundStore.instance.resetForTesting();
      sourceDir = Directory(p.join(tempDir.path, 'src'))
        ..createSync(recursive: true);
    });

    tearDown(() {
      PlaygroundStore.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File writePng(String name, {int width = 800, int height = 1400}) {
      final image = img.Image(width: width, height: height);
      final file = File(p.join(sourceDir.path, name));
      file.writeAsBytesSync(img.encodePng(image));
      return file;
    }


    test('快照写入/读取往返', () async {
      final turn = await PlaygroundStore.instance.record(
        channel: PlaygroundChannel.video,
        providerId: 'p1',
        providerName: 'Agnes',
        model: 'agnes-video-2.5-flash',
        prompt: '一只橘猫跳上窗台',
        params: const {'seconds': '5', 'size': '720P'},
        media: [
          (file: writePng('first.png'), role: PlaygroundMediaRole.firstFrame),
        ],
        invoke: (outDir) async {
          final f = File(p.join(outDir.path, 'video.mp4'));
          await f.writeAsString('fake-mp4', flush: true);
          return const PlaygroundCallOutcome(
            status: PlaygroundTurnStatus.completed,
            outputFileName: 'video.mp4',
            outputBytes: 7,
          );
        },
      );

      expect(turn.status, PlaygroundTurnStatus.completed);
      expect(turn.media, hasLength(1));
      expect(turn.media.first.width, 800);
      expect(turn.media.first.height, 1400);
      expect(turn.media.first.role, PlaygroundMediaRole.firstFrame);

      // 重新加载（模拟重启）
      PlaygroundStore.instance.resetForTesting();
      await PlaygroundStore.instance.ensureLoaded();
      final reloaded = PlaygroundStore.instance.turns;
      expect(reloaded, hasLength(1));
      expect(reloaded.first.id, turn.id);
      expect(reloaded.first.prompt, '一只橘猫跳上窗台');
      expect(reloaded.first.media.single.width, 800);
    });

    test('参考图是副本：原文件删除后快照仍显示', () async {
      final original = writePng('ref.png');
      await PlaygroundStore.instance.record(
        channel: PlaygroundChannel.video,
        providerId: 'p1',
        providerName: 'Agnes',
        model: 'agnes-video-2.5-flash',
        prompt: 'x',
        params: const {},
        media: [
          (file: original, role: PlaygroundMediaRole.reference),
        ],
        invoke: (outDir) async {
          final f = File(p.join(outDir.path, 'video.mp4'));
          await f.writeAsString('v', flush: true);
          return const PlaygroundCallOutcome(
            status: PlaygroundTurnStatus.completed,
            outputFileName: 'video.mp4',
            outputBytes: 1,
          );
        },
      );

      final stored = PlaygroundStore.instance.turns.single;
      final copy = PlaygroundStore.instance.mediaFile(
        stored,
        stored.media.single,
      );
      expect(copy.existsSync(), isTrue,
          reason: '快照必须持有副本，不能只记原路径');

      // 删掉原文件——副本必须还在
      original.deleteSync();
      expect(copy.existsSync(), isTrue,
          reason: '自包含是快照的核心性质，原文件消失不能让它变残');
    });

    test('失败调用也留快照，含请求参数与错误', () async {
      final turn = await PlaygroundStore.instance.record(
        channel: PlaygroundChannel.video,
        providerId: 'p1',
        providerName: 'Agnes',
        model: 'agnes-video-2.5-flash',
        prompt: '会失败的提示词',
        params: const {'seconds': '5'},
        media: const [],
        invoke: (outDir) async => throw StateError('上游 400: 参数不合法'),
      );

      expect(turn.status, PlaygroundTurnStatus.failed);
      expect(turn.error, contains('400'));
      expect(turn.prompt, '会失败的提示词',
          reason: '失败的那次同样要记下发了什么');
      expect(turn.params['seconds'], '5');
      expect(turn.outputFileName, isNull);
    });

    test('脱敏请求体视图不展开 base64', () async {
      final turn = await PlaygroundStore.instance.record(
        channel: PlaygroundChannel.video,
        providerId: 'p1',
        providerName: 'Agnes',
        model: 'agnes-video-2.5-flash',
        prompt: '人物从首帧姿态转身',
        params: const {
          'mode': 'keyframe',
          'seconds': '5',
          'size': '720P',
          'aspect_ratio': '9:16',
        },
        media: [
          (file: writePng('f.png'), role: PlaygroundMediaRole.firstFrame),
          (file: writePng('l.png'), role: PlaygroundMediaRole.lastFrame),
        ],
        invoke: (outDir) async {
          final f = File(p.join(outDir.path, 'video.mp4'));
          await f.writeAsString('v', flush: true);
          return const PlaygroundCallOutcome(
            status: PlaygroundTurnStatus.completed,
            outputFileName: 'video.mp4',
            outputBytes: 1,
          );
        },
      );

      final view = turn.renderRedactedRequest();
      expect(view, contains('prompt: 人物从首帧姿态转身'));
      expect(view, contains('mode: keyframe'));
      expect(view, contains('size: 720P'));
      expect(view, contains('aspect_ratio: 9:16'));
      expect(view, contains('first_frame: <'));
      expect(view, contains('last_frame: <'));
      expect(view, contains('800×1400'));
      // 关键：绝不能出现完整编码数据
      expect(view, isNot(contains('base64,')));
      expect(view.length, lessThan(2000),
          reason: '脱敏视图的价值就在于短——展开 87KB 数据等于没有视图');
    });

    test('updateTurn 改状态与产物，但不动请求字段', () async {
      final turn = await PlaygroundStore.instance.record(
        channel: PlaygroundChannel.video,
        providerId: 'p1',
        providerName: 'Agnes',
        model: 'agnes-video-2.5-flash',
        prompt: '原始提示词',
        params: const {'seconds': '5'},
        media: const [],
        invoke: (outDir) async => const PlaygroundCallOutcome(
          status: PlaygroundTurnStatus.cloudProcessing,
          remoteTaskId: 'video_abc',
          error: '本地预算耗尽',
        ),
      );

      await PlaygroundStore.instance.updateTurn(
        turn.id,
        status: PlaygroundTurnStatus.completed,
        outputFileName: 'video.mp4',
        error: null,
      );

      final updated = PlaygroundStore.instance.turns.single;
      expect(updated.status, PlaygroundTurnStatus.completed);
      expect(updated.outputFileName, 'video.mp4');
      expect(updated.error, isNull);
      // 不可变字段必须原样——它们记录"当时发了什么"
      expect(updated.prompt, '原始提示词');
      expect(updated.params['seconds'], '5');
    });

    test('pruneOld 不动云端处理中的轮次', () async {
      final done = await PlaygroundStore.instance.record(
        channel: PlaygroundChannel.video,
        providerId: 'p1',
        providerName: 'Agnes',
        model: 'm',
        prompt: 'x',
        params: const {},
        media: const [],
        invoke: (outDir) async => const PlaygroundCallOutcome(
          status: PlaygroundTurnStatus.completed,
          outputFileName: 'video.mp4',
          outputBytes: 1,
        ),
      );
      final pending = await PlaygroundStore.instance.record(
        channel: PlaygroundChannel.video,
        providerId: 'p1',
        providerName: 'Agnes',
        model: 'm',
        prompt: 'y',
        params: const {},
        media: const [],
        invoke: (outDir) async => const PlaygroundCallOutcome(
          status: PlaygroundTurnStatus.cloudProcessing,
          remoteTaskId: 'video_x',
        ),
      );

      // 把两条都改成 10 天前：用 backdate 不存在于本 store，直接改索引文件
      // 太绕——改为把窗口设成负数，让所有条目都"过期"。
      final pruned = await PlaygroundStore.instance.pruneOld(
        const Duration(days: -1),
      );

      expect(pruned, 1, reason: '只清理已终结的');
      final remaining = PlaygroundStore.instance.turns;
      expect(remaining.map((t) => t.id), [pending.id]);
      expect(remaining.single.id, isNot(done.id));
    });

    test('索引文件损坏时以空库启动而不是抛异常', () async {
      await PlaygroundStore.instance.ensureLoaded();
      final file = AppPaths.agnesPlaygroundIndexFile;
      await file.parent.create(recursive: true);
      await file.writeAsString('{ 这不是合法 JSON', flush: true);

      PlaygroundStore.instance.resetForTesting();
      // 不抛异常即是契约
      await PlaygroundStore.instance.ensureLoaded();
      expect(PlaygroundStore.instance.turns, isEmpty);
    });

    test('PlaygroundTurn 序列化往返含全部字段', () {
      final original = PlaygroundTurn(
        id: 'turn_1',
        channel: PlaygroundChannel.image,
        providerId: 'p',
        providerName: 'Agnes',
        model: 'agnes-image-2.5-flash',
        prompt: '向日葵',
        params: const {'size': '2K'},
        media: const [
          PlaygroundMedia(
            fileName: '0_a.png',
            originalName: 'a.png',
            role: PlaygroundMediaRole.reference,
            width: 100,
            height: 200,
            bytes: 4096,
          ),
        ],
        outputFileName: 'image.png',
        outputBytes: 2048,
        remoteTaskId: '',
        status: PlaygroundTurnStatus.completed,
        durationMs: 1234,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final decoded = PlaygroundTurn.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(decoded, isNotNull);
      expect(decoded!.id, original.id);
      expect(decoded.channel, PlaygroundChannel.image);
      expect(decoded.media.single.width, 100);
      expect(decoded.media.single.role, PlaygroundMediaRole.reference);
      expect(decoded.status, PlaygroundTurnStatus.completed);
      expect(decoded.durationMs, 1234);
    });

    test('解析失败的条目被跳过而不是让整份索引失效', () {
      expect(PlaygroundTurn.fromJson({'no_id': true}), isNull);
      expect(PlaygroundTurn.fromJson({'id': 'x', 'channel': 'bogus'}), isNull);
    });
  });
}
